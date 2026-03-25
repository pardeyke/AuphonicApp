import Foundation
import AVFoundation

@Observable
final class ProcessingWorkflow {
    private(set) var state: ProcessingState = .idle
    private(set) var progress: Double = -1
    private(set) var statusText: String = ""
    private(set) var lastOutputFile: URL?

    private var apiClient: AuphonicAPIClient
    private var originalSourceFile: URL?
    private var sourceFile: URL?
    private var productionUuid: String = ""
    private var presetId: String = ""
    private var settings: [String: Any] = [:]
    private var extractChannel: Int = 0       // 0=all, >0=single, -1=L+R
    private var previewDurationSeconds: Double = 0
    private var keepTimecode: Bool = false
    private var avoidOverwrite: Bool = false
    private var outputSuffix: String = "_auphonic"
    private var writeSettingsXml: Bool = false
    private var tempOutputMode: Bool = false
    private var outputDirectory: URL?
    private var targetExtension: String?

    private var extractedTempFile: URL?
    private var trimmedTempFile: URL?
    private var cancelled = false
    private var pollTimer: Timer?

    init(apiClient: AuphonicAPIClient) {
        self.apiClient = apiClient
    }

    func start(
        inputFile: URL,
        presetUuid: String,
        manualSettings: [String: Any],
        avoidOverwrite: Bool,
        outputSuffix: String,
        writeSettingsXml: Bool,
        channelToExtract: Int = 0,
        previewDuration: Double = 0,
        keepTimecode: Bool = false
    ) {
        self.originalSourceFile = inputFile
        self.sourceFile = inputFile
        self.presetId = presetUuid
        self.settings = manualSettings
        self.avoidOverwrite = avoidOverwrite
        self.outputSuffix = outputSuffix
        self.writeSettingsXml = writeSettingsXml
        self.extractChannel = channelToExtract
        self.previewDurationSeconds = previewDuration
        self.keepTimecode = keepTimecode
        self.cancelled = false
        self.targetExtension = nil
        self.lastOutputFile = nil

        // Resolve "keep" format
        if let format = settings["output_format"] as? String, format == "keep" {
            let ext = inputFile.pathExtension
            let resolved = OutputFormat.resolveKeep(for: ext)
            settings["output_format"] = resolved.format
            targetExtension = resolved.targetExtension
        }

        print("[ProcessingWorkflow] start: extractChannel=\(extractChannel), previewDuration=\(previewDurationSeconds)")

        if extractChannel != 0 {
            progress = 0.0
            setState(.extractingChannel)
            stepExtractChannel()
        } else if previewDurationSeconds > 0 {
            progress = 0.05
            setState(.trimming)
            stepTrimPreview()
        } else {
            progress = 0.10
            setState(.creatingProduction)
            stepCreateProduction()
        }
    }

    func cancel() {
        cancelled = true
        pollTimer?.invalidate()
        pollTimer = nil
        cleanupTempFiles()
        setState(.idle)
    }

    func setTempOutputMode(_ enabled: Bool) {
        tempOutputMode = enabled
    }

    func setOutputDirectory(_ url: URL?) {
        outputDirectory = url
    }

    // MARK: - State

    private func setState(_ newState: ProcessingState) {
        state = newState
        statusText = newState.statusText
        if case .error = newState {
            progress = -1
        }
    }

    private func setError(_ message: String) {
        cleanupTempFiles()
        setState(.error(message))
    }

    // MARK: - Step: Extract Channel

