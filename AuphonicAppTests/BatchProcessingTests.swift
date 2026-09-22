import Testing
import Foundation
import AVFoundation
@testable import AuphonicApp

// MARK: - Test WAV Helpers

private func tempWavURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("auphonic_test_\(UUID().uuidString).wav")
}

/// Create a WAV where every channel holds a constant sample value.
private func makeWav(
    url: URL,
    channels: Int,
    frames: Int = 4800,
    bitDepth: Int = 24,
    isFloat: Bool = false,
    sampleRate: Double = 48000,
    channelValue: (Int) -> Float
) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: channels,
        AVLinearPCMBitDepthKey: bitDepth,
        AVLinearPCMIsFloatKey: isFloat,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings)
    // Formats with >2 channels need an explicit channel layout
    guard let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)) else {
        throw NSError(domain: "test", code: 1)
    }
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                               sampleRate: sampleRate,
                               interleaved: false,
                               channelLayout: layout)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else {
        throw NSError(domain: "test", code: 1)
    }
    buffer.frameLength = AVAudioFrameCount(frames)
    for ch in 0..<channels {
        let value = channelValue(ch)
        for i in 0..<frames {
            buffer.floatChannelData![ch][i] = value
        }
    }
    try file.write(from: buffer)
}

/// Read all samples of one 0-based channel as floats
private func readChannel(_ url: URL, channel: Int) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let frames = AVAudioFrameCount(file.length)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
        throw NSError(domain: "test", code: 2)
    }
    try file.read(into: buffer)
    return Array(UnsafeBufferPointer(start: buffer.floatChannelData![channel],
                                     count: Int(buffer.frameLength)))
}

/// bext chunk payload with the given TimeReference
private func bextData(timeReference: UInt64) -> Data {
    var data = Data(count: 602)
    data.withUnsafeMutableBytes { raw in
        raw.storeBytes(of: UInt32(truncatingIfNeeded: timeReference).littleEndian,
                       toByteOffset: 338, as: UInt32.self)
        raw.storeBytes(of: UInt32(truncatingIfNeeded: timeReference >> 32).littleEndian,
                       toByteOffset: 342, as: UInt32.self)
    }
    return data
}

// MARK: - BWF Timecode

struct BextTimecodeTests {

    @Test func readTimeReferenceRoundtrip() throws {
        let url = tempWavURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try makeWav(url: url, channels: 2) { _ in 0 }

        let tc: UInt64 = 48000 * 3600 * 10 + 12345   // 10h + a bit, exceeds 32 bits
        #expect(WavChunkCopier.writeChunk(to: url, chunkId: "bext", data: bextData(timeReference: tc)))
        #expect(WavChunkCopier.readBextTimeReference(from: url) == tc)
    }

    @Test func missingBextReturnsNil() throws {
        let url = tempWavURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try makeWav(url: url, channels: 1) { _ in 0 }
        #expect(WavChunkCopier.readBextTimeReference(from: url) == nil)
    }

    @Test func readsTimecodeRateFromIxml() throws {
        let url = tempWavURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try makeWav(url: url, channels: 1) { _ in 0 }

        let ixml = "<BWFXML><SPEED><TIMECODE_RATE>25/1</TIMECODE_RATE></SPEED></BWFXML>"
        #expect(WavChunkCopier.writeChunk(to: url, chunkId: "iXML", data: ixml.data(using: .utf8)!))
        #expect(WavChunkCopier.readIxmlTimecodeRate(from: url) == 25.0)
    }

    @Test func readsFractionalTimecodeRate() throws {
        let url = tempWavURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try makeWav(url: url, channels: 1) { _ in 0 }

        let ixml = "<BWFXML><SPEED><TIMECODE_RATE>30000/1001</TIMECODE_RATE></SPEED></BWFXML>"
        #expect(WavChunkCopier.writeChunk(to: url, chunkId: "iXML", data: ixml.data(using: .utf8)!))
        let rate = try #require(WavChunkCopier.readIxmlTimecodeRate(from: url))
        #expect(abs(rate - 29.97) < 0.01)
    }
}

// MARK: - Grouping

struct FileGrouperTests {

    private func makeBatchFile(channels: Int, timecode: UInt64?) throws -> BatchFile {
        let url = tempWavURL()
        try makeWav(url: url, channels: channels) { _ in 0 }
        if let tc = timecode {
            _ = WavChunkCopier.writeChunk(to: url, chunkId: "bext", data: bextData(timeReference: tc))
        }
        guard let file = BatchFile(url: url) else { throw NSError(domain: "test", code: 3) }
        return file
    }

