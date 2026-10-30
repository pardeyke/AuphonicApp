import Foundation
import AVFoundation
import Accelerate

/// Offline stand-in for Auphonic, used when the app is launched for UI tests
/// (`UITestEnvironment`). It behaves like the real service from the app's
/// point of view — productions, uploads, polling, downloads in the requested
/// format, the multitrack tracks archive and mono mixdown — and "processes"
/// audio deterministically: every output sample is the input sample times
/// `processingGain`, encoded in the format the production asked for. A test
/// can therefore check that exactly the right channels came back, at the
/// right bit depth, without a network.
///
/// Every call is appended to `api-log.json` in the launch's work directory,
/// so the test runner can verify what the app sent.
@Observable
final class SimulatedAuphonicAPI: AuphonicService {

    /// Every sample Auphonic returns is the uploaded sample times this
    nonisolated static let processingGain: Float = 0.5

    /// Failure modes, set by the test through `AUPHONIC_UITEST_SCENARIO`
    struct Scenario {
        /// Every production ends with Auphonic's error status
        var processingError = false
        /// Status polls fail with a rejected token (not retryable)
        var revokedToken = false
        /// The first N status polls fail with a timeout, then polling recovers
        var transientErrors = 0
        /// Productions never finish on their own (for cancelling)
        var neverFinishes = false
        /// `user.json` fails, so connecting shows an alert
        var connectionFails = false
        /// Creating a production is rejected with HTTP 400
        var createFails = false
        /// Storing a preset is rejected
        var savePresetFails = false
        /// Productions whose title contains one of these fail while processing
        var failingTitles: [String] = []

