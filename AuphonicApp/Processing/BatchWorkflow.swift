import Foundation
import AVFoundation

/// Batch engine: for every file in every configured group, extracts the
/// selected channels (packed into stereo/mono uploads), runs one Auphonic
/// production per upload, downloads the processed audio and writes it back
/// into an untouched copy of the original file in the destination folder.
@MainActor
@Observable
final class BatchWorkflow {
    private(set) var isRunning = false
    private(set) var statusText = "Ready"
    private(set) var completedCount = 0
    private(set) var totalCount = 0
    private(set) var lastOutputDirectory: URL?

    /// Overall progress 0-1 (-1 = hidden)
    var overallProgress: Double {
        guard isRunning, totalCount > 0 else { return -1 }
        return Double(completedCount) / Double(totalCount)
    }

    private let apiClient: AuphonicAPIClient
    private var runTask: Task<Void, Never>?

    /// Housekeeping: delete each file's productions on Auphonic once its
    /// output has been written successfully (failed files keep theirs)
    var deleteProductionsAfterDownload = false

    /// Cap the uploaded audio per job (seconds). Used by the settings test
    /// drive to never upload more than Auphonic's 3-minute billing minimum.
    var maxUploadDuration: Double?

    /// Max simultaneous Auphonic productions per file
    private static let maxConcurrentJobs = 3
    private static let pollInterval: Duration = .seconds(2)
    private static let pollTimeout: TimeInterval = 3600
    /// Consecutive failed status polls tolerated before the file fails
    /// (about 30 s of an unreachable server at the 2 s interval)
    static let maxConsecutivePollFailures = 15

    /// Whether a failed status poll can be retried. Transport errors and
    /// server errors usually pass; a rejected token or a production that no
    /// longer exists will not, and used to be polled for the full hour.
    nonisolated static func isRetryablePollError(_ error: Error) -> Bool {
        switch error {
        case AuphonicAPIClient.APIError.noToken, AuphonicAPIClient.APIError.invalidToken:
            return false
        case AuphonicAPIClient.APIError.httpError(let code, _):
            return code != 404
        default:
            return true
        }
    }

    /// Tracks failed polls in a row; `record` throws once the poll should stop.
    struct PollFailures {
        private(set) var consecutive = 0

        mutating func reset() { consecutive = 0 }

        mutating func record(_ error: Error) throws {
            guard BatchWorkflow.isRetryablePollError(error) else { throw error }
            consecutive += 1
            if consecutive >= BatchWorkflow.maxConsecutivePollFailures { throw error }
        }
    }

    init(apiClient: AuphonicAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Control

    /// Mix Preparation mode: channel surgery per configured group
    func start(groups: [FileGroup], destination: URL, onFinished: (() -> Void)? = nil) {
        // Only groups with a usable configuration take part
        let work: [(file: BatchFile, config: ChannelConfig)] = groups
            .filter { $0.config.hasValidJobConfiguration }
            .flatMap { group in group.files.map { (file: $0, config: group.config) } }

        start(files: work.map(\.file), destination: destination, onFinished: onFinished) { [weak self] index, file in
            try await self?.processFile(file, config: work[index].config, destination: destination)
        }
    }

    /// Standard mode: every file goes to Auphonic as a whole and comes back in the
    /// configured output format
    func start(files: [BatchFile], config: StandardModeConfig, destination: URL, onFinished: (() -> Void)? = nil) {
        guard config.hasValidConfiguration else { return }

        start(files: files, destination: destination, onFinished: onFinished) { [weak self] _, file in
            try await self?.processFileDirect(file, config: config, destination: destination)
        }
    }

    private func start(
        files: [BatchFile],
        destination: URL,
        onFinished: (() -> Void)?,
        process: @escaping (Int, BatchFile) async throws -> Void
    ) {
        guard !isRunning, !files.isEmpty else { return }

        for file in files {
            file.status = .pending
            file.progress = 0
        }

        isRunning = true
        completedCount = 0
        totalCount = files.count
        lastOutputDirectory = destination

        runTask = Task {
            await run(files: files, destination: destination, process: process)
            isRunning = false
            onFinished?()
        }
    }

    func cancel() {
        runTask?.cancel()
        statusText = "Cancelled"
    }

    // MARK: - Run Loop

    /// Whether `error` means the user cancelled rather than the file failed.
    /// `Task.sleep` and `checkCancellation` throw `CancellationError`, but a
    /// cancelled `URLSession` upload or download throws `URLError.cancelled`,
    /// and any error surfacing while the task is already cancelled is a
    /// consequence of the cancellation too.
    nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return Task.isCancelled
    }

