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
    }

    /// A take on disk, read back as the batch would see it
    private func take(bitDepth: Int = 24, isFloat: Bool = false) throws -> BatchFile {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("standard_mode_\(UUID().uuidString).wav")
        try makeWav(url: url, channels: 2, bitDepth: bitDepth, isFloat: isFloat) { _ in 0.1 }
        return try #require(BatchFile(url: url))
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
    @Test func formatConversionAloneMakesItValid() throws {
        let config = StandardModeConfig()
        config.options.outputFormat = .mp3
        #expect(config.hasValidConfiguration)
        let file = try take()
        defer { try? FileManager.default.removeItem(at: file.url) }
        #expect(config.outputFileExtension(for: file) == "mp3")
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

    /// Auphonic has no "same as input" format and refuses to start a
    /// production without output files ("Can't start the production: it is
    /// already started or you have to provide more data!"), so "Keep Format"
    /// has to name the source's own format per file.
    @Test func keepFormatResolvesToTheSourceFormat() throws {
        let config = StandardModeConfig()
        config.options.levelerEnabled = true

        let file = try take(bitDepth: 24)
        defer { try? FileManager.default.removeItem(at: file.url) }

        let settings = config.productionSettings(for: file)
        let files = settings["output_files"] as? [[String: Any]]
        #expect(files?.count == 1)
        #expect(files?.first?["format"] as? String == "wav-24bit")
        #expect(files?.first?["bitrate"] == nil)
        #expect(config.outputFormat(for: file) == .wav24)
        #expect(config.outputFileExtension(for: file) == "wav")
        #expect(settings["output_format"] == nil)
    }

    @Test func keepFormatFollowsTheSourceBitDepth() throws {
        let config = StandardModeConfig()
        let pcm16 = try take(bitDepth: 16)
        let float32 = try take(bitDepth: 32, isFloat: true)
        defer {
            try? FileManager.default.removeItem(at: pcm16.url)
            try? FileManager.default.removeItem(at: float32.url)
        }
        #expect(config.outputFormat(for: pcm16) == .wav16)
        #expect(config.outputFormat(for: float32) == .wav24)
    }

    /// An explicit format wins over whatever the source is
    @Test func explicitFormatIgnoresTheSource() throws {
        let config = StandardModeConfig()
        config.options.outputFormat = .flac

        let file = try take()
        defer { try? FileManager.default.removeItem(at: file.url) }

        let files = config.productionSettings(for: file)["output_files"] as? [[String: Any]]
        #expect(files?.first?["format"] as? String == "flac")
        #expect(config.outputFormat(for: file) == .flac)
    }

    /// With an unmodified preset its own output files stay authoritative
    @Test func keepFormatWithPresetSendsNoOutputFiles() throws {
        let config = StandardModeConfig()
        config.selectedPresetUuid = "preset-123"

        let file = try take()
        defer { try? FileManager.default.removeItem(at: file.url) }

        #expect(config.productionSettings(for: file)["output_files"] == nil)
        #expect(config.outputFormat(for: file) == nil)
        #expect(config.outputFileExtension(for: file) == nil)

        // Editing the settings drops the preset, so the format is resolved again
        config.presetModified = true
        #expect(config.outputFormat(for: file) == .wav24)
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