        /// Comma-separated flags, e.g. `processingError` or
        /// `transientErrors=3,failTitle=take_02`
        init(_ spec: String = "") {
            for flag in spec.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                let parts = flag.split(separator: "=", maxSplits: 1).map(String.init)
                let value = parts.count > 1 ? parts[1] : ""
                switch parts.first ?? "" {
                case "processingError": processingError = true
                case "revokedToken": revokedToken = true
                case "transientErrors": transientErrors = Int(value) ?? 2
                case "neverFinishes": neverFinishes = true
                case "connectionFails": connectionFails = true
                case "createFails": createFails = true
                case "savePresetFails": savePresetFails = true
                case "failTitle": failingTitles.append(value)
                default: break
                }
            }
        }
    }

    static let presets = [
        AuphonicPreset(uuid: "preset-dialog", name: "UITest Dialog"),
        AuphonicPreset(uuid: "preset-music", name: "UITest Music")
    ]

    /// Algorithms behind the canned presets
    static func presetAlgorithms(_ uuid: String) -> [String: Any] {
        switch uuid {
        case "preset-dialog":
            return ["leveler": true, "levelerstrength": 80, "compressor": "soft",
                    "denoise": true, "denoisemethod": "dynamic", "denoiseamount": 12,
                    "filtering": true, "filtermethod": "autoeq",
                    "normloudness": true, "loudnesstarget": -23, "maxpeak": -1.0,
                    "loudnessmethod": "dialog"]
        default:
            return ["leveler": false, "denoise": false, "filtering": false,
                    "normloudness": true, "loudnesstarget": -14, "loudnessmethod": "program"]
        }
    }

    var token = ""
    private var scenario: Scenario
    private let workDirectory: URL
    private var logEntries: [[String: Any]] = []
    private var customPresets: [AuphonicPreset] = []

    private final class Production {
        let uuid: String
        let title: String
        let isMultitrack: Bool
        /// Requested output files (`output_files`)
        let outputFiles: [[String: Any]]
        var polls = 0
        /// Results, rendered once the uploads arrive: download URL → file
        var results: [String: URL] = [:]
        var outputDescriptions: [ProductionOutputFile] = []
        var singleOutputURL = ""

        init(uuid: String, title: String, isMultitrack: Bool, outputFiles: [[String: Any]]) {
            self.uuid = uuid
            self.title = title
            self.isMultitrack = isMultitrack
            self.outputFiles = outputFiles
        }
    }

    private var productions: [String: Production] = [:]
    private var productionCounter = 0

    init(scenario: Scenario = Scenario(), workDirectory: URL) {
        self.scenario = scenario
        self.workDirectory = workDirectory
        try? FileManager.default.createDirectory(at: resultsDirectory, withIntermediateDirectories: true)
        writeLog()
    }

    private var resultsDirectory: URL {
        workDirectory.appendingPathComponent("results", isDirectory: true)
    }

    var logURL: URL { workDirectory.appendingPathComponent("api-log.json") }

    // MARK: - Log

    private func log(_ call: String, _ details: [String: Any] = [:]) {
        var entry = details
        entry["call"] = call
        logEntries.append(entry)
        writeLog()
    }

    private func writeLog() {
        let payload: Any = JSONSerialization.isValidJSONObject(logEntries) ? logEntries : []
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: logURL, options: .atomic)
        }
    }

    private func requireToken() throws {
        if token.isEmpty { throw AuphonicAPIClient.APIError.noToken }
    }

    // MARK: - Account

    func fetchUserInfo() async throws -> UserCredits {
        try requireToken()
        log("fetchUserInfo")
        if scenario.connectionFails {
            throw AuphonicAPIClient.APIError.networkError("Simulated connection failure")
        }
        // 12 h total, 10 h shown after the 2 free watermark hours
        return UserCredits(credits: 12, onetimeCredits: 2, recurringCredits: 10)
    }

    func fetchPresets() async throws -> [AuphonicPreset] {
        try requireToken()
        log("fetchPresets")
        return Self.presets + customPresets
    }

    func fetchPresetDetails(uuid: String) async throws -> [String: Any] {
        try requireToken()
        log("fetchPresetDetails", ["uuid": uuid])
        return ["uuid": uuid, "algorithms": Self.presetAlgorithms(uuid)]
    }

    func savePreset(name: String, settings: [String: Any]) async throws -> String {
        try requireToken()
        log("savePreset", ["name": name, "settings": settings])
        if scenario.savePresetFails {
            throw AuphonicAPIClient.APIError.httpError(400, "Simulated preset rejection")
        }
        let uuid = "preset-custom-\(customPresets.count + 1)"
        customPresets.append(AuphonicPreset(uuid: uuid, name: name))
        return uuid
    }

    // MARK: - Productions

    private func nextUuid() -> String {
        productionCounter += 1
        return "sim-\(productionCounter)"
    }

    func createProduction(presetUuid: String, manualSettings: [String: Any], title: String) async throws -> String {
        try requireToken()
        if scenario.createFails {
            log("createProduction", ["title": title, "rejected": true])
            throw AuphonicAPIClient.APIError.httpError(400, "Simulated: production rejected")
        }
        let uuid = nextUuid()
        // An unmodified preset decides the output itself; the simulation
        // answers with 24-bit WAV then, like a typical production preset
        let outputFiles = (manualSettings["output_files"] as? [[String: Any]]) ?? [["format": "wav-24bit"]]
        productions[uuid] = Production(uuid: uuid, title: title, isMultitrack: false, outputFiles: outputFiles)
        log("createProduction", ["uuid": uuid, "title": title, "preset": presetUuid, "settings": manualSettings])
        return uuid
    }

    func createMultitrackProduction(
        trackIds: [String],
        trackAlgorithms: [String: [String: Any]],
        masterAlgorithms: [String: Any],
        outputFiles: [[String: Any]],
        title: String
    ) async throws -> String {
        try requireToken()
        if scenario.createFails {
            log("createMultitrackProduction", ["title": title, "rejected": true])
            throw AuphonicAPIClient.APIError.httpError(400, "Simulated: production rejected")
        }
        let uuid = nextUuid()
        productions[uuid] = Production(uuid: uuid, title: title, isMultitrack: true, outputFiles: outputFiles)
        log("createMultitrackProduction", [
            "uuid": uuid, "title": title, "trackIds": trackIds,
            "trackAlgorithms": trackAlgorithms, "masterAlgorithms": masterAlgorithms,
            "outputFiles": outputFiles
        ])
        return uuid
    }

    func uploadFiles(productionUuid: String, files: [(fieldName: String, file: URL)],
                     onProgress: (@Sendable (Double) -> Void)?) async throws {
        try requireToken()
        guard let production = productions[productionUuid] else {
            throw AuphonicAPIClient.APIError.httpError(404, "no such production")
        }

        let described = files.map { entry -> [String: Any] in
            var info = Self.describe(entry.file)
            info["field"] = entry.fieldName
            info["name"] = entry.file.lastPathComponent
            return info
        }
        log("upload", ["uuid": productionUuid, "files": described])

        // Render the results now: the app removes its upload scratch files
        // once the production is done
        let directory = resultsDirectory.appendingPathComponent(productionUuid, isDirectory: true)
        let inputs = files.map(\.file)
        let isMultitrack = production.isMultitrack
        // Plain strings cross into the detached task; the settings dictionaries can't
        let format = (production.outputFiles.first?["format"] as? String) ?? "wav-24bit"
        let mixdownFormat = production.outputFiles
            .first { ($0["mono_mixdown"] as? Bool) == true }
            .map { ($0["format"] as? String) ?? "wav-24bit" }

        let rendered = try await Task.detached(priority: .userInitiated) {
            try Self.render(inputs: inputs, format: format, mixdownFormat: mixdownFormat,
                            multitrack: isMultitrack, into: directory)
        }.value

        for output in rendered {
            let url = "sim://\(productionUuid)/\(output.file.lastPathComponent)"
            production.results[url] = output.file
            production.outputDescriptions.append(
                ProductionOutputFile(format: output.format, filename: output.file.lastPathComponent, downloadUrl: url))
        }
        if !isMultitrack, let first = production.outputDescriptions.first {
            production.singleOutputURL = first.downloadUrl
        }
        onProgress?(1)
    }

    func startProduction(productionUuid: String) async throws {
        try requireToken()
        log("start", ["uuid": productionUuid])
    }

    func getProductionStatus(productionUuid: String) async throws -> ProductionStatus {
        try requireToken()
        guard let production = productions[productionUuid] else {
            throw AuphonicAPIClient.APIError.httpError(404, "no such production")
        }
        production.polls += 1

        if scenario.revokedToken {
            log("status", ["uuid": productionUuid, "result": "invalidToken"])
            throw AuphonicAPIClient.APIError.invalidToken
        }
        if scenario.transientErrors > 0 {
            scenario.transientErrors -= 1
            log("status", ["uuid": productionUuid, "result": "timeout"])
            throw URLError(.timedOut)
        }
        if scenario.processingError || scenario.failingTitles.contains(where: { production.title.contains($0) }) {
            log("status", ["uuid": productionUuid, "result": "error"])
            return ProductionStatus(statusCode: 2, statusString: "Error", progress: 0,
                                    errorMessage: "Simulated processing failure", outputFileUrl: "", uuid: productionUuid)
        }

        let pollsUntilDone = scenario.neverFinishes ? Int.max : 3
        guard production.polls >= pollsUntilDone else {
            return ProductionStatus(statusCode: 4, statusString: "Audio Processing",
                                    progress: Double(production.polls) / 3, errorMessage: "",
                                    outputFileUrl: "", uuid: productionUuid)
        }

        log("status", ["uuid": productionUuid, "result": "done"])
        return ProductionStatus(statusCode: 3, statusString: "Done", progress: 1, errorMessage: "",
                                outputFileUrl: production.singleOutputURL,
                                outputFiles: production.outputDescriptions, uuid: productionUuid)
    }

    func downloadFile(from urlString: String, onProgress: (@Sendable (Double) -> Void)?) async throws -> URL {
        try requireToken()
        guard let source = productions.values.lazy.compactMap({ $0.results[urlString] }).first else {
            throw AuphonicAPIClient.APIError.httpError(404, "Simulated: no such download \(urlString)")
        }
        log("download", ["url": urlString])

        // The app moves or deletes what it downloads, so hand out a copy
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("sim_download_\(UUID().uuidString)")
            .appendingPathExtension(source.pathExtension)
        try FileManager.default.copyItem(at: source, to: copy)
        onProgress?(1)
        return copy
    }

    func deleteProduction(uuid: String) async throws {
        try requireToken()
        log("delete", ["uuid": uuid])
    }

    // MARK: - Rendering

    private struct RenderedOutput: Sendable {
        let format: String
        let file: URL
    }

    /// Facts about an uploaded file the tests check (channels, length, format)
    nonisolated private static func describe(_ url: URL) -> [String: Any] {
        guard let file = try? AVAudioFile(forReading: url) else { return ["readable": false] }
        var info: [String: Any] = [
            "channels": Int(file.fileFormat.channelCount),
            "frames": Int(file.length),
            "sampleRate": file.fileFormat.sampleRate
        ]
        if let format = WavChunkCopier.readFormatInfo(from: url) {
            info["bitDepth"] = format.bitsPerSample
            info["isFloat"] = format.isFloat
        }
        return info
    }

    nonisolated private static func render(
        inputs: [URL],
        format: String,
        mixdownFormat: String?,
        multitrack: Bool,
        into directory: URL
    ) throws -> [RenderedOutput] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if !multitrack {
            guard let input = inputs.first else { return [] }
            let output = directory.appendingPathComponent("output").appendingPathExtension(fileExtension(for: format))
            try encode(samples: readScaled(input), sampleRate: sampleRate(of: input), format: format, to: output)
            return [RenderedOutput(format: format, file: output)]
        }

        // Multitrack: every track comes back as 16-bit WAV in a zip named
        // after the uploaded file, like Auphonic's "tracks" output
        var results: [RenderedOutput] = []
        let tracksDirectory = directory.appendingPathComponent("tracks", isDirectory: true)
        try FileManager.default.createDirectory(at: tracksDirectory, withIntermediateDirectories: true)

        var trackFiles: [URL] = []
        var mix: [Float] = []
        var rate = 48000.0
        for input in inputs {
            let samples = try readScaled(input)
            rate = try sampleRate(of: input)
            let track = tracksDirectory.appendingPathComponent(input.deletingPathExtension().lastPathComponent + ".wav")
            try encode(samples: samples, sampleRate: rate, format: "wav-16bit", to: track)
            trackFiles.append(track)

            // Mixdown: the average of the processed tracks
            let mono = samples.first ?? []
            if mix.isEmpty { mix = Array(repeating: 0, count: mono.count) }
            let length = min(mix.count, mono.count)
            mix = vDSP.add(multiplication: (a: Array(mono[..<length]), b: 1 / Float(inputs.count)), Array(mix[..<length]))
        }

        let archive = directory.appendingPathComponent("tracks.zip")
        try StoredZipWriter.write(trackFiles, to: archive)
        results.append(RenderedOutput(format: "tracks", file: archive))

        if let mixdownFormat {
            let output = directory.appendingPathComponent("mixdown").appendingPathExtension(fileExtension(for: mixdownFormat))
            try encode(samples: [mix], sampleRate: rate, format: mixdownFormat, to: output)
            results.append(RenderedOutput(format: mixdownFormat, file: output))
        }
        return results
    }

    nonisolated private static func sampleRate(of url: URL) throws -> Double {
        try AVAudioFile(forReading: url).fileFormat.sampleRate
    }

    /// All channels of `url`, deinterleaved and multiplied by the gain.
    /// Reads in chunks: one `read(into:)` may return fewer frames than asked.
    nonisolated private static func readScaled(_ url: URL) throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url)
        let channels = Int(file.processingFormat.channelCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1 << 18) else {
            throw AuphonicAPIClient.APIError.decodingError("Simulated: cannot buffer \(url.lastPathComponent)")
        }
        var result = Array(repeating: [Float](), count: channels)
        for channel in 0..<channels { result[channel].reserveCapacity(Int(file.length)) }

        while file.framePosition < file.length {
            try file.read(into: buffer)
            let count = Int(buffer.frameLength)
            guard count > 0, let data = buffer.floatChannelData else { break }
            for channel in 0..<channels {
                result[channel] += vDSP.multiply(processingGain, UnsafeBufferPointer(start: data[channel], count: count))
            }
        }
        return result
    }

    nonisolated static func fileExtension(for format: String) -> String {
        switch format {
        case "flac": return "flac"
        case "alac": return "m4a"
        case "mp3", "mp3-vbr": return "mp3"
        case "aac": return "aac"
        case "vorbis": return "ogg"
        case "opus": return "opus"
        default: return "wav"
        }
    }

    /// Writes the samples in the Auphonic output `format`. Formats Core Audio
    /// can encode are real audio files; for the rest (MP3, Vorbis, Opus …)
    /// a marker file with the right extension stands in.
    nonisolated private static func encode(samples: [[Float]], sampleRate: Double, format: String, to url: URL) throws {
        var settings: [String: Any] = [
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: samples.count
        ]
        switch format {
        case "wav-16bit", "wav-24bit":
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = format == "wav-16bit" ? 16 : 24
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = false
            settings[AVLinearPCMIsNonInterleaved] = false
        case "flac":
            settings[AVFormatIDKey] = kAudioFormatFLAC
            settings[AVEncoderBitDepthHintKey] = 24
        case "alac":
            settings[AVFormatIDKey] = kAudioFormatAppleLossless
            settings[AVEncoderBitDepthHintKey] = 24
        default:
            try Data("SIMULATED \(format) OUTPUT\n".utf8).write(to: url)
            return
        }

        let frames = samples.first?.count ?? 0
        guard let processing = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                             channels: AVAudioChannelCount(max(samples.count, 1))),
              let buffer = AVAudioPCMBuffer(pcmFormat: processing, frameCapacity: AVAudioFrameCount(max(frames, 1))),
              let data = buffer.floatChannelData else {
            throw AuphonicAPIClient.APIError.decodingError("Simulated: cannot encode \(format)")
        }
        for (channel, values) in samples.enumerated() {
            values.withUnsafeBufferPointer { data[channel].update(from: $0.baseAddress!, count: values.count) }
        }
        buffer.frameLength = AVAudioFrameCount(frames)

        // Scoped so the file is closed (and its header finalized) on return
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
        }
    }
}