    @Test func groupsAdjacentFilesWithSameChannelCount() throws {
        // Added out of order on purpose; timecode order is 2ch, 2ch, 5ch, 2ch
        let a = try makeBatchFile(channels: 2, timecode: 1_000_000)
        let b = try makeBatchFile(channels: 5, timecode: 3_000_000)
        let c = try makeBatchFile(channels: 2, timecode: 2_000_000)
        let d = try makeBatchFile(channels: 2, timecode: 4_000_000)
        defer { for f in [a, b, c, d] { try? FileManager.default.removeItem(at: f.url) } }

        let groups = FileGrouper.makeGroups(from: [d, b, a, c])

        #expect(groups.count == 3)
        #expect(groups[0].channelCount == 2)
        #expect(groups[0].files.map(\.id) == [a.id, c.id])
        #expect(groups[1].channelCount == 5)
        #expect(groups[1].files.map(\.id) == [b.id])
        #expect(groups[2].channelCount == 2)
        #expect(groups[2].files.map(\.id) == [d.id])
    }

    @Test func regroupingKeepsExistingConfig() throws {
        let a = try makeBatchFile(channels: 4, timecode: 1_000_000)
        let b = try makeBatchFile(channels: 4, timecode: 2_000_000)
        defer { for f in [a, b] { try? FileManager.default.removeItem(at: f.url) } }

        let firstPass = FileGrouper.makeGroups(from: [a])
        firstPass[0].config.linkedSettings = false
        firstPass[0].config.channels[1].enabled = false

        let secondPass = FileGrouper.makeGroups(from: [a, b], previousGroups: firstPass)

        #expect(secondPass.count == 1)
        #expect(secondPass[0].files.count == 2)
        #expect(secondPass[0].config === firstPass[0].config)
        #expect(secondPass[0].config.linkedSettings == false)
        #expect(secondPass[0].config.channels[1].enabled == false)
    }
}

// MARK: - Channel Extraction

struct ChannelExtractionTests {

    @Test func extractsSelectedChannelsInJobOrder() throws {
        let source = tempWavURL()
        defer { try? FileManager.default.removeItem(at: source) }
        try makeWav(url: source, channels: 4) { ch in Float(ch + 1) * 0.1 }

        let extracted = try BatchWorkflow.extractChannels(
            from: source, channels: [2, 4], isFloat: false, bitDepth: 24)
        defer { try? FileManager.default.removeItem(at: extracted) }

        let left = try readChannel(extracted, channel: 0)
        let right = try readChannel(extracted, channel: 1)
        #expect(abs(left[0] - 0.2) < 1e-5)
        #expect(abs(right[0] - 0.4) < 1e-5)
        #expect(left.count == 4800)
    }

    @Test func maxDurationTrimsTheExcerpt() throws {
        let source = tempWavURL()
        defer { try? FileManager.default.removeItem(at: source) }
        // 4 seconds at 48 kHz
        try makeWav(url: source, channels: 3, frames: 192_000) { ch in Float(ch + 1) * 0.1 }

        let extracted = try BatchWorkflow.extractChannels(
            from: source, channels: [1, 2], isFloat: false, bitDepth: 24, maxDuration: 2.0)
        defer { try? FileManager.default.removeItem(at: extracted) }

        let file = try AVAudioFile(forReading: extracted)
        #expect(file.length == 96_000)   // exactly 2 seconds
        let samples = try readChannel(extracted, channel: 0)
        #expect(abs(samples[0] - 0.1) < 1e-5)
    }

    @Test func preservesFloatFormat() throws {
        let source = tempWavURL()
        defer { try? FileManager.default.removeItem(at: source) }
        try makeWav(url: source, channels: 3, bitDepth: 32, isFloat: true) { ch in Float(ch) * 0.25 }

        let extracted = try BatchWorkflow.extractChannels(
            from: source, channels: [3], isFloat: true, bitDepth: 32)
        defer { try? FileManager.default.removeItem(at: extracted) }

        let info = try #require(WavChunkCopier.readFormatInfo(from: extracted))
        #expect(info.isFloat)
        #expect(info.bitsPerSample == 32)
        let samples = try readChannel(extracted, channel: 0)
        #expect(samples[0] == 0.5)
    }
}

// MARK: - Channel Replacement