    private func run(
        files: [BatchFile],
        destination: URL,
        process: (Int, BatchFile) async throws -> Void
    ) async {
        let accessing = destination.startAccessingSecurityScopedResource()
        defer { if accessing { destination.stopAccessingSecurityScopedResource() } }

        var failures = 0

        for (index, file) in files.enumerated() {
            if Task.isCancelled { break }

            statusText = "File \(index + 1) of \(files.count): \(file.fileName)"

            do {
                try await process(index, file)
            } catch where Self.isCancellation(error) {
                file.status = .pending
                break
            } catch {
                file.status = .failed(error.localizedDescription)
                failures += 1
            }

            completedCount += 1
        }

        if Task.isCancelled {
            statusText = "Cancelled after \(completedCount) of \(totalCount) files"
        } else {
            statusText = failures == 0
                ? "Done — \(completedCount) file\(completedCount == 1 ? "" : "s") processed"
                : "Done — \(failures) of \(totalCount) files failed"
        }

        NotificationService.show(
            title: Task.isCancelled ? "Batch Cancelled" : (failures == 0 ? "Batch Complete" : "Batch Finished with Errors"),
            body: statusText
        )
    }

    // MARK: - Per File

    private func processFile(_ file: BatchFile, config: ChannelConfig, destination: URL) async throws {
        guard !file.isRF64 else {
            throw ChannelReplacerError.rf64NotSupported
        }

        if config.productionMode == .multitrack {
            try await processFileMultitrack(file, config: config, destination: destination)
            return
        }

        let jobs = config.uploadJobs
        guard !jobs.isEmpty else { return }

        file.status = .processing("Starting \(jobs.count) upload\(jobs.count == 1 ? "" : "s")…")
        file.progress = 0

        var results: [(job: UploadJob, downloaded: URL)] = []
        var productionUuids: [String] = []
        // Every temp file is registered the moment its job finishes, so the
        // deferred cleanup also covers jobs that completed before a sibling
        // in the same batch failed (a failing job removes its own files).
        var tempFiles: [URL] = []
        defer {
            for temp in tempFiles where temp != file.url {
                try? FileManager.default.removeItem(at: temp)
            }
        }

        var done = 0
        for batch in stride(from: 0, to: jobs.count, by: Self.maxConcurrentJobs).map({
            Array(jobs[$0..<min($0 + Self.maxConcurrentJobs, jobs.count)])
        }) {
            try Task.checkCancellation()

            try await withThrowingTaskGroup(
                of: (job: UploadJob, downloaded: URL, extracted: URL, productionUuid: String).self
            ) { group in
                for job in batch {
                    group.addTask {
                        try await self.processJob(job, file: file, config: config)
                    }
                }
                for try await result in group {
                    tempFiles.append(result.extracted)
                    tempFiles.append(result.downloaded)
                    results.append((result.job, result.downloaded))
                    productionUuids.append(result.productionUuid)
                    done += 1
                    file.progress = 0.9 * Double(done) / Double(jobs.count)
                }
            }
        }

        // Reassemble: copy original, patch processed channels into it
        file.status = .processing("Writing output…")
        let outputURL = Self.resolveOutputURL(for: file.url, destination: destination)
        let replacements = results.map { (channelIndices: $0.job.channelIndices, file: $0.downloaded) }
        let original = file.url

        try await Task.detached(priority: .userInitiated) {
            try ChannelReplacer.replaceChannels(
                original: original,
                output: outputURL,
                replacements: replacements
            )
        }.value

        if config.writeSettingsJson {
            var perJob: [String: Any] = [:]
            for job in jobs {
                perJob[job.label] = config.settingsForJob(job, bitDepth: file.bitDepth)
            }
            writeSidecar(perJob, next: outputURL)
        }

        // Housekeeping: the output is safely on disk, remove the productions
        if deleteProductionsAfterDownload {
            for uuid in productionUuids {
                try? await apiClient.deleteProduction(uuid: uuid)   // best effort
            }
        }

        file.progress = 1
        file.status = .done(outputURL)
    }

