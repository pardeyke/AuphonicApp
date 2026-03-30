import Foundation

/// Describes a single API processing job (mono channel or stereo pair extraction)
struct ProcessingJob {
    /// 1-based channel indices to extract. Empty = whole file as-is.
    let channelIndices: [Int]

    var isStereo: Bool { channelIndices.count == 2 }
    var isMono: Bool { channelIndices.count == 1 }
    var isWholeFile: Bool { channelIndices.isEmpty }
}

/// Represents one channel in the file
@Observable
final class ChannelEntry: Identifiable {
    let id: Int                          // 0-based channel index
    var enabled: Bool = true
    var stereoPairPartner: Int? = nil    // 0-based index of partner (nil = unpaired)
    var displayName: String
    let options: ManualOptionsState      // per-channel settings (used when !linkedSettings)

    init(id: Int, displayName: String) {
        self.id = id
        self.displayName = displayName
        self.options = ManualOptionsState()
    }
}

/// Unified channel configuration that replaces the old perChannelMode + ChannelTabsState
@Observable
final class ChannelConfig {
    // File properties (set by configure())
    private(set) var fileChannelCount: Int = 0
    private(set) var trackNames: [String] = []
    private(set) var bitDepth: Int = 24

    // Channel state
    var channels: [ChannelEntry] = []

    // Stereo mode: true = process 2-ch file as stereo (only meaningful for 2-ch files)
    var stereoMode: Bool = true

    // Settings mode
    var linkedSettings: Bool = true     // true = one shared ManualOptionsState for all channels

    // Merge output
    var mergeOutput: Bool = true        // true = merge processed channels back into multichannel

    // Shared settings (used when linkedSettings == true)
    let sharedOptions = ManualOptionsState()

    // Preset (applies to sharedOptions or all channels when linked)
    var selectedPresetUuid: String = ""
    var presetModified: Bool = false

    // Output behavior (shared across all channels)
    var avoidOverwrite: Bool = true
    var outputSuffix: String = "_auphonic"
    var writeSettingsXml: Bool = false
    var keepTimecode: Bool = false

    // MARK: - Configuration

    /// Initialize channel entries from file metadata
    func configure(count: Int, trackNames: [String], bitDepth: Int) {
        self.fileChannelCount = count
        self.trackNames = trackNames
        self.bitDepth = bitDepth

        channels = (0..<count).map { idx in
            let name = channelDisplayName(index: idx, count: count, trackNames: trackNames)
            let entry = ChannelEntry(id: idx, displayName: name)
            configureChannelOptions(entry.options)
            return entry
        }

        // Default stereoMode based on channel count
        if count == 2 {
            stereoMode = true
        } else {
            stereoMode = false
        }

        // Configure shared options too
        configureChannelOptions(sharedOptions)
    }

    private func configureChannelOptions(_ opts: ManualOptionsState) {
        let wavFormat = bitDepth <= 16 ? "wav-16bit" : "wav-24bit"
        opts.forcedOutputFormat = wavFormat
        opts.outputFormatEnabled = true
        opts.outputFormat = bitDepth <= 16 ? .wav16 : .wav24
    }

    private func channelDisplayName(index: Int, count: Int, trackNames: [String]) -> String {
        let ch = index + 1
        let name: String
        if index < trackNames.count && !trackNames[index].isEmpty {
            name = trackNames[index]
        } else if count == 2 {
            name = index == 0 ? "Left" : "Right"
        } else {
            name = ""
        }
        return name.isEmpty ? "Ch \(ch)" : "Ch \(ch) (\(name))"
    }

    // MARK: - Stereo Pairing

    func linkStereo(ch1: Int, ch2: Int) {
        guard ch1 != ch2,
              ch1 >= 0, ch1 < channels.count,
              ch2 >= 0, ch2 < channels.count else { return }

        // Unlink any existing pairs first
        unlinkStereo(ch: ch1)
        unlinkStereo(ch: ch2)

        channels[ch1].stereoPairPartner = ch2
        channels[ch2].stereoPairPartner = ch1

        // Both must be enabled together
        let enabled = channels[ch1].enabled || channels[ch2].enabled
        channels[ch1].enabled = enabled
        channels[ch2].enabled = enabled
    }