    private func stepExtractChannel() {
        guard let inputFile = sourceFile else { return setError("No input file") }

        Task.detached { [self] in
            do {
                let file = try AVAudioFile(forReading: inputFile)
                let format = file.processingFormat
                let channelCount = Int(format.channelCount)
                let frameCount = AVAudioFrameCount(file.length)

                guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                    throw NSError(domain: "AuphonicApp", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
                }
                try file.read(into: inputBuffer)

                let outputChannels: Int
                var channelIndicesToCopy: [Int]

                if self.extractChannel == -1 {
                    // L+R stereo
                    outputChannels = min(2, channelCount)
                    channelIndicesToCopy = Array(0..<outputChannels)
                } else {
                    // Single channel (1-based)
                    let chIdx = self.extractChannel - 1
                    guard chIdx >= 0, chIdx < channelCount else {
                        throw NSError(domain: "AuphonicApp", code: 2, userInfo: [NSLocalizedDescriptionKey: "Channel \(self.extractChannel) does not exist"])
                    }
                    outputChannels = 1
                    channelIndicesToCopy = [chIdx]
                }

                let outputSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: outputChannels,
                    AVLinearPCMBitDepthKey: 24,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]

                // Create a float buffer for in-memory channel copying
                // (AVAudioFile handles the int conversion on write)
                guard let outFloatFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                         sampleRate: format.sampleRate,
                                                         channels: AVAudioChannelCount(outputChannels),
                                                         interleaved: false),
                      let outBuffer = AVAudioPCMBuffer(pcmFormat: outFloatFormat, frameCapacity: frameCount) else {
                    throw NSError(domain: "AuphonicApp", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create output format"])
                }
                outBuffer.frameLength = frameCount

                guard let inData = inputBuffer.floatChannelData,
                      let outData = outBuffer.floatChannelData else {
                    throw NSError(domain: "AuphonicApp", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to access audio data"])
                }

                for (outCh, inCh) in channelIndicesToCopy.enumerated() {
                    for i in 0..<Int(frameCount) {
                        outData[outCh][i] = inData[inCh][i]
                    }
                }

                let tempFile = FileManager.default.temporaryDirectory
                    .appendingPathComponent("auphonic_extract_\(Int64.random(in: 0...Int64.max)).wav")
                let outputFile = try AVAudioFile(forWriting: tempFile, settings: outputSettings)
                try outputFile.write(from: outBuffer)

                await MainActor.run {
                    self.extractedTempFile = tempFile
                    self.sourceFile = tempFile
                    if self.previewDurationSeconds > 0 {
                        self.progress = 0.05
                        self.setState(.trimming)
                        self.stepTrimPreview()
                    } else {
                        self.progress = 0.10
                        self.setState(.creatingProduction)
                        self.stepCreateProduction()
                    }
                }
            } catch {
                await MainActor.run { self.setError(error.localizedDescription) }
            }
        }
    }

    // MARK: - Step: Trim Preview