// MARK: - Stored ZIP

/// Writes an uncompressed ZIP archive — all the simulated tracks archive needs
nonisolated enum StoredZipWriter {
    static func write(_ files: [URL], to archive: URL) throws {
        var output = Data()
        var central = Data()

        for file in files {
            let content = try Data(contentsOf: file)
            let name = Data(file.lastPathComponent.utf8)
            let crc = crc32(content)
            let offset = UInt32(output.count)

            // Local file header
            output.appendLE(UInt32(0x04034b50))
            output.appendLE(UInt16(20))              // version needed
            output.appendLE(UInt16(0))               // flags
            output.appendLE(UInt16(0))               // stored
            output.appendLE(UInt16(0)); output.appendLE(UInt16(0x21))  // time, date
            output.appendLE(crc)
            output.appendLE(UInt32(content.count))
            output.appendLE(UInt32(content.count))
            output.appendLE(UInt16(name.count))
            output.appendLE(UInt16(0))
            output.append(name)
            output.append(content)

            // Central directory entry
            central.appendLE(UInt32(0x02014b50))
            central.appendLE(UInt16(20)); central.appendLE(UInt16(20))
            central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
            central.appendLE(UInt16(0)); central.appendLE(UInt16(0x21))
            central.appendLE(crc)
            central.appendLE(UInt32(content.count))
            central.appendLE(UInt32(content.count))
            central.appendLE(UInt16(name.count))
            central.appendLE(UInt16(0)); central.appendLE(UInt16(0))   // extra, comment
            central.appendLE(UInt16(0)); central.appendLE(UInt16(0))   // disk, internal attrs
            central.appendLE(UInt32(0))                                // external attrs
            central.appendLE(offset)
            central.append(name)
        }

        let centralOffset = UInt32(output.count)
        output.append(central)

        // End of central directory
        output.appendLE(UInt32(0x06054b50))
        output.appendLE(UInt16(0)); output.appendLE(UInt16(0))
        output.appendLE(UInt16(files.count)); output.appendLE(UInt16(files.count))
        output.appendLE(UInt32(central.count))
        output.appendLE(centralOffset)
        output.appendLE(UInt16(0))

        try output.write(to: archive)
    }

    private static let crcTable: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    nonisolated mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