    // MARK: - Per File (Standard mode)

    /// One production per file: the file is uploaded as it is, Auphonic
    /// processes it and returns it in the configured output format, which is
    /// saved into the destination folder under the original base name.
    private func processFileDirect(_ file: BatchFile, config: StandardModeConfig, destination: URL) async throws {
        file.status = .processing("Preparing…")
        file.progress = 0

        // The test drive caps the upload; a full run sends the file untouched
        let source = file.url
        let needsTrim = maxUploadDuration.map { file.duration > $0 } ?? false
        var uploadFile = source
        if needsTrim {
            let channels = Array(1...file.channelCount)
            let isFloat = file.isFloat
            let bitDepth = file.bitDepth
            let maxDuration = maxUploadDuration
            uploadFile = try await Task.detached(priority: .userInitiated) {
                try Self.extractChannels(
                    from: source,
                    channels: channels,
                    isFloat: isFloat,
                    bitDepth: bitDepth,
                    maxDuration: maxDuration
                )
            }.value
        }
        defer {
            if uploadFile != source {
                try? FileManager.default.removeItem(at: uploadFile)
            }
        }

        try Task.checkCancellation()
        let title = source.deletingPathExtension().lastPathComponent
        let uuid = try await apiClient.createProduction(
            presetUuid: config.presetUuidForProduction,
            manualSettings: config.productionSettings,
            title: title
        )

        file.status = .processing("Uploading…")
        try await apiClient.uploadFile(productionUuid: uuid, file: uploadFile) { progress in
            Task { @MainActor in file.progress = 0.3 * progress }
        }
        try Task.checkCancellation()
        try await apiClient.startProduction(productionUuid: uuid)

        file.status = .processing("Processing…")
        let outputUrl = try await pollForOutputURL(productionUuid: uuid, label: file.fileName)

        file.status = .processing("Downloading…")
        let downloaded = try await apiClient.downloadFile(from: outputUrl) { progress in
            Task { @MainActor in file.progress = 0.8 + 0.15 * progress }
        }
        defer { try? FileManager.default.removeItem(at: downloaded) }

        // "Keep format" returns the input format, so fall back to what the
        // API actually sent before falling back to the source extension
        file.status = .processing("Writing output…")
        let ext = config.outputFileExtension
            ?? (downloaded.pathExtension.isEmpty ? source.pathExtension : downloaded.pathExtension)
        let outputURL = Self.resolveOutputURL(for: source, destination: destination, preferredExtension: ext)
        try FileManager.default.copyItem(at: downloaded, to: outputURL)

        if config.writeSettingsJson {
            var payload = config.productionSettings
            payload["preset"] = config.presetUuidForProduction
            writeSidecar(payload, next: outputURL)
        }

        if deleteProductionsAfterDownload {
            try? await apiClient.deleteProduction(uuid: uuid)   // best effort
        }

        file.progress = 1
        file.status = .done(outputURL)
    }

    // MARK: - Per File (Multitrack)

