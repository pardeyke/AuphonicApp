import AVFoundation
import CoreAudio
import AudioToolbox

@Observable
final class AudioPlayerService {
    enum Slot {
        case original
        case processed
    }

    private(set) var isPlaying = false
    private(set) var activeSlot: Slot = .original
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var hasOriginal = false
    private(set) var hasProcessed = false

    private(set) var originalWaveform: [Float] = []
    private(set) var processedWaveform: [Float] = []
    private(set) var originalDuration: TimeInterval = 0
    private(set) var processedDuration: TimeInterval = 0

    // Cached per-channel waveforms (key: channel index, 0=all)
    private var waveformCacheA: [Int: [Float]] = [:]
    private var waveformCacheB: [Int: [Float]] = [:]

    // Channel solo (0 = all, 1-N = solo that channel)
    private(set) var soloChannelA: Int = 0
    private(set) var soloChannelB: Int = 0
    private(set) var channelCountA: Int = 0
    private(set) var channelCountB: Int = 0
    private(set) var trackNamesA: [String] = []
    private(set) var trackNamesB: [String] = []

    private var engine = AVAudioEngine()
    private var playerNodeA = AVAudioPlayerNode()
    private var playerNodeB = AVAudioPlayerNode()

    private var audioFileA: AVAudioFile?
    private var audioFileB: AVAudioFile?

    private var displayTimer: Timer?
    private var lastSeekFrame: AVAudioFramePosition = 0

    // Chunked streaming state
    private var nextReadFrame: AVAudioFramePosition = 0
    private var isStreaming = false
    private var streamGeneration: UInt64 = 0
    private let chunkSeconds: Double = 1.0
    private let aheadChunks = 3

    nonisolated init() {}

    private func ensureEngineSetup() {
        guard playerNodeA.engine == nil else { return }
        engine.attach(playerNodeA)
        engine.attach(playerNodeB)
    }

    // MARK: - Loading

    func loadOriginal(url: URL) {
        stop()
        soloChannelA = 0
        waveformCacheA = [:]
        do {
            let file = try AVAudioFile(forReading: url)
            audioFileA = file
            hasOriginal = true
            activeSlot = .original
            channelCountA = Int(file.processingFormat.channelCount)
            trackNamesA = WavChunkCopier.readIxmlTrackNames(from: url)
            originalDuration = Double(file.length) / file.processingFormat.sampleRate
            duration = originalDuration
            originalWaveform = []
            reconnectAndStart()
            generateAllWaveformsAsync(file: file, slot: .original)
        } catch {
            print("Failed to load original: \(error)")
        }
    }

    func loadProcessed(url: URL) {
        soloChannelB = 0
        waveformCacheB = [:]
        do {
            let file = try AVAudioFile(forReading: url)
            audioFileB = file
            hasProcessed = true
            channelCountB = Int(file.processingFormat.channelCount)
            trackNamesB = WavChunkCopier.readIxmlTrackNames(from: url)
            processedDuration = Double(file.length) / file.processingFormat.sampleRate
            processedWaveform = []
            reconnectAndStart()
            generateAllWaveformsAsync(file: file, slot: .processed)
        } catch {
            print("Failed to load processed: \(error)")
        }
    }

    func clearProcessed() {
        if isPlaying && activeSlot == .processed {
            switchTo(.original)
        }
        playerNodeB.stop()
        audioFileB = nil
        hasProcessed = false
        processedWaveform = []
        waveformCacheB = [:]
        channelCountB = 0
        soloChannelB = 0
        trackNamesB = []
    }

    private func reconnectAndStart() {
        let wasPlaying = isPlaying
        let savedFrame = lastSeekFrame

        stopStreaming()
        playerNodeA.stop()
        playerNodeB.stop()
        isPlaying = false
        stopDisplayTimer()

        if engine.isRunning { engine.stop() }

        ensureEngineSetup()

        engine.disconnectNodeOutput(playerNodeA)
        engine.disconnectNodeOutput(playerNodeB)

        if let file = audioFileA {
            let stereo = AVAudioFormat(standardFormatWithSampleRate: file.processingFormat.sampleRate, channels: 2)!
            engine.connect(playerNodeA, to: engine.mainMixerNode, format: stereo)
        }
        if let file = audioFileB {
            let stereo = AVAudioFormat(standardFormatWithSampleRate: file.processingFormat.sampleRate, channels: 2)!
            engine.connect(playerNodeB, to: engine.mainMixerNode, format: stereo)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
            return
        }

        if wasPlaying {
            lastSeekFrame = savedFrame
            play()
        }
    }

    // MARK: - Chunked Streaming Playback

    func play() {
        guard !isPlaying else { return }
        guard activeFile != nil else { return }

        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch { print("Engine start failed: \(error)"); return }
        }

        let node = activeNode
        node.stop()