    private func stepTrimPreview() {
        guard let inputFile = sourceFile else { return setError("No input file") }

        Task.detached { [self] in
            do {
                let file = try AVAudioFile(forReading: inputFile)
                let sampleRate = file.processingFormat.sampleRate
                let maxFrames = AVAudioFrameCount(self.previewDurationSeconds * sampleRate)
                let framesToRead = min(maxFrames, AVAudioFrameCount(file.length))

                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: framesToRead) else {
                    throw NSError(domain: "AuphonicApp", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
                }
                try file.read(into: buffer, frameCount: framesToRead)

                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: Int(file.processingFormat.channelCount),
                    AVLinearPCMBitDepthKey: 24,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]

                let tempFile = FileManager.default.temporaryDirectory
                    .appendingPathComponent("auphonic_trim_\(Int64.random(in: 0...Int64.max)).wav")
                let outputFile = try AVAudioFile(forWriting: tempFile, settings: settings)
                try outputFile.write(from: buffer)

                await MainActor.run {
                    self.trimmedTempFile = tempFile
                    self.sourceFile = tempFile
                    self.progress = 0.10
                    self.setState(.creatingProduction)
                    self.stepCreateProduction()
                }
            } catch {
                await MainActor.run { self.setError(error.localizedDescription) }
            }
        }
    }

    // MARK: - Step: Create Production

    private func stepCreateProduction() {
        guard !cancelled else { return }
        let title = originalSourceFile?.deletingPathExtension().lastPathComponent ?? "Untitled"

        Task {
            do {
                let uuid = try await apiClient.createProduction(
                    presetUuid: presetId,
                    manualSettings: settings,
                    title: title
                )
                await MainActor.run {
                    self.productionUuid = uuid
                    self.progress = 0.15
                    self.setState(.uploading)
                    self.stepUpload()
                }
            } catch {
                await MainActor.run { self.setError(error.localizedDescription) }
            }
        }
    }

    // MARK: - Step: Upload

    private func stepUpload() {
        guard !cancelled, let file = sourceFile else { return }

        Task {
            do {
                try await apiClient.uploadFile(productionUuid: productionUuid, file: file) { [weak self] fraction in
                    DispatchQueue.main.async {
                        // Upload: 0.15 → 0.45
                        self?.progress = 0.15 + fraction * 0.30
                        self?.statusText = "Uploading: \(Int(fraction * 100))%"
                    }
                }
                await MainActor.run {
                    self.progress = 0.45
                    self.setState(.starting)
                    self.stepStart()
                }
            } catch {
                await MainActor.run { self.setError(error.localizedDescription) }
            }
        }
    }

    // MARK: - Step: Start

    private func stepStart() {
        guard !cancelled else { return }

        Task {
            do {
                try await apiClient.startProduction(productionUuid: productionUuid)
                await MainActor.run {
                    self.progress = 0.50
                    self.setState(.processing)
                    self.startPolling()
                }
            } catch {
                await MainActor.run { self.setError(error.localizedDescription) }
            }
        }
    }

    // MARK: - Step: Poll Status

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pollStatus()
        }
    }

    private func pollStatus() {
        guard !cancelled else { return }

        Task {
            do {
                let status = try await apiClient.getProductionStatus(productionUuid: productionUuid)
                await MainActor.run {
                    if self.cancelled { return }

                    // Processing: 0.50 → 0.80
                    self.progress = 0.50 + status.progress * 0.30
                    self.statusText = "Processing: \(Int(status.progress * 100))%"

                    if status.isDone {
                        self.pollTimer?.invalidate()
                        self.pollTimer = nil
                        if !status.outputFileUrl.isEmpty {
                            self.progress = 0.80
                            self.setState(.downloading)
                            self.stepDownload(url: status.outputFileUrl)
                        } else {
                            self.setError("No output file URL")
                        }
                    } else if status.isError {
                        self.pollTimer?.invalidate()
                        self.pollTimer = nil
                        self.setError(status.errorMessage.isEmpty ? "Processing failed" : status.errorMessage)
                    }
                }
            } catch {
                // Don't fail on transient poll errors, just retry
            }
        }
    }

    // MARK: - Step: Download

    private func stepDownload(url: String) {
        guard !cancelled else { return }

        Task {
            do {
                let tempFile = try await apiClient.downloadFile(from: url) { [weak self] fraction in
                    DispatchQueue.main.async {
                        // Download: 0.80 → 0.95
                        self?.progress = 0.80 + fraction * 0.15
                        self?.statusText = "Downloading: \(Int(fraction * 100))%"
                    }
                }
                await MainActor.run {
                    self.progress = 0.95
                    if self.targetExtension != nil {
                        self.setState(.converting)
                        self.stepConvert(tempFile: tempFile)
                    } else {
                        self.setState(.saving)
                        self.stepSave(tempFile: tempFile)
                    }
                }
            } catch {
                await MainActor.run { self.setError(error.localizedDescription) }
            }
        }
    }

    // MARK: - Step: Convert (WAV → AIFF etc.)

    private func stepConvert(tempFile: URL) {
        guard !cancelled else { return }

        Task.detached { [self] in
            do {
                let inputFile = try AVAudioFile(forReading: tempFile)
                let format = inputFile.processingFormat
                let frameCount = AVAudioFrameCount(inputFile.length)

                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                    throw NSError(domain: "AuphonicApp", code: 6, userInfo: [NSLocalizedDescriptionKey: "Conversion buffer failed"])
                }
                try inputFile.read(into: buffer)

                let convertedFile = FileManager.default.temporaryDirectory
                    .appendingPathComponent("auphonic_convert_\(Int64.random(in: 0...Int64.max))")
                    .appendingPathExtension(self.targetExtension ?? "aif")

                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: Int(format.channelCount),
                    AVLinearPCMBitDepthKey: 24,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: true,  // AIFF is big-endian
                    AVLinearPCMIsNonInterleaved: false
                ]

                let outputFile = try AVAudioFile(forWriting: convertedFile, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
                try outputFile.write(from: buffer)

                try? FileManager.default.removeItem(at: tempFile)

                await MainActor.run {
                    self.setState(.saving)
                    self.stepSave(tempFile: convertedFile)
                }
            } catch {
                await MainActor.run { self.setError(error.localizedDescription) }
            }
        }
    }

    // MARK: - Step: Save

    private func stepSave(tempFile: URL) {
        guard !cancelled else { return }

        Task.detached { [self] in
            do {
                let finalURL: URL

                if self.tempOutputMode {
                    // Per-channel mode: keep in /tmp
                    finalURL = tempFile
                } else {
                    guard let original = self.originalSourceFile else {
                        throw NSError(domain: "AuphonicApp", code: 7, userInfo: [NSLocalizedDescriptionKey: "No original file reference"])
                    }

                    // Use explicit output directory if set, otherwise save next to original
                    let dir: URL
                    if let outputDir = self.outputDirectory {
                        _ = outputDir.startAccessingSecurityScopedResource()
                        dir = outputDir
                    } else {
                        dir = original.deletingLastPathComponent()
                    }
                    defer {
                        if self.outputDirectory != nil {
                            self.outputDirectory?.stopAccessingSecurityScopedResource()
                        }
                    }
                    let baseName = original.deletingPathExtension().lastPathComponent
                    let ext = self.targetExtension ?? tempFile.pathExtension

                    var outputName = baseName
                    if self.avoidOverwrite {
                        outputName += self.outputSuffix
                    }

                    var outputURL = dir.appendingPathComponent(outputName).appendingPathExtension(ext)

                    // If avoiding overwrite and file exists, append number
                    if self.avoidOverwrite {
                        var counter = 2
                        while FileManager.default.fileExists(atPath: outputURL.path) {
                            outputURL = dir.appendingPathComponent("\(outputName)_\(counter)").appendingPathExtension(ext)
                            counter += 1
                        }
                    }

                    try FileManager.default.moveItem(at: tempFile, to: outputURL)
                    finalURL = outputURL

                    // Write settings XML if requested
                    if self.writeSettingsXml {
                        let jsonURL = finalURL.deletingPathExtension().appendingPathExtension("json")
                        if let jsonData = try? JSONSerialization.data(withJSONObject: self.settings, options: .prettyPrinted) {
                            try? jsonData.write(to: jsonURL)
                        }
                    }

                    // Downgrade WaveFormatExtensible to simple PCM
                    if ext.lowercased() == "wav" {
                        WavChunkCopier.downgradeToSimplePcm(file: finalURL)
                    }

                    // Keep timecode (copy WAV metadata chunks)
                    if self.keepTimecode, ext.lowercased() == "wav",
                       let original = self.originalSourceFile {
                        if var ixmlData = WavChunkCopier.readIxmlChunk(from: original) {
                            let bitDepth = WavChunkCopier.readWavBitDepth(from: finalURL)
                            ixmlData = WavChunkCopier.updateIxmlForOutput(
                                ixmlData: ixmlData,
                                outputBitDepth: bitDepth > 0 ? bitDepth : 24,
                                extractedChannel: self.extractChannel
                            )
                            _ = WavChunkCopier.writeChunk(to: finalURL, chunkId: "iXML", data: ixmlData)
                        }
                        if let bextData = WavChunkCopier.readChunk(from: original, chunkId: "bext") {
                            _ = WavChunkCopier.writeChunk(to: finalURL, chunkId: "bext", data: bextData)
                        }
                        _ = WavChunkCopier.removeChunk(from: finalURL, chunkId: "LIST")
                    }
                }

                await MainActor.run {
                    self.lastOutputFile = finalURL
                    self.cleanupTempFiles()
                    self.progress = 1.0
                    self.setState(.done)
                }
            } catch {
                await MainActor.run { self.setError(error.localizedDescription) }
            }
        }
    }

    // MARK: - Cleanup

    private func cleanupTempFiles() {
        if let f = extractedTempFile { try? FileManager.default.removeItem(at: f) }
        if let f = trimmedTempFile { try? FileManager.default.removeItem(at: f) }
        extractedTempFile = nil
        trimmedTempFile = nil
    }
}