    /// One multitrack production per file: every enabled channel is uploaded
    /// as its own track, processed individually (denoise, leveler, crosstalk
    /// damping) and — optionally — mixed down into one master.
    private func processFileMultitrack(_ file: BatchFile, config: ChannelConfig, destination: URL) async throws {
        let channels = config.enabledChannels
        guard !channels.isEmpty else { return }

        var tempFiles: [URL] = []
        var workDirectories: [URL] = []
        defer {
            for temp in tempFiles where temp != file.url {
                try? FileManager.default.removeItem(at: temp)
            }
            for directory in workDirectories {
                try? FileManager.default.removeItem(at: directory)
            }
        }

        // 1. Extract every enabled channel into its own mono file
        file.status = .processing("Extracting \(channels.count) tracks…")
        file.progress = 0

        let source = file.url
        let isFloat = file.isFloat
        let bitDepth = file.bitDepth
        let maxDuration = maxUploadDuration

        var uploads: [(fieldName: String, file: URL)] = []
        var trackIdsByChannel: [(channel: Int, trackId: String)] = []

        // Auphonic names the exported tracks after the uploaded file names,
        // so each track is uploaded as "<trackId>.wav". Those names live in a
        // folder private to this file: in the shared temp folder a leftover
        // from a crashed run would block the rename and the UUID-named file
        // would be uploaded instead, breaking the track mapping later.
        let uploadDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("auphonic_upload_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: uploadDirectory, withIntermediateDirectories: true)
        workDirectories.append(uploadDirectory)

        for channel in channels {
            try Task.checkCancellation()
            let channelNumber = channel.id + 1
            let extracted = try await Task.detached(priority: .userInitiated) {
                try Self.extractChannels(
                    from: source,
                    channels: [channelNumber],
                    isFloat: isFloat,
                    bitDepth: bitDepth,
                    maxDuration: maxDuration
                )
            }.value

            let trackId = config.trackId(for: channel)
            let named = uploadDirectory.appendingPathComponent("\(trackId).wav")
            do {
                try FileManager.default.moveItem(at: extracted, to: named)
            } catch {
                try? FileManager.default.removeItem(at: extracted)
                throw error
            }

            uploads.append((fieldName: trackId, file: named))
            trackIdsByChannel.append((channel: channelNumber, trackId: trackId))
        }

        // 2. Create the production
        try Task.checkCancellation()
        file.progress = 0.1
        file.status = .processing("Creating multitrack production…")
        let title = file.url.deletingPathExtension().lastPathComponent
        let productionUuid = try await apiClient.createMultitrackProduction(
            trackIds: trackIdsByChannel.map(\.trackId),
            trackAlgorithms: config.multitrackTrackAlgorithms,
            masterAlgorithms: config.masterOptions.getSettings(),
            outputFiles: config.multitrackOutputFiles(bitDepth: file.bitDepth),
            title: title
        )

        // 3. Upload all tracks in one request, then start
        file.status = .processing("Uploading \(uploads.count) tracks…")
        try await apiClient.uploadFiles(productionUuid: productionUuid, files: uploads) { [weak self] fraction in
            Task { @MainActor [weak self] in
                guard self?.isRunning == true else { return }
                file.progress = 0.1 + fraction * 0.35
            }
        }
        try Task.checkCancellation()
        try await apiClient.startProduction(productionUuid: productionUuid)

        // 4. Poll
        file.status = .processing("Processing multitrack production…")
        let status = try await pollUntilDone(productionUuid: productionUuid, label: "multitrack production") { progress in
            file.progress = 0.45 + progress * 0.4
        }

        // 5. Download the tracks archive (and the mixdown when requested)
        guard let tracksFile = status.outputFiles.first(where: \.isTracksArchive) else {
            throw AuphonicAPIClient.APIError.decodingError("Production returned no individual tracks")
        }

        file.status = .processing("Downloading tracks…")
        let archive = try await apiClient.downloadFile(from: tracksFile.downloadUrl)
        tempFiles.append(archive)

        var mixdownFile: URL?
        if config.downloadMixdown,
           let mixdown = status.outputFiles.first(where: { !$0.isTracksArchive }) {
            file.status = .processing("Downloading mixdown…")
            let downloaded = try await apiClient.downloadFile(from: mixdown.downloadUrl)
            tempFiles.append(downloaded)
            mixdownFile = downloaded
        }

        // 6. Unpack the archive and map every track back to its channel
        file.progress = 0.9
        file.status = .processing("Writing output…")

        let unpackDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("auphonic_tracks_\(UUID().uuidString)", isDirectory: true)
        workDirectories.append(unpackDirectory)

        let extractedTracks = try await Task.detached(priority: .userInitiated) {
            try ZipArchive.extract(archive, to: unpackDirectory)
        }.value

        let ordered = Self.matchTracks(extractedTracks, to: trackIdsByChannel.map(\.trackId))
        guard ordered.count == trackIdsByChannel.count else {
            throw AuphonicAPIClient.APIError.decodingError(
                "Tracks archive holds \(ordered.count) files for \(trackIdsByChannel.count) tracks")
        }

        var replacements: [(channelIndices: [Int], file: URL)] = []
        for (index, entry) in trackIdsByChannel.enumerated() {
            replacements.append((channelIndices: [entry.channel], file: ordered[index]))
        }

        // The mixdown replaces its target channel last, so it wins if the
        // target is also processed as a track.
        if let mixdownFile, let target = config.mixdownTargetChannel {
            replacements.append((channelIndices: [target + 1], file: mixdownFile))
        }

        let outputURL = Self.resolveOutputURL(for: file.url, destination: destination)
        let original = file.url
        try await Task.detached(priority: .userInitiated) {
            try ChannelReplacer.replaceChannels(
                original: original,
                output: outputURL,
                replacements: replacements
            )
        }.value

        if config.writeSettingsJson {
            writeSidecar([
                "mode": "multitrack",
                "master": config.masterOptions.getSettings(),
                "tracks": config.multitrackTrackAlgorithms,
                "output_files": config.multitrackOutputFiles(bitDepth: file.bitDepth)
            ], next: outputURL)
        }

        if deleteProductionsAfterDownload {
            try? await apiClient.deleteProduction(uuid: productionUuid)
        }

        file.progress = 1
        file.status = .done(outputURL)
    }

    /// Match the files inside Auphonic's tracks archive to the uploaded track
    /// ids: by id first, then by the "Track N" numbering, then by name order.
    ///
    /// The id passes go from strict to loose across *all* ids before relaxing,
    /// so `ch10.wav` is claimed by `ch10` exactly before `ch1` gets a chance
    /// to substring-match it; the loose pass also tries longer ids first.
    nonisolated static func matchTracks(_ files: [URL], to trackIds: [String]) -> [URL] {
        var remaining = files
        var result: [URL?] = Array(repeating: nil, count: trackIds.count)

        func baseName(_ url: URL) -> String {
            url.deletingPathExtension().lastPathComponent.lowercased()
        }

        func claim(_ index: Int, where predicate: (String) -> Bool) {
            guard result[index] == nil,
                  let match = remaining.firstIndex(where: { predicate(baseName($0)) }) else { return }
            result[index] = remaining.remove(at: match)
        }

        // 1a. File is named exactly after the track id
        for (index, trackId) in trackIds.enumerated() {
            let needle = trackId.lowercased()
            claim(index) { $0 == needle }
        }

        // 1b. Track id appears as a whole token ("take_ch1_processed", not "ch10")
        for (index, trackId) in trackIds.enumerated() {
            let pattern = "(^|[^a-z0-9])" + NSRegularExpression.escapedPattern(for: trackId.lowercased()) + "([^a-z0-9]|$)"
            claim(index) { $0.range(of: pattern, options: .regularExpression) != nil }
        }

        // 1c. Track id contained anywhere, longest ids first so "lav10" wins over "lav1"
        let byLength = trackIds.enumerated().sorted { $0.element.count > $1.element.count }
        for (index, trackId) in byLength {
            let needle = trackId.lowercased()
            claim(index) { $0.contains(needle) }
        }

        // 2. "Track N" numbering (1-based, in upload order)
        for (index, _) in trackIds.enumerated() where result[index] == nil {
            let number = index + 1
            if let match = remaining.firstIndex(where: { url in
                let name = url.deletingPathExtension().lastPathComponent
                guard let digits = name.range(of: "\\d+", options: .regularExpression) else { return false }
                return Int(name[digits]) == number
            }) {
                result[index] = remaining.remove(at: match)
            }
        }

        // 3. Whatever is left, in stable name order
        remaining.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        for index in result.indices where result[index] == nil {
            if remaining.isEmpty { break }
            result[index] = remaining.removeFirst()
        }

        return result.compactMap { $0 }
    }

    // MARK: - Per Upload Job

    private func processJob(
        _ job: UploadJob,
        file: BatchFile,
        config: ChannelConfig
    ) async throws -> (job: UploadJob, downloaded: URL, extracted: URL, productionUuid: String) {
        // 1. Extract the job's channels (skipped when the job covers the whole file)
        file.status = .processing("Extracting \(job.label)…")
        let source = file.url
        let channels = job.channelIndices
        let isFloat = file.isFloat
        let bitDepth = file.bitDepth
        let maxDuration = maxUploadDuration
        let needsTrim = maxDuration.map { file.duration > $0 } ?? false
        let coversWholeFile = channels == Array(1...file.channelCount) && !needsTrim

        let uploadFile: URL
        if coversWholeFile {
            uploadFile = source
        } else {
            uploadFile = try await Task.detached(priority: .userInitiated) {
                try Self.extractChannels(
                    from: source,
                    channels: channels,
                    isFloat: isFloat,
                    bitDepth: bitDepth,
                    maxDuration: maxDuration
                )
            }.value
        }

        do {
            // 2. Create production
            try Task.checkCancellation()
            let title = "\(file.url.deletingPathExtension().lastPathComponent) \(job.label)"
            let uuid = try await apiClient.createProduction(
                presetUuid: config.presetUuidForJob(job),
                manualSettings: config.settingsForJob(job, bitDepth: file.bitDepth),
                title: title
            )

            // 3. Upload + start
            file.status = .processing("Uploading \(job.label)…")
            try await apiClient.uploadFile(productionUuid: uuid, file: uploadFile)
            try Task.checkCancellation()
            try await apiClient.startProduction(productionUuid: uuid)

            // 4. Poll until done
            file.status = .processing("Processing \(job.label)…")
            let outputUrl = try await pollForOutputURL(productionUuid: uuid, label: job.label)

            // 5. Download
            file.status = .processing("Downloading \(job.label)…")
            let downloaded = try await apiClient.downloadFile(from: outputUrl)

            return (job: job, downloaded: downloaded, extracted: uploadFile, productionUuid: uuid)
        } catch {
            if uploadFile != source {
                try? FileManager.default.removeItem(at: uploadFile)
            }
            throw error
        }
    }

    // MARK: - Polling

    /// Polls a production every `pollInterval` until it is done, and returns
    /// its final status. `label` names the production in error messages;
    /// `onProgress` receives Auphonic's 0…1 progress after each poll.
    private func pollUntilDone(
        productionUuid: String,
        label: String,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> ProductionStatus {
        let deadline = Date().addingTimeInterval(Self.pollTimeout)
        var failures = PollFailures()

        while Date() < deadline {
            try await Task.sleep(for: Self.pollInterval)

            let status: ProductionStatus
            do {
                status = try await apiClient.getProductionStatus(productionUuid: productionUuid)
                failures.reset()
            } catch {
                try failures.record(error)   // transient: keep polling
                continue
            }

            onProgress?(min(1, max(0, status.progress)))

            if status.isDone { return status }
            if status.isError {
                throw AuphonicAPIClient.APIError.httpError(0, "\(label): \(status.failureDescription)")
            }
        }
        throw AuphonicAPIClient.APIError.networkError("Timed out waiting for \(label)")
    }

    /// Singletrack productions deliver one output file; its URL is what the
    /// download step needs.
    private func pollForOutputURL(productionUuid: String, label: String) async throws -> String {
        let status = try await pollUntilDone(productionUuid: productionUuid, label: label)
        guard !status.outputFileUrl.isEmpty else {
            throw AuphonicAPIClient.APIError.decodingError("No output file URL for \(label)")
        }
        return status.outputFileUrl
    }

    // MARK: - Channel Extraction

    /// Extract the given 1-based channels into a temp WAV, preserving the
    /// source sample format (32-bit float stays 32-bit float). Chunked to
    /// keep memory bounded for long recordings. `maxDuration` trims the
    /// excerpt (settings test drive).
    nonisolated static func extractChannels(
        from url: URL,
        channels: [Int],
        isFloat: Bool,
        bitDepth: Int,
        maxDuration: Double? = nil
    ) throws -> URL {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let channelCount = Int(format.channelCount)

        for ch in channels {
            guard ch >= 1, ch <= channelCount else {
                throw ChannelReplacerError.invalidWav("channel \(ch) does not exist")
            }
        }

        let outChannelCount = channels.count
        let outBitDepth = isFloat ? 32 : min(max(bitDepth, 16), 32)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: outChannelCount,
            AVLinearPCMBitDepthKey: outBitDepth,
            AVLinearPCMIsFloatKey: isFloat,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("auphonic_extract_\(UUID().uuidString).wav")
        let outputFile = try AVAudioFile(forWriting: tempFile, settings: outputSettings)

        let chunkFrames: AVAudioFrameCount = 1 << 20    // 1M frames per pass
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames),
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: format.sampleRate,
                                            channels: AVAudioChannelCount(outChannelCount),
                                            interleaved: false),
              let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: chunkFrames) else {
            throw ChannelReplacerError.invalidWav("failed to create extraction buffers")
        }

