import Testing
import Foundation
import UniformTypeIdentifiers
@testable import AuphonicApp

// MARK: - Config

struct StandardModeConfigTests {

    @Test func defaultsToKeepFormatAndNoPreset() {
        let config = StandardModeConfig()
        #expect(config.outputFormat == .keep)
        #expect(config.presetUuidForProduction.isEmpty)
        #expect(config.outputFileExtension == nil)
    }

    /// Nothing enabled, no preset, no conversion — nothing worth billing
    @Test func emptyConfigurationIsNotValid() {
        #expect(StandardModeConfig().hasValidConfiguration == false)
    }

    @Test func anAlgorithmMakesItValid() {
        let config = StandardModeConfig()
        config.options.levelerEnabled = true
        #expect(config.hasValidConfiguration)
    }

    /// A pure format conversion is a legitimate production on its own
    @Test func formatConversionAloneMakesItValid() {
        let config = StandardModeConfig()
        config.options.outputFormat = .mp3
        #expect(config.hasValidConfiguration)
        #expect(config.outputFileExtension == "mp3")
    }

    @Test func presetAloneMakesItValid() {
        let config = StandardModeConfig()
        config.selectedPresetUuid = "abc123"
        #expect(config.hasValidConfiguration)
        #expect(config.presetUuidForProduction == "abc123")
    }

    /// Editing the settings takes precedence over the preset
    @Test func editingSettingsDropsThePreset() {
        let config = StandardModeConfig()
        config.selectedPresetUuid = "abc123"
        config.presetModified = true
        #expect(config.presetUuidForProduction.isEmpty)
    }

    @Test func settingsCarryFormatAndBitrate() {
        let config = StandardModeConfig()
        config.options.outputFormat = .mp3
        config.options.bitrate = 192

        let settings = config.productionSettings
        #expect(settings["output_format"] == nil)
        #expect(settings["bitrate"] == nil)

        let files = settings["output_files"] as? [[String: Any]]
        #expect(files?.count == 1)
        #expect(files?.first?["format"] as? String == "mp3")
        #expect(files?.first?["bitrate"] as? String == "192")
    }

    /// "Keep format" must not send output_files, so Auphonic mirrors the input
    @Test func keepFormatSendsNoOutputFiles() {
        let config = StandardModeConfig()
        config.options.levelerEnabled = true

        let settings = config.productionSettings
        #expect(settings["output_files"] == nil)
        #expect(settings["output_format"] == nil)
    }

    /// Cutting is merged into the same algorithms object
    @Test func cuttingReachesTheProductionSettings() {
        let config = StandardModeConfig()
        config.options.levelerEnabled = true
        config.cutting.enabled = true
        config.cutting.cutFillers = true

        let algorithms = config.productionSettings["algorithms"] as? [String: Any]
        #expect(algorithms?["leveler"] as? Bool == true)
        #expect(algorithms?["filler_cutter"] as? Bool == true)
        #expect(algorithms?["cut_mode"] as? String == "apply_cuts")
    }

    /// A cutter on its own is reason enough to run a production
    @Test func cuttingAloneMakesItValid() {
        let config = StandardModeConfig()
        #expect(config.hasValidConfiguration == false)
        config.cutting.enabled = true
        config.cutting.cutSilence = true
        #expect(config.hasValidConfiguration)
    }

    /// Unlike Mix Preparation, Standard mode never forces WAV
    @Test func algorithmsArePassedThrough() {
        let config = StandardModeConfig()
        config.options.levelerEnabled = true
        config.options.noiseEnabled = true

        let algorithms = config.productionSettings["algorithms"] as? [String: Any]
        #expect(algorithms?["leveler"] as? Bool == true)
        #expect(algorithms?["denoise"] as? Bool == true)
    }
}

// MARK: - Automatic Cutting

struct CuttingOptionsTests {

    @Test func defaultsToInactive() {
        let cutting = CuttingOptions()
        #expect(cutting.isActive == false)
        #expect(cutting.cutMode == .applyCuts)
        #expect(cutting.fadeTime == 100)
    }

    /// The master switch alone cuts nothing
    @Test func enabledWithoutACutterIsInactive() {
        let cutting = CuttingOptions()
        cutting.enabled = true
        #expect(cutting.isActive == false)
    }

    @Test func cutterWithoutTheMasterSwitchIsInactive() {
        let cutting = CuttingOptions()
        cutting.cutSilence = true
        #expect(cutting.isActive == false)
    }

    /// Nothing is written while inactive, so a preset's cutting survives
    @Test func inactiveWritesNoKeys() {
        var algorithms: [String: Any] = ["leveler": true]
        CuttingOptions().apply(to: &algorithms)
        #expect(algorithms.count == 1)
        #expect(algorithms["silence_cutter"] == nil)
        #expect(algorithms["cut_mode"] == nil)
    }

    @Test func activeWritesEveryCuttingKey() {
        let cutting = CuttingOptions()
        cutting.enabled = true
        cutting.cutSilence = true
        cutting.cutFillers = true
        cutting.cutMode = .setCutsToSilence
        cutting.fadeTime = 250

        var algorithms: [String: Any] = [:]
        cutting.apply(to: &algorithms)

        #expect(algorithms["silence_cutter"] as? Bool == true)
        #expect(algorithms["filler_cutter"] as? Bool == true)
        #expect(algorithms["cough_cutter"] as? Bool == false)
        #expect(algorithms["music_cutter"] as? Bool == false)
        #expect(algorithms["cut_mode"] as? String == "set_cuts_to_silence")
        #expect(algorithms["fadetime"] as? Int == 250)
    }

