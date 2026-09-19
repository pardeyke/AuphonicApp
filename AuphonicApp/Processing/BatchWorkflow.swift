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

    init(apiClient: AuphonicAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Control

    func start(groups: [FileGroup], destination: URL, onFinished: (() -> Void)? = nil) {
        guard !isRunning else { return }

        // Only groups with a usable configuration take part
        let work: [(file: BatchFile, config: ChannelConfig)] = groups
            .filter { $0.config.hasValidJobConfiguration }
            .flatMap { group in group.files.map { (file: $0, config: group.config) } }

        guard !work.isEmpty else { return }

        for (file, _) in work {
            file.status = .pending
            file.progress = 0
        }

        isRunning = true
        completedCount = 0
        totalCount = work.count
        lastOutputDirectory = destination

        runTask = Task {
            await run(work: work, destination: destination)
            isRunning = false
            onFinished?()
        }
    }

    func cancel() {
        runTask?.cancel()
        statusText = "Cancelled"
    }

    // MARK: - Run Loop

    private func run(work: [(file: BatchFile, config: ChannelConfig)], destination: URL) async {
        let accessing = destination.startAccessingSecurityScopedResource()
        defer { if accessing { destination.stopAccessingSecurityScopedResource() } }

        var failures = 0

        for (index, item) in work.enumerated() {
            if Task.isCancelled { break }

            statusText = "File \(index + 1) of \(work.count): \(item.file.fileName)"

            do {
                try await processFile(item.file, config: item.config, destination: destination)
            } catch is CancellationError {
                item.file.status = .pending
                break
            } catch {
                item.file.status = .failed(error.localizedDescription)
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

        let jobs = config.uploadJobs
        guard !jobs.isEmpty else { return }

        file.status = .processing("Starting \(jobs.count) upload\(jobs.count == 1 ? "" : "s")…")
        file.progress = 0

        var results: [(job: UploadJob, downloaded: URL)] = []
        var productionUuids: [String] = []
        var tempFiles: [URL] = []
        defer {
            for temp in tempFiles where temp != file.url {
                try? FileManager.default.removeItem(at: temp)
            }
        }

        do {
            var done = 0
            for batch in stride(from: 0, to: jobs.count, by: Self.maxConcurrentJobs).map({
                Array(jobs[$0..<min($0 + Self.maxConcurrentJobs, jobs.count)])
            }) {
                try Task.checkCancellation()

                let batchResults = try await withThrowingTaskGroup(
                    of: (job: UploadJob, downloaded: URL, extracted: URL, productionUuid: String).self
                ) { group in
                    for job in batch {
                        group.addTask {
                            try await self.processJob(job, file: file, config: config)
                        }
                    }
                    var collected: [(job: UploadJob, downloaded: URL, extracted: URL, productionUuid: String)] = []
                    for try await result in group {
                        collected.append(result)
                    }
                    return collected
                }

                for result in batchResults {
                    results.append((result.job, result.downloaded))
                    productionUuids.append(result.productionUuid)
                    tempFiles.append(result.extracted)
                    tempFiles.append(result.downloaded)
                    done += 1
                    file.progress = 0.9 * Double(done) / Double(jobs.count)
                }
            }
        } catch {
            for result in results {
                try? FileManager.default.removeItem(at: result.downloaded)
            }
            throw error
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

        if config.writeSettingsXml {
            writeSettingsSidecar(for: outputURL, jobs: jobs, config: config)
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
                manualSettings: config.settingsForJob(job),
                title: title
            )

            // 3. Upload + start
            file.status = .processing("Uploading \(job.label)…")
            try await apiClient.uploadFile(productionUuid: uuid, file: uploadFile)
            try Task.checkCancellation()
            try await apiClient.startProduction(productionUuid: uuid)

            // 4. Poll until done
            file.status = .processing("Processing \(job.label)…")
            let outputUrl = try await pollUntilDone(productionUuid: uuid, jobLabel: job.label, file: file)

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

    private func pollUntilDone(productionUuid: String, jobLabel: String, file: BatchFile) async throws -> String {
        let deadline = Date().addingTimeInterval(Self.pollTimeout)

        while Date() < deadline {
            try await Task.sleep(for: Self.pollInterval)

            let status: ProductionStatus
            do {
                status = try await apiClient.getProductionStatus(productionUuid: productionUuid)
            } catch {
                continue    // tolerate transient poll errors
            }

            if status.isDone {
                guard !status.outputFileUrl.isEmpty else {
                    throw AuphonicAPIClient.APIError.decodingError("No output file URL for \(jobLabel)")
                }
                return status.outputFileUrl
            }
            if status.isError {
                let message = status.errorMessage.isEmpty ? "Processing failed" : status.errorMessage
                throw AuphonicAPIClient.APIError.httpError(0, "\(jobLabel): \(message)")
            }
        }
        throw AuphonicAPIClient.APIError.networkError("Timed out waiting for \(jobLabel)")
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
    /// name is already taken.
    nonisolated static func resolveOutputURL(for original: URL, destination: URL) -> URL {
        let baseName = original.deletingPathExtension().lastPathComponent
        let ext = original.pathExtension

        func isTaken(_ url: URL) -> Bool {
            url.standardizedFileURL == original.standardizedFileURL
                || FileManager.default.fileExists(atPath: url.path)
        }

        var candidate = destination.appendingPathComponent(original.lastPathComponent)
        var counter = 2
        while isTaken(candidate) {
            candidate = destination
                .appendingPathComponent("\(baseName)_\(counter)")
                .appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    // MARK: - Settings Sidecar

    private func writeSettingsSidecar(for outputURL: URL, jobs: [UploadJob], config: ChannelConfig) {
        var perJob: [String: Any] = [:]
        for job in jobs {
            perJob[job.label] = config.settingsForJob(job)
        }
        let sidecarURL = outputURL.deletingPathExtension().appendingPathExtension("json")
        if let data = try? JSONSerialization.data(withJSONObject: perJob, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: sidecarURL)
        }
    }
}