        let frameLimit: AVAudioFramePosition = maxDuration
            .map { min(file.length, AVAudioFramePosition($0 * format.sampleRate)) }
            ?? file.length

        while file.framePosition < frameLimit {
            let toRead = min(AVAudioFrameCount(frameLimit - file.framePosition), chunkFrames)
            try file.read(into: inBuffer, frameCount: toRead)
            let frames = Int(inBuffer.frameLength)
            if frames == 0 { break }

            guard let inData = inBuffer.floatChannelData,
                  let outData = outBuffer.floatChannelData else {
                throw ChannelReplacerError.invalidWav("failed to access audio data")
            }

            for (outCh, inCh) in channels.enumerated() {
                outData[outCh].update(from: inData[inCh - 1], count: frames)
            }
            outBuffer.frameLength = AVAudioFrameCount(frames)
            try outputFile.write(from: outBuffer)
        }

        return tempFile
    }

    // MARK: - Output Naming

    /// Output path in the destination folder using the original file name.
    /// Never resolves to the original path itself; appends a counter when the
    /// name is already taken. `preferredExtension` is used by Standard mode, where
    /// the result can come back in a different format than the source.
    nonisolated static func resolveOutputURL(
        for original: URL,
        destination: URL,
        preferredExtension: String? = nil
    ) -> URL {
        let baseName = original.deletingPathExtension().lastPathComponent
        let ext = preferredExtension ?? original.pathExtension

        func isTaken(_ url: URL) -> Bool {
            url.standardizedFileURL == original.standardizedFileURL
                || FileManager.default.fileExists(atPath: url.path)
        }

        func url(named name: String) -> URL {
            let base = destination.appendingPathComponent(name)
            return ext.isEmpty ? base : base.appendingPathExtension(ext)
        }

        var candidate = url(named: baseName)
        var counter = 2
        while isTaken(candidate) {
            candidate = url(named: "\(baseName)_\(counter)")
            counter += 1
        }
        return candidate
    }

    // MARK: - Settings Sidecar

    /// Writes the settings that produced `outputURL` next to it as
    /// `<name>.json`. Best effort: a sidecar that cannot be written must not
    /// fail a file whose audio is already on disk.
    private func writeSidecar(_ payload: [String: Any], next outputURL: URL) {
        let sidecarURL = outputURL.deletingPathExtension().appendingPathExtension("json")
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: sidecarURL)
        }
    }
}
