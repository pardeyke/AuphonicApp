import Foundation

/// Settings for Standard mode: every file is sent to Auphonic as a whole, one
/// production per file, and comes back in the chosen output format. No channel
/// extraction and no grouping — the counterpart to `ChannelConfig`, which
/// exists for Mix Preparation mode.
@Observable
final class StandardModeConfig {
    /// Algorithms plus the output format/bitrate (`ManualOptionsState` already
    /// emits `output_files` for anything but "keep format")
    let options = ManualOptionsState()

    /// Automatic cutting (silence, fillers, coughs, music) — Standard mode
    /// only, because it changes the length of the audio
    let cutting = CuttingOptions()

    var selectedPresetUuid = ""
    var presetModified = false

    /// Write the settings that produced a file next to it as JSON
    var writeSettingsJson = false

    /// Preset to run the production with; empty once the user edited the
    /// settings, because then the manual settings are authoritative
    var presetUuidForProduction: String {
        presetModified ? "" : selectedPresetUuid
    }

    var productionSettings: [String: Any] {
        var settings = options.getSettings()
        var algorithms = (settings["algorithms"] as? [String: Any]) ?? [:]
        cutting.apply(to: &algorithms)
        settings["algorithms"] = algorithms
        return settings
    }

    var outputFormat: OutputFormat {
        options.outputFormat
    }

    /// Format Auphonic is asked for when processing `file`. Auphonic has no
    /// "same as input" audio format and will not start a production without
    /// `output_files`, so "Keep Format" is resolved from the file's own codec
    /// and bit depth. `nil` when an unmodified preset is in charge: its own
    /// output files stay authoritative then.
    func outputFormat(for file: BatchFile) -> OutputFormat? {
        if outputFormat != .keep { return outputFormat }
        guard presetUuidForProduction.isEmpty else { return nil }
        return OutputFormat.matching(formatID: file.formatID, bitDepth: file.bitDepth, isFloat: file.isFloat)
    }

    /// Request settings for one file: `productionSettings` plus the resolved
    /// output file where "Keep Format" would otherwise send none.
    func productionSettings(for file: BatchFile) -> [String: Any] {
        var settings = productionSettings
        if outputFormat == .keep, let format = outputFormat(for: file) {
            var outputFile: [String: Any] = ["format": format.rawValue]
            if let bitrate = format.bitrate(matchingBytes: file.fileSize, duration: file.duration) {
                outputFile["bitrate"] = "\(bitrate)"
            }
            settings["output_files"] = [outputFile]
        }
        return settings
    }

    /// Extension of the file Auphonic will return for `file`; `nil` when a
    /// preset decides the format, so the caller has to look at what arrived.
    func outputFileExtension(for file: BatchFile) -> String? {
        outputFormat(for: file)?.fileExtension
    }

    /// Whether there is anything worth sending: a preset, at least one enabled
    /// algorithm, a cutter, or a format conversion.
    var hasValidConfiguration: Bool {
        !presetUuidForProduction.isEmpty
            || options.hasAnyAlgorithmEnabled()
            || cutting.isActive
            || outputFormat != .keep
    }
}
