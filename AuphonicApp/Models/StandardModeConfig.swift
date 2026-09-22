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

    /// Extension of the file Auphonic will return; `keep` mirrors the input,
    /// so the caller has to fall back to the source extension in that case.
    var outputFileExtension: String? {
        outputFormat == .keep ? nil : outputFormat.fileExtension
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