    func unlinkStereo(ch: Int) {
        guard ch >= 0, ch < channels.count,
              let partner = channels[ch].stereoPairPartner else { return }
        channels[ch].stereoPairPartner = nil
        if partner >= 0 && partner < channels.count {
            channels[partner].stereoPairPartner = nil
        }
    }

    // MARK: - Selection

    func selectAll() {
        for ch in channels { ch.enabled = true }
    }

    func deselectAll() {
        for ch in channels { ch.enabled = false }
    }

    var allSelected: Bool {
        channels.allSatisfy(\.enabled)
    }

    var enabledChannelCount: Int {
        channels.filter(\.enabled).count
    }

    // MARK: - Computed Properties

    /// Whether a stereo/multi-mono picker should be shown (only for 2-channel files)
    var showsModeToggle: Bool {
        fileChannelCount == 2
    }

    /// Whether the channel list should be shown
    var showsChannelList: Bool {
        if fileChannelCount <= 1 { return false }
        if fileChannelCount == 2 && stereoMode { return false }
        return true
    }

    /// Whether whole-file processing is used (no channel extraction)
    var isWholeFileMode: Bool {
        if fileChannelCount <= 1 { return true }
        if fileChannelCount == 2 && stereoMode { return true }
        return false
    }

    /// Whether merge output checkbox should be available
    var mergeAvailable: Bool {
        !isWholeFileMode && enabledChannelCount > 1
    }

    /// Number of API calls per file
    var apiCallCount: Int {
        if isWholeFileMode { return 1 }
        return processingJobs.count
    }

    /// Whether WAV output must be forced (needed for merge)
    var requiresWavOutput: Bool {
        !isWholeFileMode && mergeOutput
    }

    /// Build the list of processing jobs from current configuration
    var processingJobs: [ProcessingJob] {
        if isWholeFileMode {
            return [ProcessingJob(channelIndices: [])]
        }

        var jobs: [ProcessingJob] = []
        var visited = Set<Int>()

        for ch in channels where ch.enabled && !visited.contains(ch.id) {
            visited.insert(ch.id)

            if let partner = ch.stereoPairPartner, channels[partner].enabled {
                visited.insert(partner)
                // Stereo pair: lower index first
                let indices = [min(ch.id, partner) + 1, max(ch.id, partner) + 1]
                jobs.append(ProcessingJob(channelIndices: indices))
            } else {
                // Mono extraction
                jobs.append(ProcessingJob(channelIndices: [ch.id + 1]))
            }
        }

        return jobs
    }

    /// Get channels that are linkable as stereo pair for a given channel
    func availableStereoPartners(for channelId: Int) -> [ChannelEntry] {
        channels.filter { ch in
            ch.id != channelId &&
            ch.enabled &&
            ch.stereoPairPartner == nil
        }
    }

    // MARK: - Settings Retrieval

    /// Get the effective ManualOptionsState for a given processing job
    func optionsForJob(_ job: ProcessingJob) -> ManualOptionsState {
        if linkedSettings || job.isWholeFile {
            return sharedOptions
        }
        // For unlinked: use the first channel's options in the job
        if let firstIdx = job.channelIndices.first {
            let chIdx = firstIdx - 1  // convert 1-based to 0-based
            if chIdx >= 0 && chIdx < channels.count {
                return channels[chIdx].options
            }
        }
        return sharedOptions
    }

    /// Get settings dict for a processing job
    func settingsForJob(_ job: ProcessingJob) -> [String: Any] {
        let opts = optionsForJob(job)
        var settings = opts.getSettings()

        // Force WAV output when merge is needed
        if requiresWavOutput {
            let wavFormat = bitDepth <= 16 ? "wav-16bit" : "wav-24bit"
            settings["output_format"] = wavFormat
            settings["output_files"] = [["format": wavFormat]]
        }

        return settings
    }

    /// Get preset UUID for a processing job
    func presetUuidForJob(_ job: ProcessingJob) -> String {
        if linkedSettings || job.isWholeFile {
            return presetModified ? "" : selectedPresetUuid
        }
        // Per-channel mode doesn't use presets currently
        return ""
    }
}