struct ChannelReplacerTests {

    @Test func replacesOnlySelectedChannelsAndKeepsMetadata() throws {
        let original = tempWavURL()
        let processed = tempWavURL()
        let output = tempWavURL()
        defer { for f in [original, processed, output] { try? FileManager.default.removeItem(at: f) } }

        try makeWav(url: original, channels: 4, bitDepth: 24) { ch in Float(ch + 1) * 0.1 }

        // Attach metadata that must survive untouched
        let ixml = "<BWFXML><PROJECT>TestShoot</PROJECT></BWFXML>".data(using: .utf8)!
        #expect(WavChunkCopier.writeChunk(to: original, chunkId: "iXML", data: ixml))
        #expect(WavChunkCopier.writeChunk(to: original, chunkId: "bext", data: bextData(timeReference: 123456789)))

        // Stereo "processed" file replaces channels 2 and 4
        try makeWav(url: processed, channels: 2, bitDepth: 24) { ch in ch == 0 ? 0.7 : -0.5 }

        let originalBytesBefore = try Data(contentsOf: original)

        try ChannelReplacer.replaceChannels(
            original: original,
            output: output,
            replacements: [(channelIndices: [2, 4], file: processed)]
        )

        // Original untouched
        #expect(try Data(contentsOf: original) == originalBytesBefore)

        // Untouched channels are bit-identical, replaced channels carry new audio
        let ch1 = try readChannel(output, channel: 0)
        let ch2 = try readChannel(output, channel: 1)
        let ch3 = try readChannel(output, channel: 2)
        let ch4 = try readChannel(output, channel: 3)
        let origCh1 = try readChannel(original, channel: 0)
        let origCh3 = try readChannel(original, channel: 2)

        #expect(ch1 == origCh1)
        #expect(ch3 == origCh3)
        #expect(abs(ch2[0] - 0.7) < 1e-5)
        #expect(abs(ch4[0] - (-0.5)) < 1e-5)
        #expect(abs(ch2[ch2.count - 1] - 0.7) < 1e-5)

        // Metadata preserved in the output
        #expect(WavChunkCopier.readChunk(from: output, chunkId: "iXML") == ixml)
        #expect(WavChunkCopier.readBextTimeReference(from: output) == 123456789)
    }

    @Test func preserves32BitFloatContainer() throws {
        let original = tempWavURL()
        let processed = tempWavURL()
        let output = tempWavURL()
        defer { for f in [original, processed, output] { try? FileManager.default.removeItem(at: f) } }

        try makeWav(url: original, channels: 3, bitDepth: 32, isFloat: true) { ch in Float(ch + 1) * 0.2 }
        try makeWav(url: processed, channels: 1, bitDepth: 24) { _ in 0.65 }

        try ChannelReplacer.replaceChannels(
            original: original,
            output: output,
            replacements: [(channelIndices: [2], file: processed)]
        )

        let info = try #require(WavChunkCopier.readFormatInfo(from: output))
        #expect(info.isFloat)
        #expect(info.bitsPerSample == 32)

        let ch1 = try readChannel(output, channel: 0)
        let ch2 = try readChannel(output, channel: 1)
        let ch3 = try readChannel(output, channel: 2)
        #expect(ch1[0] == 0.2)              // untouched, bit-exact
        #expect(abs(ch2[0] - 0.65) < 1e-5)  // replaced (24-bit source precision)
        #expect(ch3[0] == 0.6000000238418579 || abs(ch3[0] - 0.6) < 1e-6)
    }

    @Test func shorterProcessedFileFillsRestWithSilence() throws {
        let original = tempWavURL()
        let processed = tempWavURL()
        let output = tempWavURL()
        defer { for f in [original, processed, output] { try? FileManager.default.removeItem(at: f) } }

        try makeWav(url: original, channels: 2, frames: 4800, bitDepth: 24) { _ in 0.3 }
        try makeWav(url: processed, channels: 1, frames: 2400, bitDepth: 24) { _ in 0.9 }

        try ChannelReplacer.replaceChannels(
            original: original,
            output: output,
            replacements: [(channelIndices: [1], file: processed)]
        )

        let ch1 = try readChannel(output, channel: 0)
        #expect(abs(ch1[0] - 0.9) < 1e-5)
        #expect(ch1[4799] == 0)
        let ch2 = try readChannel(output, channel: 1)
        #expect(abs(ch2[4799] - 0.3) < 1e-5)
    }

