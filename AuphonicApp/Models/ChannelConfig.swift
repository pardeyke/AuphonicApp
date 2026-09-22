import Foundation

/// One Auphonic production for a file. Every selected channel is uploaded as
/// its own mono production: Auphonic's singletrack algorithms are designed
/// for finished mixes and do not process channels independently (confirmed by
/// Auphonic support), so channels must never share an upload.
/// Indices are 1-based.
struct UploadJob: Equatable {
    let channelIndices: [Int]

    /// Short label like "Ch 3"
    var label: String {
        "Ch " + channelIndices.map(String.init).joined(separator: "+")
    }
}

/// Represents one channel in the files of a group
@Observable
final class ChannelEntry: Identifiable {
    let id: Int                          // 0-based channel index
    var enabled: Bool = true
    var displayName: String
    let options: ManualOptionsState      // per-channel settings (used when !linkedSettings)

    init(id: Int, displayName: String) {
        self.id = id
        self.displayName = displayName
        self.options = ManualOptionsState()
    }
}

/// How a group's channels are sent to Auphonic
enum ProductionMode: String, CaseIterable, Identifiable {
    /// One singletrack production per channel
    case singletrack
    /// One multitrack production per file, every channel as its own track
    case multitrack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .singletrack: return "Singletrack"
        case .multitrack: return "Multitrack"
        }
    }
}

/// Per-group channel configuration: which channels are processed and the
/// processing settings.
@Observable
final class ChannelConfig {
    // File properties (set by configure())
    private(set) var fileChannelCount: Int = 0
    private(set) var trackNames: [String] = []

    // Channel state
    var channels: [ChannelEntry] = []

    // Production mode (per group)
    var productionMode: ProductionMode = .singletrack

    // Multitrack: master/mix settings and mixdown handling
    let masterOptions = MultitrackMasterOptions()

    /// Also download the master mixdown (individual tracks are always exported)
    var downloadMixdown: Bool = false

    /// 0-based channel of the original file that the mixdown replaces
    var mixdownTargetChannel: Int?

    // Settings mode
    var linkedSettings: Bool = true     // true = one shared ManualOptionsState for all channels

    // Shared settings (used when linkedSettings == true)
    let sharedOptions = ManualOptionsState()

    // Preset (applies to sharedOptions or all channels when linked)
    var selectedPresetUuid: String = ""
    var presetModified: Bool = false

    // Write the used settings as a JSON sidecar next to each output file
    var writeSettingsXml: Bool = false

    // MARK: - Configuration

    /// Initialize channel entries from file metadata
    func configure(count: Int, trackNames: [String]) {
        self.fileChannelCount = count
        self.trackNames = trackNames

        channels = (0..<count).map { idx in
            let name = channelDisplayName(index: idx, count: count, trackNames: trackNames)
            return ChannelEntry(id: idx, displayName: name)
        }
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

    // MARK: - Upload Jobs

    /// Number of Auphonic productions per file: one per channel in
    /// singletrack mode, exactly one in multitrack mode.
    var apiCallCount: Int {
        switch productionMode {
        case .singletrack:
            return uploadJobs.count
        case .multitrack:
            return uploadJobs.isEmpty ? 0 : 1
        }
    }

    /// One mono upload per enabled channel. In multitrack mode these become
    /// the tracks of a single production.
    var uploadJobs: [UploadJob] {
        channels
            .filter(\.enabled)
            .map { UploadJob(channelIndices: [$0.id + 1]) }
    }

    /// Enabled channels in channel order
    var enabledChannels: [ChannelEntry] {
        channels.filter(\.enabled)
    }

    // MARK: - Multitrack

    /// Stable track id for a channel, used as the multipart field name and to
    /// match the files inside Auphonic's tracks archive.
    func trackId(for channel: ChannelEntry) -> String {
        let name = channel.displayName
            .replacingOccurrences(of: "[^A-Za-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return name.isEmpty ? "ch\(channel.id + 1)" : name
    }

    /// Per-track `algorithms`, keyed by track id
    var multitrackTrackAlgorithms: [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        for channel in enabledChannels {
            let options = linkedSettings ? sharedOptions : channel.options
            result[trackId(for: channel)] = options.getMultitrackTrackSettings()
        }
        return result
    }

    /// `output_files` for a multitrack production: the individual tracks
    /// archive, plus the mono mixdown when requested. `bitDepth` is the
    /// container bit depth of the file being processed.
    func multitrackOutputFiles(bitDepth: Int) -> [[String: Any]] {
        var files: [[String: Any]] = [["format": "tracks", "ending": "wav.zip"]]
        if downloadMixdown {
            files.append([
                "format": Self.forcedWavFormat(bitDepth: bitDepth),
                "mono_mixdown": true
            ])
        }
        return files
    }

    // MARK: - Settings Retrieval

    /// The Auphonic WAV output format used for round-tripping processed
    /// channels. Decided per file: a group only guarantees equal channel
    /// counts, so a 16-bit take can sit next to 24-bit and 32-bit float ones.
    static func forcedWavFormat(bitDepth: Int) -> String {
        bitDepth <= 16 ? "wav-16bit" : "wav-24bit"
    }

    /// Get the effective ManualOptionsState for a given upload job
    func optionsForJob(_ job: UploadJob) -> ManualOptionsState {
        if linkedSettings {
            return sharedOptions
        }
        if let firstIdx = job.channelIndices.first {
            let chIdx = firstIdx - 1  // convert 1-based to 0-based
            if chIdx >= 0 && chIdx < channels.count {
                return channels[chIdx].options
            }
        }
        return sharedOptions
    }

    /// Settings dict for an upload job. Output is always forced to WAV (at the
    /// file's own bit depth) so the processed channels can be written back
    /// into the original container, and the cutters are forced off so the
    /// channel keeps its length even when the selected preset has cutting
    /// enabled.
    func settingsForJob(_ job: UploadJob, bitDepth: Int) -> [String: Any] {
        let opts = optionsForJob(job)
        var settings = opts.getSettings()
        settings["output_files"] = [["format": Self.forcedWavFormat(bitDepth: bitDepth)]]

        var algorithms = (settings["algorithms"] as? [String: Any]) ?? [:]
        CuttingOptions.disableAll(in: &algorithms)
        settings["algorithms"] = algorithms
        return settings
    }

    /// Get preset UUID for an upload job
    func presetUuidForJob(_ job: UploadJob) -> String {
        if linkedSettings {
            return presetModified ? "" : selectedPresetUuid
        }
        // Per-channel mode doesn't use presets currently
        return ""
    }

    /// Whether the current configuration has anything to process. A group
    /// that fails this is skipped by the batch and shows a warning, so a
    /// production that would only bill the 3-minute minimum and change
    /// nothing is never created.
    var hasValidJobConfiguration: Bool {
        guard !uploadJobs.isEmpty else { return false }

        let preset = linkedSettings && !presetModified ? selectedPresetUuid : ""
        let anyTrackAlgorithm = linkedSettings
            ? sharedOptions.hasAnyAlgorithmEnabled()
            : uploadJobs.contains { optionsForJob($0).hasAnyAlgorithmEnabled() }

        switch productionMode {
        case .multitrack:
            // The master algorithms (leveler, gates, crosstalk, loudness)
            // process the exported tracks too, so they count on their own
            return masterOptions.hasAnyEnabled || anyTrackAlgorithm || !preset.isEmpty
        case .singletrack:
            if linkedSettings {
                return !preset.isEmpty || anyTrackAlgorithm
            }
            return uploadJobs.allSatisfy { optionsForJob($0).hasAnyAlgorithmEnabled() }
        }
    }
}