    /// Raw values are the API's enum — they must match the spec exactly
    @Test func cutModeRawValues() {
        #expect(CutMode.applyCuts.rawValue == "apply_cuts")
        #expect(CutMode.setCutsToSilence.rawValue == "set_cuts_to_silence")
        #expect(CutMode.exportUncutAudio.rawValue == "export_uncut_audio")
    }

    @Test func restoresFromApiSettings() {
        let cutting = CuttingOptions()
        cutting.applyApiSettings([
            "silence_cutter": true,
            "music_cutter": true,
            "cut_mode": "export_uncut_audio",
            "fadetime": 500
        ])
        #expect(cutting.enabled)
        #expect(cutting.isActive)
        #expect(cutting.cutSilence)
        #expect(cutting.cutMusic)
        #expect(cutting.cutFillers == false)
        #expect(cutting.cutMode == .exportUncutAudio)
        #expect(cutting.fadeTime == 500)
    }

    @Test func settingsWithoutCuttingSwitchItOff() {
        let cutting = CuttingOptions()
        cutting.enabled = true
        cutting.cutSilence = true
        cutting.applyApiSettings(["leveler": true])
        #expect(cutting.enabled == false)
        #expect(cutting.cutSilence == false)
    }
}

// MARK: - Mode

struct AppModeTests {

    @Test func everyModeHasDistinctNames() {
        let names = Set(AppMode.allCases.map(\.displayName))
        #expect(names.count == AppMode.allCases.count)
        #expect(AppMode.allCases.allSatisfy { !$0.summary.isEmpty })
    }

    /// Raw values are persisted in UserDefaults — renaming them silently
    /// resets everyone's saved mode
    @Test func rawValuesAreStable() {
        #expect(AppMode.standard.rawValue == "standard")
        #expect(AppMode.mixPreparation.rawValue == "mixPreparation")
        #expect(AppMode(rawValue: "nonsense") == nil)
    }
}

// MARK: - Output Naming

struct StandardModeOutputNamingTests {

    @Test func usesTheRequestedExtension() throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("auphonic_api_out_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let original = URL(fileURLWithPath: "/takes/Interview.aiff")
        let output = BatchWorkflow.resolveOutputURL(
            for: original,
            destination: destination,
            preferredExtension: "mp3"
        )
        #expect(output.lastPathComponent == "Interview.mp3")
    }

    /// Without a preferred extension the source extension is kept (Mix
    /// Preparation writes the same container it read)
    @Test func keepsSourceExtensionByDefault() throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("auphonic_api_out_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let output = BatchWorkflow.resolveOutputURL(
            for: URL(fileURLWithPath: "/takes/MixPre-001.wav"),
            destination: destination
        )
        #expect(output.lastPathComponent == "MixPre-001.wav")
    }

    @Test func existingFileGetsACounter() throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("auphonic_api_out_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        try Data([1]).write(to: destination.appendingPathComponent("Interview.flac"))

        let output = BatchWorkflow.resolveOutputURL(
            for: URL(fileURLWithPath: "/takes/Interview.wav"),
            destination: destination,
            preferredExtension: "flac"
        )
        #expect(output.lastPathComponent == "Interview_2.flac")
    }

    /// A source without an extension must not produce a trailing dot
    @Test func extensionlessSourceStaysExtensionless() throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("auphonic_api_out_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let output = BatchWorkflow.resolveOutputURL(
            for: URL(fileURLWithPath: "/takes/RECORDING"),
            destination: destination
        )
        #expect(output.lastPathComponent == "RECORDING")
    }
}

// MARK: - Accepted Input

struct AudioFileTypesTests {

    @Test func acceptsEverythingCoreAudioDecodes() {
        let accepted = ["take.wav", "take.WAV", "take.bwf", "take.aif", "take.aiff",
                        "take.caf", "take.mp3", "take.m4a", "take.aac", "take.flac"]
        for name in accepted {
            #expect(AudioFileTypes.isAudioFile(URL(fileURLWithPath: "/tmp/\(name)")), "\(name) should be accepted")
        }
    }

    @Test func rejectsNonAudio() {
        for name in ["notes.txt", "sheet.pdf", "art.png", "clip.mov", "archive.zip"] {
            #expect(AudioFileTypes.isAudioFile(URL(fileURLWithPath: "/tmp/\(name)")) == false, "\(name) should be rejected")
        }
    }

    /// Mix Preparation patches the RIFF data chunk of a copy of the original,
    /// which only exists in WAV containers
    @Test func mixPreparationTakesWavOnly() {
        for name in ["take.wav", "take.WAV", "take.wave", "take.bwf"] {
            #expect(AudioFileTypes.isAudioFile(URL(fileURLWithPath: "/tmp/\(name)"), mode: .mixPreparation),
                    "\(name) should be accepted")
        }
        for name in ["take.aif", "take.aiff", "take.caf", "take.mp3", "take.m4a", "take.flac"] {
            #expect(AudioFileTypes.isAudioFile(URL(fileURLWithPath: "/tmp/\(name)"), mode: .mixPreparation) == false,
                    "\(name) should be rejected in Mix Preparation")
        }
    }

    @Test func openPanelTypesFollowTheMode() {
        #expect(AudioFileTypes.openPanelTypes(for: .standard).contains(.audio))
        #expect(AudioFileTypes.openPanelTypes(for: .mixPreparation).contains(.wav))
        #expect(AudioFileTypes.openPanelTypes(for: .mixPreparation).contains(.audio) == false)
        // Folders must stay selectable in both modes
        #expect(AppMode.allCases.allSatisfy { AudioFileTypes.openPanelTypes(for: $0).contains(.folder) })
    }
}