    @Test func refusesToOverwriteOriginal() throws {
        let original = tempWavURL()
        defer { try? FileManager.default.removeItem(at: original) }
        try makeWav(url: original, channels: 2) { _ in 0 }

        #expect(throws: ChannelReplacerError.self) {
            try ChannelReplacer.replaceChannels(original: original, output: original, replacements: [])
        }
    }
}

// MARK: - Folder Expansion

struct CollectAudioURLsTests {

    @Test func expandsFoldersRecursivelyAndFiltersNonAudio() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("auphonic_folder_\(UUID().uuidString)")
        let sub = root.appendingPathComponent("Card1")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let wavA = root.appendingPathComponent("b.wav")
        let wavB = sub.appendingPathComponent("a.WAV")
        let other = root.appendingPathComponent("notes.txt")
        for f in [wavA, wavB, other] { try Data([1]).write(to: f) }

        let loose = FileManager.default.temporaryDirectory
            .appendingPathComponent("auphonic_loose_\(UUID().uuidString).wav")
        try Data([1]).write(to: loose)
        defer { try? FileManager.default.removeItem(at: loose) }

        // Folder + loose file + duplicate of a file already inside the folder
        let collected = AppViewModel.collectAudioURLs(from: [root, loose, wavA])

        #expect(collected.count == 3)
        #expect(Set(collected.map(\.lastPathComponent)) == ["a.WAV", "b.wav", loose.lastPathComponent])
    }

    /// Everything Core Audio can decode is collected, not just WAV
    @Test func collectsAllAudioFormats() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("auphonic_formats_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let audioNames = ["take.wav", "take.aif", "take.aiff", "take.caf",
                          "take.mp3", "take.m4a", "take.flac", "take.aac"]
        let ignoredNames = ["notes.txt", "sheet.pdf", "clip.mov", "art.png"]
        for name in audioNames + ignoredNames {
            try Data([1]).write(to: root.appendingPathComponent(name))
        }

        let collected = AppViewModel.collectAudioURLs(from: [root])
        #expect(Set(collected.map(\.lastPathComponent)) == Set(audioNames))
    }

    @Test func nonexistentURLsAreIgnored() {
        let ghost = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).wav")
        #expect(AppViewModel.collectAudioURLs(from: [ghost]).isEmpty)
    }
}

// MARK: - Output Naming

struct OutputNamingTests {

    @Test func neverResolvesToOriginalPath() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("auphonic_test_dir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = dir.appendingPathComponent("scene.wav")
        try Data([1]).write(to: original)

        let resolved = BatchWorkflow.resolveOutputURL(for: original, destination: dir)
        #expect(resolved.lastPathComponent == "scene_2.wav")
    }

    @Test func usesOriginalNameInOtherFolder() throws {
        let srcDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("auphonic_src_\(UUID().uuidString)")
        let destDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("auphonic_dest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: srcDir)
            try? FileManager.default.removeItem(at: destDir)
        }

        let original = srcDir.appendingPathComponent("scene.wav")
        try Data([1]).write(to: original)

        let resolved = BatchWorkflow.resolveOutputURL(for: original, destination: destDir)
        #expect(resolved.lastPathComponent == "scene.wav")

        // Occupied name falls back to a counter
        try Data([1]).write(to: resolved)
        let second = BatchWorkflow.resolveOutputURL(for: original, destination: destDir)
        #expect(second.lastPathComponent == "scene_2.wav")
    }
}


// MARK: - Cancellation

struct CancellationClassificationTests {

    @Test func cancellationErrorIsCancellation() {
        #expect(BatchWorkflow.isCancellation(CancellationError()))
    }

    /// A cancelled URLSession transfer throws URLError.cancelled, not
    /// CancellationError; it used to mark the file as failed.
    @Test func cancelledTransferIsCancellation() {
        #expect(BatchWorkflow.isCancellation(URLError(.cancelled)))
    }

    @Test func otherErrorsAreFailures() {
        #expect(!BatchWorkflow.isCancellation(URLError(.timedOut)))
        #expect(!BatchWorkflow.isCancellation(AuphonicAPIClient.APIError.invalidToken))
    }

    /// Any error surfacing after the task was cancelled counts as cancellation
    @Test func errorsInsideCancelledTaskAreCancellation() async {
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return BatchWorkflow.isCancellation(URLError(.timedOut))
        }
        task.cancel()
        #expect(await task.value)
    }
}
