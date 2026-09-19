import Foundation

/// One Auphonic production for a file: one channel (mono upload) or two
/// channels packed/paired into a stereo upload. Indices are 1-based.
struct UploadJob: Equatable {
    let channelIndices: [Int]

    var isStereo: Bool { channelIndices.count == 2 }
    var isMono: Bool { channelIndices.count == 1 }

    /// Short label like "Ch 3" or "Ch 3+5"
    var label: String {
        "Ch " + channelIndices.map(String.init).joined(separator: "+")
    }
}

/// Represents one channel in the files of a group
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

/// Per-group channel configuration: which channels are processed, how they are
/// paired/packed into Auphonic uploads, and the processing settings.
@Observable
final class ChannelConfig {
    // File properties (set by configure())
    private(set) var fileChannelCount: Int = 0
    private(set) var trackNames: [String] = []
    private(set) var bitDepth: Int = 24

    // Channel state
    var channels: [ChannelEntry] = []

    // Settings mode
    var linkedSettings: Bool = true     // true = one shared ManualOptionsState for all channels

    // Pack unpaired mono channels into stereo uploads. Auphonic bills by file
    // duration regardless of channel count, so this halves the credit cost.
    var packMonoChannels: Bool = true

    // Shared settings (used when linkedSettings == true)
    let sharedOptions = ManualOptionsState()

    // Preset (applies to sharedOptions or all channels when linked)
    var selectedPresetUuid: String = ""
    var presetModified: Bool = false

    // Write the used settings as a JSON sidecar next to each output file
    var writeSettingsXml: Bool = false

    // MARK: - Configuration

    /// Initialize channel entries from file metadata
    func configure(count: Int, trackNames: [String], bitDepth: Int) {
        self.fileChannelCount = count
        self.trackNames = trackNames
        self.bitDepth = bitDepth

        channels = (0..<count).map { idx in
            let name = channelDisplayName(index: idx, count: count, trackNames: trackNames)
            return ChannelEntry(id: idx, displayName: name)
        }

        // 2-channel files default to a genuine stereo pair (L/R processed together)
        if count == 2 {
            linkStereo(ch1: 0, ch2: 1)
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

    // MARK: - Upload Jobs (packing)

    /// Number of Auphonic productions per file
    var apiCallCount: Int {
        uploadJobs.count
    }

    /// Build the upload jobs for one file of this group.
    ///
    /// - User-defined stereo pairs always become one stereo upload.
    /// - Remaining enabled channels are packed two-per-upload when
    ///   `packMonoChannels` is on — but only channels with identical settings
    ///   can share an upload, since a production has a single settings set.
    var uploadJobs: [UploadJob] {
        var jobs: [UploadJob] = []
        var visited = Set<Int>()
        var loose: [ChannelEntry] = []      // enabled, unpaired channels

        for ch in channels where ch.enabled && !visited.contains(ch.id) {
            visited.insert(ch.id)

            if let partner = ch.stereoPairPartner,
               partner < channels.count, channels[partner].enabled {
                visited.insert(partner)
                let indices = [min(ch.id, partner) + 1, max(ch.id, partner) + 1]
                jobs.append(UploadJob(channelIndices: indices))
            } else {
                loose.append(ch)
            }
        }

        if packMonoChannels {
            // Bucket by settings signature: only identical settings may share a production
            var buckets: [String: [ChannelEntry]] = [:]
            var bucketOrder: [String] = []
            for ch in loose {
                let key = linkedSettings ? "linked" : settingsSignature(for: ch)
                if buckets[key] == nil { bucketOrder.append(key) }
                buckets[key, default: []].append(ch)
            }

            for key in bucketOrder {
                let bucket = buckets[key] ?? []
                var i = 0
                while i + 1 < bucket.count {
                    jobs.append(UploadJob(channelIndices: [bucket[i].id + 1, bucket[i + 1].id + 1]))
                    i += 2
                }
                if i < bucket.count {
                    jobs.append(UploadJob(channelIndices: [bucket[i].id + 1]))
                }
            }
        } else {
            for ch in loose {
                jobs.append(UploadJob(channelIndices: [ch.id + 1]))
            }
        }

        return jobs
    }

    /// Canonical serialization of a channel's settings, used to decide which
    /// channels may be packed into the same upload.
    private func settingsSignature(for channel: ChannelEntry) -> String {
        let settings = channel.options.getSettings()
        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "ch\(channel.id)"    // unpackable fallback: unique bucket
        }
        return string
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

    /// The Auphonic WAV output format used for round-tripping processed channels
    var forcedWavFormat: String {
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

    /// Settings dict for an upload job. Output is always forced to WAV so the
    /// processed channels can be written back into the original container.
    func settingsForJob(_ job: UploadJob) -> [String: Any] {
        let opts = optionsForJob(job)
        var settings = opts.getSettings()
        settings["output_format"] = forcedWavFormat
        settings["output_files"] = [["format": forcedWavFormat]]
        settings.removeValue(forKey: "bitrate")
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

    /// Whether the current configuration has anything to process
    var hasValidJobConfiguration: Bool {
        guard !uploadJobs.isEmpty else { return false }
        if linkedSettings {
            let preset = presetModified ? "" : selectedPresetUuid
            return !preset.isEmpty || sharedOptions.hasAnyAlgorithmEnabled()
        }
        return uploadJobs.allSatisfy { optionsForJob($0).hasAnyAlgorithmEnabled() }
    }
}