        // Start streaming from current position
        startStreaming(from: lastSeekFrame)
        node.play()
        isPlaying = true
        startDisplayTimer()
    }

    private func startStreaming(from frame: AVAudioFramePosition) {
        streamGeneration += 1
        nextReadFrame = frame
        isStreaming = true
        for _ in 0..<aheadChunks {
            scheduleNextChunk()
        }
    }

    private func stopStreaming() {
        isStreaming = false
    }

    private func scheduleNextChunk() {
        guard isStreaming, let file = activeFile else { return }

        // Loop: wrap to beginning
        if nextReadFrame >= file.length {
            nextReadFrame = 0
        }

        let srcFormat = file.processingFormat
        let sampleRate = srcFormat.sampleRate
        let chunkFrames = AVAudioFrameCount(chunkSeconds * sampleRate)
        let remaining = AVAudioFrameCount(file.length - nextReadFrame)
        let count = min(chunkFrames, remaining)

        // Read in native format
        guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: count) else { return }
        file.framePosition = nextReadFrame
        do {
            try file.read(into: srcBuffer, frameCount: count)
        } catch { return }

        // Convert to stereo output buffer
        let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: count) else { return }
        outBuffer.frameLength = srcBuffer.frameLength

        guard let srcData = srcBuffer.floatChannelData,
              let outData = outBuffer.floatChannelData else { return }

        let frames = Int(srcBuffer.frameLength)
        let srcChannels = Int(srcFormat.channelCount)
        let solo = activeSlot == .original ? soloChannelA : soloChannelB
        let byteCount = frames * MemoryLayout<Float>.size

        if solo > 0 && (solo - 1) < srcChannels {
            // Solo: copy chosen channel to both L and R
            let chIdx = solo - 1
            memcpy(outData[0], srcData[chIdx], byteCount)
            memcpy(outData[1], srcData[chIdx], byteCount)
        } else {
            // All: copy ch0→L, ch1→R (mono: duplicate)
            memcpy(outData[0], srcData[0], byteCount)
            memcpy(outData[1], srcChannels > 1 ? srcData[1] : srcData[0], byteCount)
        }

        nextReadFrame += AVAudioFramePosition(count)

        let gen = streamGeneration
        activeNode.scheduleBuffer(outBuffer, completionCallbackType: .dataConsumed) { [weak self] _ in
            DispatchQueue.main.async {
                self?.onChunkConsumed(generation: gen)
            }
        }
    }

    private func onChunkConsumed(generation: UInt64) {
        guard isStreaming, generation == streamGeneration else { return }
        scheduleNextChunk()
    }

    // MARK: - Pause / Stop

    func pause() {
        guard isPlaying else { return }
        lastSeekFrame = currentFrame
        stopStreaming()
        activeNode.stop()
        isPlaying = false
        stopDisplayTimer()
    }

    func stop() {
        stopStreaming()
        playerNodeA.stop()
        playerNodeB.stop()
        isPlaying = false
        currentTime = 0
        lastSeekFrame = 0
        stopDisplayTimer()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    // MARK: - Seek

    func seek(to fraction: Double) {
        guard let file = activeFile else { return }
        let frame = AVAudioFramePosition(fraction * Double(file.length))
        lastSeekFrame = frame
        let fileDuration = Double(file.length) / file.processingFormat.sampleRate
        currentTime = fraction * fileDuration

        if isPlaying {
            stopStreaming()
            activeNode.stop()
            startStreaming(from: frame)
            activeNode.play()
        }
    }

    /// Current playback frame (wraps for looping)
    private var currentFrame: AVAudioFramePosition {
        let node = activeNode
        guard let file = activeFile,
              let nodeTime = node.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = node.playerTime(forNodeTime: nodeTime) else {
            return lastSeekFrame
        }
        let raw = lastSeekFrame + playerTime.sampleTime
        let len = file.length
        guard len > 0 else { return 0 }
        return ((raw % len) + len) % len
    }

    // MARK: - A/B Switching

    func switchTo(_ slot: Slot) {
        guard slot != activeSlot else { return }
        guard (slot == .original && hasOriginal) || (slot == .processed && hasProcessed) else { return }

        let wasPlaying = isPlaying
        let savedFrame = currentFrame

        if isPlaying {
            stopStreaming()
            activeNode.stop()
            isPlaying = false
        }

        activeSlot = slot
        lastSeekFrame = savedFrame

        if wasPlaying {
            play()
        }
    }

    func toggleAB() {
        switchTo(activeSlot == .original ? .processed : .original)
    }

    // MARK: - Channel Solo (instant re-stream)

    func setSoloChannel(slot: Slot, channel: Int) {
        if slot == .original {
            soloChannelA = channel
            if let cached = waveformCacheA[channel] {
                originalWaveform = cached
            }
        } else {
            soloChannelB = channel
            if let cached = waveformCacheB[channel] {
                processedWaveform = cached
            }
        }

        // If this is the active slot and playing, restart stream with new solo
        if slot == activeSlot && isPlaying {
            let pos = currentFrame
            stopStreaming()
            activeNode.stop()
            lastSeekFrame = pos
            startStreaming(from: pos)
            activeNode.play()
        }
    }

    // MARK: - Active helpers

    private var activeFile: AVAudioFile? {
        activeSlot == .original ? audioFileA : audioFileB
    }

    private var activeNode: AVAudioPlayerNode {
        activeSlot == .original ? playerNodeA : playerNodeB
    }

    // MARK: - Output Device

    struct AudioDevice: Identifiable, Hashable {
        let id: AudioDeviceID
        let name: String
    }

    static func availableOutputDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else { return [] }

        var result: [AudioDevice] = []
        for deviceID in deviceIDs {
            var outputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var outputSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &outputAddress, 0, nil, &outputSize) == noErr,
                  outputSize > 0 else { continue }

            let bufferListData = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(outputSize))
            defer { bufferListData.deallocate() }
            guard AudioObjectGetPropertyData(deviceID, &outputAddress, 0, nil, &outputSize, bufferListData) == noErr else { continue }

            let bufferList = bufferListData.withMemoryRebound(to: AudioBufferList.self, capacity: 1) { $0.pointee }
            guard bufferList.mNumberBuffers > 0 else { continue }

            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
            var nameUnmanaged: Unmanaged<CFString>?
            guard AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &nameUnmanaged) == noErr,
                  let cfName = nameUnmanaged?.takeUnretainedValue() else { continue }

            result.append(AudioDevice(id: deviceID, name: cfName as String))
        }

        return result
    }

    func setOutputDevice(_ deviceID: AudioDeviceID) {
        let wasPlaying = isPlaying
        let savedFrame = currentFrame
        if isPlaying { stopStreaming(); activeNode.stop(); isPlaying = false }
        if engine.isRunning { engine.stop() }

        var deviceIDVar = deviceID
        let outputUnit = engine.outputNode.audioUnit!
        AudioUnitSetProperty(
            outputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceIDVar,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        reconnectAndStart()

        if wasPlaying {
            lastSeekFrame = savedFrame
            play()
        }
    }

    // MARK: - Display Timer

    private func startDisplayTimer() {
        stopDisplayTimer()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateCurrentTime()
            }
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    var isScrubbing = false

    private func updateCurrentTime() {
        guard isPlaying, !isScrubbing, let file = activeFile else { return }
        let frame = currentFrame
        currentTime = Double(frame) / file.processingFormat.sampleRate
    }

    // MARK: - Waveform Generation

    private var waveformGeneration: UInt64 = 0

    /// Reads the file once on a background thread and generates waveforms for all channels + combined.
    private func generateAllWaveformsAsync(file: AVAudioFile, slot: Slot) {
        waveformGeneration += 1
        let gen = waveformGeneration
        let url = file.url
        let resolution = 256

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let allWaveforms = Self.generateAllWaveforms(url: url, resolution: resolution) else { return }

            DispatchQueue.main.async {
                guard let self, self.waveformGeneration == gen else { return }
                let activeChannel = slot == .original ? self.soloChannelA : self.soloChannelB

                if slot == .original {
                    self.waveformCacheA = allWaveforms
                    self.originalWaveform = allWaveforms[activeChannel] ?? allWaveforms[0] ?? []
                } else {
                    self.waveformCacheB = allWaveforms
                    self.processedWaveform = allWaveforms[activeChannel] ?? allWaveforms[0] ?? []
                }
            }
        }
    }

    /// Reads the file once and returns waveforms for channel 0 (all) and each individual channel.
    private static func generateAllWaveforms(url: URL, resolution: Int) -> [Int: [Float]]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            return nil
        }

        file.framePosition = 0
        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }

        guard let channelData = buffer.floatChannelData else { return nil }
        let fileChannels = Int(file.processingFormat.channelCount)
        let totalFrames = Int(buffer.frameLength)
        let samplesPerBin = max(1, totalFrames / resolution)

        // Build all waveforms in a single pass
        var result: [Int: [Float]] = [:]
        // channel 0 = combined peak, 1..N = individual
        for ch in 0...fileChannels {
            result[ch] = [Float](repeating: 0, count: resolution)
        }

        for bin in 0..<resolution {
            let start = bin * samplesPerBin
            let end = min(start + samplesPerBin, totalFrames)
            var allMax: Float = 0
            for chIdx in 0..<fileChannels {
                var chMax: Float = 0
                for frame in start..<end {
                    let val = abs(channelData[chIdx][frame])
                    if val > chMax { chMax = val }
                }
                result[chIdx + 1]![bin] = chMax
                if chMax > allMax { allMax = chMax }
            }
            result[0]![bin] = allMax
        }

        return result
    }

    // MARK: - File Info

    var originalChannelCount: Int {
        guard let file = audioFileA else { return 0 }
        return Int(file.processingFormat.channelCount)
    }

    var originalSampleRate: Double {
        guard let file = audioFileA else { return 0 }
        return file.processingFormat.sampleRate
    }

    deinit {
        displayTimer?.invalidate()
        playerNodeA.stop()
        playerNodeB.stop()
        engine.stop()
    }
}
