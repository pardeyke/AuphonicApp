import AVFoundation
import CoreAudio
import AudioToolbox
import Accelerate

@Observable
final class AudioPlayerService {
    enum Slot: String, CaseIterable, Identifiable {
        case original
        case processed

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .original: return "Original"
            case .processed: return "Processed"
            }
        }
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

    // BWF timecode of the loaded original (samples since midnight + fps from iXML)
    private(set) var startTimecodeSamples: UInt64?
    private(set) var timecodeRate: Double?

    // Cached per-channel waveforms (key: channel index, 0=all, 1-N = channel)
    private(set) var waveformCacheA: [Int: [Float]] = [:]
    private(set) var waveformCacheB: [Int: [Float]] = [:]

    // Mixer state per slot: 1-based channel numbers
    private(set) var mutedChannelsA: Set<Int> = []
    private(set) var mutedChannelsB: Set<Int> = []
    private(set) var soloedChannelsA: Set<Int> = []
    private(set) var soloedChannelsB: Set<Int> = []

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
        mutedChannelsA = []
        soloedChannelsA = []
        startTimecodeSamples = nil
        timecodeRate = nil
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
            startTimecodeSamples = WavChunkCopier.readBextTimeReference(from: url)
            timecodeRate = WavChunkCopier.readIxmlTimecodeRate(from: url)
            ensureConnected(slot: .original, sampleRate: file.processingFormat.sampleRate)
            generateAllWaveformsAsync(file: file, slot: .original)
        } catch {
            print("Failed to load original: \(error)")
        }
    }

    func loadProcessed(url: URL) {
        mutedChannelsB = []
        soloedChannelsB = []
        do {
            let file = try AVAudioFile(forReading: url)
            audioFileB = file
            hasProcessed = true
            channelCountB = Int(file.processingFormat.channelCount)
            trackNamesB = WavChunkCopier.readIxmlTrackNames(from: url)
            processedDuration = Double(file.length) / file.processingFormat.sampleRate
            processedWaveform = []
            ensureConnected(slot: .processed, sampleRate: file.processingFormat.sampleRate)
            generateAllWaveformsAsync(file: file, slot: .processed)
        } catch {
            print("Failed to load processed: \(error)")
        }
    }

    /// Connect the slot's player node for the given sample rate. Cheap when the
    /// rate is unchanged (the common case when switching between takes) — the
    /// engine is not stopped or restarted; play() starts it on demand.
    private var connectedRateA: Double = 0
    private var connectedRateB: Double = 0

    private func ensureConnected(slot: Slot, sampleRate: Double) {
        ensureEngineSetup()

        let node = slot == .original ? playerNodeA : playerNodeB
        let connectedRate = slot == .original ? connectedRateA : connectedRateB
        guard connectedRate != sampleRate else { return }

        // Format changes require a stopped engine; it restarts on next play()
        if engine.isRunning { engine.stop() }
        engine.disconnectNodeOutput(node)
        let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.connect(node, to: engine.mainMixerNode, format: stereo)

        if slot == .original {
            connectedRateA = sampleRate
        } else {
            connectedRateB = sampleRate
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
        mutedChannelsB = []
        soloedChannelsB = []
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

        connectedRateA = 0
        connectedRateB = 0
        if let file = audioFileA {
            let stereo = AVAudioFormat(standardFormatWithSampleRate: file.processingFormat.sampleRate, channels: 2)!
            engine.connect(playerNodeA, to: engine.mainMixerNode, format: stereo)
            connectedRateA = file.processingFormat.sampleRate
        }
        if let file = audioFileB {
            let stereo = AVAudioFormat(standardFormatWithSampleRate: file.processingFormat.sampleRate, channels: 2)!
            engine.connect(playerNodeB, to: engine.mainMixerNode, format: stereo)
            connectedRateB = file.processingFormat.sampleRate
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
        let byteCount = frames * MemoryLayout<Float>.size

        // Mix every audible channel (mute/solo aware) down to the stereo bus
        let audible = (1...max(1, srcChannels)).filter {
            $0 <= srcChannels && isChannelAudible(slot: activeSlot, channel: $0)
        }

        // Always a mono sum — these are separate mics, not a stereo image, so
        // monitoring them panned would be misleading.
        if audible.isEmpty {
            // Everything muted — output silence rather than the raw file
            memset(outData[0], 0, byteCount)
            memset(outData[1], 0, byteCount)
        } else if audible.count == 1 {
            let source = srcData[audible[0] - 1]
            memcpy(outData[0], source, byteCount)
            memcpy(outData[1], source, byteCount)
        } else {
            // Sum to the centre, attenuated so a full mix can't clip
            let gain = 1 / Float(audible.count).squareRoot()
            memset(outData[0], 0, byteCount)
            for channel in audible {
                vDSP_vsma(srcData[channel - 1], 1, [gain], outData[0], 1, outData[0], 1, vDSP_Length(frames))
            }
            memcpy(outData[1], outData[0], byteCount)
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

    // MARK: - Channel Mixer (mute / solo, applied without a gap)

    /// A channel is heard when it isn't muted and — if anything is soloed in
    /// its slot — it is one of the soloed channels.
    func isChannelAudible(slot: Slot, channel: Int) -> Bool {
        let muted = slot == .original ? mutedChannelsA : mutedChannelsB
        let soloed = slot == .original ? soloedChannelsA : soloedChannelsB
        if muted.contains(channel) { return false }
        return soloed.isEmpty || soloed.contains(channel)
    }

    func isChannelMuted(slot: Slot, channel: Int) -> Bool {
        (slot == .original ? mutedChannelsA : mutedChannelsB).contains(channel)
    }

    func isChannelSoloed(slot: Slot, channel: Int) -> Bool {
        (slot == .original ? soloedChannelsA : soloedChannelsB).contains(channel)
    }

    func toggleMute(slot: Slot, channel: Int) {
        if slot == .original {
            mutedChannelsA.formSymmetricDifference([channel])
        } else {
            mutedChannelsB.formSymmetricDifference([channel])
        }
        restreamIfPlaying(slot: slot)
    }

    func toggleSolo(slot: Slot, channel: Int) {
        if slot == .original {
            soloedChannelsA.formSymmetricDifference([channel])
        } else {
            soloedChannelsB.formSymmetricDifference([channel])
        }
        restreamIfPlaying(slot: slot)
    }

    func clearMixerState(slot: Slot) {
        if slot == .original {
            mutedChannelsA = []
            soloedChannelsA = []
        } else {
            mutedChannelsB = []
            soloedChannelsB = []
        }
        restreamIfPlaying(slot: slot)
    }

    /// Per-channel peak waveform (1-based; 0 = summed overview)
    func waveform(slot: Slot, channel: Int) -> [Float] {
        (slot == .original ? waveformCacheA : waveformCacheB)[channel] ?? []
    }

    /// Re-schedule the stream from the current position so mixer changes are
    /// heard immediately instead of after the buffered chunks drain.
    private func restreamIfPlaying(slot: Slot) {
        guard slot == activeSlot, isPlaying else { return }
        let position = currentFrame
        stopStreaming()
        activeNode.stop()
        lastSeekFrame = position
        startStreaming(from: position)
        activeNode.play()
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

    /// The device CoreAudio currently routes default output to
    static func systemDefaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    /// Route playback to the device stored in the settings: by name, or the
    /// system default when the name is empty or the device is not connected.
    func applyOutputDevice(named name: String) {
        let device = name.isEmpty ? nil : Self.availableOutputDevices().first { $0.name == name }
        guard let deviceID = device?.id ?? Self.systemDefaultOutputDevice() else { return }
        setOutputDevice(deviceID)
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

    // MARK: - Timecode

    /// Absolute BWF timecode at the current playback position, as
    /// HH:MM:SS:FF when the iXML declares a frame rate, HH:MM:SS otherwise.
    var currentTimecodeString: String? {
        guard let start = startTimecodeSamples, let file = audioFileA else { return nil }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return nil }

        let totalSeconds = Double(start) / sampleRate + currentTime
        let whole = Int(totalSeconds)
        let h = (whole / 3600) % 24
        let m = (whole % 3600) / 60
        let s = whole % 60

        if let rate = timecodeRate, rate > 0 {
            let frames = min(Int(rate.rounded()) - 1, Int((totalSeconds - Double(whole)) * rate))
            return String(format: "%02d:%02d:%02d:%02d", h, m, s, frames)
        }
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    // MARK: - Waveform Generation

    private var waveformGeneration: UInt64 = 0
    /// The background scan for the current generation; cancelled by the next
    private var waveformTask: Task<Void, Never>?

    /// In-memory cache of waveforms keyed by file URL, so switching files is instant.
    private static let waveformCache = WaveformCache()

    /// Reads the file once on a background thread and generates waveforms for all channels + combined.
    private func generateAllWaveformsAsync(file: AVAudioFile, slot: Slot) {
        waveformGeneration += 1
        let gen = waveformGeneration
        let url = file.url
        let resolution = 8192   // high resolution so the view can zoom in

        // Check cache first
        if let cached = Self.waveformCache.waveforms(for: url) {
            if slot == .original {
                waveformCacheA = cached
                originalWaveform = cached[0] ?? []
            } else {
                waveformCacheB = cached
                processedWaveform = cached[0] ?? []
            }
            return
        }

        // The scan runs detached; a newer generation cancels it, and every
        // result hops back to the main actor and is dropped if it is stale.
        waveformTask?.cancel()
        waveformTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = Self.generateAllWaveforms(
                url: url,
                resolution: resolution,
                isCancelled: { Task.isCancelled },
                onPartial: { partial in
                    Task { @MainActor [weak self] in
                        self?.applyWaveforms(partial, isFinal: false, generation: gen, slot: slot, url: url)
                    }
                }
            )
            guard let allWaveforms = result, !Task.isCancelled else { return }
            await self?.applyWaveforms(allWaveforms, isFinal: true, generation: gen, slot: slot, url: url)
        }
    }

    /// Applies a (partial or final) scan result if it is still the current one
    private func applyWaveforms(_ waveforms: [Int: [Float]], isFinal: Bool, generation: UInt64, slot: Slot, url: URL) {
        guard waveformGeneration == generation else { return }

        if isFinal {
            Self.waveformCache.store(waveforms, for: url)
        }

        if slot == .original {
            waveformCacheA = waveforms
            originalWaveform = waveforms[0] ?? []
        } else {
            waveformCacheB = waveforms
            processedWaveform = waveforms[0] ?? []
        }
    }

    /// Reads the file in chunks and computes peak waveforms using vDSP for speed.
    /// Reports the bins filled so far after every chunk via `onPartial`, so the
    /// waveform can render progressively from left to right.
    nonisolated private static func generateAllWaveforms(
        url: URL,
        resolution: Int,
        isCancelled: () -> Bool = { false },
        onPartial: (([Int: [Float]]) -> Void)? = nil
    ) -> [Int: [Float]]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let totalFrames = Int(file.length)
        guard totalFrames > 0 else { return nil }

        let fileChannels = Int(file.processingFormat.channelCount)
        let samplesPerBin = max(1, totalFrames / resolution)

        // Prepare result arrays
        var result: [Int: [Float]] = [:]
        for ch in 0...fileChannels {
            result[ch] = [Float](repeating: 0, count: resolution)
        }

        // Read in chunks to avoid loading entire file into memory
        let chunkFrames = AVAudioFrameCount(min(totalFrames, 1024 * 1024))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunkFrames) else {
            return nil
        }

        file.framePosition = 0
        var framesRead = 0

        while framesRead < totalFrames {
            if isCancelled() { return nil }
            let toRead = min(chunkFrames, AVAudioFrameCount(totalFrames - framesRead))
            do {
                try file.read(into: buffer, frameCount: toRead)
            } catch {
                break
            }

            guard let channelData = buffer.floatChannelData else { break }
            let chunkLen = Int(buffer.frameLength)

            // Process each bin that overlaps with this chunk
            let firstBin = framesRead / samplesPerBin
            let lastBin = min(resolution - 1, (framesRead + chunkLen - 1) / samplesPerBin)

            for bin in firstBin...lastBin {
                let binStart = bin * samplesPerBin
                let binEnd = min(binStart + samplesPerBin, totalFrames)

                // Overlap with current chunk
                let overlapStart = max(binStart, framesRead)
                let overlapEnd = min(binEnd, framesRead + chunkLen)
                guard overlapEnd > overlapStart else { continue }

                let localStart = overlapStart - framesRead
                let count = overlapEnd - overlapStart

                var allMax: Float = result[0]![bin]
                for chIdx in 0..<fileChannels {
                    // Use vDSP to find max absolute value in this range
                    var chMax: Float = 0
                    vDSP_maxmgv(channelData[chIdx].advanced(by: localStart), 1, &chMax, vDSP_Length(count))

                    // Accumulate max across chunks for this bin
                    let prev = result[chIdx + 1]![bin]
                    if chMax > prev { result[chIdx + 1]![bin] = chMax }
                    if chMax > allMax { allMax = chMax }
                }
                result[0]![bin] = allMax
            }

            framesRead += chunkLen

            // Publish progress after each chunk (skip when already complete)
            if framesRead < totalFrames {
                onPartial?(result)
            }
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

    isolated deinit {
        waveformTask?.cancel()
        displayTimer?.invalidate()
        playerNodeA.stop()
        playerNodeB.stop()
        engine.stop()
    }
}
