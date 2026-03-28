import Testing
import Foundation
@testable import AuphonicApp

struct ManualOptionsStateTests {

    // MARK: - Default State

    @Test func defaultValues() {
        let opts = ManualOptionsState()
        #expect(!opts.levelerEnabled)
        #expect(!opts.noiseEnabled)
        #expect(!opts.filteringEnabled)
        #expect(!opts.loudnessEnabled)
        #expect(opts.outputFormatEnabled)
        #expect(opts.outputFormat == .keep)
        #expect(opts.avoidOverwrite)
        #expect(opts.outputSuffix == "_auphonic")
        #expect(!opts.keepTimecode)
        #expect(!opts.previewEnabled)
        #expect(opts.previewDuration == 60)
        #expect(opts.selectedChannel == 0)
    }

    // MARK: - hasAnyEnabled

    @Test func hasAnyEnabledDefault() {
        let opts = ManualOptionsState()
        #expect(opts.hasAnyEnabled()) // outputFormatEnabled is true by default
    }

    @Test func hasAnyEnabledAllDisabled() {
        let opts = ManualOptionsState()
        opts.outputFormatEnabled = false
        #expect(!opts.hasAnyEnabled())
    }

    @Test func hasAnyEnabledLeveler() {
        let opts = ManualOptionsState()
        opts.outputFormatEnabled = false
        opts.levelerEnabled = true
        #expect(opts.hasAnyEnabled())
    }

    @Test func hasAnyEnabledNoise() {
        let opts = ManualOptionsState()
        opts.outputFormatEnabled = false
        opts.noiseEnabled = true
        #expect(opts.hasAnyEnabled())
    }

    // MARK: - effectivePreviewDuration

    @Test func effectivePreviewDurationWhenDisabled() {
        let opts = ManualOptionsState()
        opts.previewEnabled = false
        #expect(opts.effectivePreviewDuration == 0)
    }

    @Test func effectivePreviewDurationWhenEnabled() {
        let opts = ManualOptionsState()
        opts.previewEnabled = true
        opts.previewDuration = 30
        opts.fileCount = 1
        #expect(opts.effectivePreviewDuration == 30)
    }

    @Test func effectivePreviewDurationDisabledForMultipleFiles() {
        let opts = ManualOptionsState()
        opts.previewEnabled = true
        opts.previewDuration = 30
        opts.fileCount = 3
        #expect(opts.effectivePreviewDuration == 0)
    }

    @Test func effectivePreviewDurationDisabledForPerChannel() {
        let opts = ManualOptionsState()
        opts.previewEnabled = true
        opts.previewDuration = 30
        opts.fileCount = 1
        opts.isPerChannelMode = true
        #expect(opts.effectivePreviewDuration == 0)
    }

    // MARK: - getSettings (Leveler)

    @Test func getSettingsLevelerDisabled() {
        let opts = ManualOptionsState()
        opts.levelerEnabled = false
        let settings = opts.getSettings()
        let alg = settings["algorithms"] as! [String: Any]
        #expect(alg["leveler"] as? Bool == false)
        #expect(alg["levelerstrength"] as? Int == 0)
        #expect(alg["compressor"] as? String == "off")
    }

    @Test func getSettingsLevelerEnabled() {
        let opts = ManualOptionsState()
        opts.levelerEnabled = true
        opts.levelerStrength = 80
        opts.compressor = 2 // Soft
        let settings = opts.getSettings()
        let alg = settings["algorithms"] as! [String: Any]
        #expect(alg["leveler"] as? Bool == true)
        #expect(alg["levelerstrength"] as? Int == 80)
        #expect(alg["compressor"] as? String == "soft")
    }

    @Test func getSettingsLevelerSeparateMS() {
        let opts = ManualOptionsState()
        opts.levelerEnabled = true
        opts.separateMS = true
        opts.classifier = 2 // Speech
        opts.speechStrength = 90
        opts.musicStrength = 70
        opts.speechCompressor = 3 // Medium
        opts.musicCompressor = 4 // Hard
        opts.musicGain = 3
        let settings = opts.getSettings()
        let alg = settings["algorithms"] as! [String: Any]
        #expect(alg["msclassifier"] as? String == "speech")
        #expect(alg["levelerstrength_speech"] as? Int == 90)
        #expect(alg["levelerstrength_music"] as? Int == 70)
        #expect(alg["compressor_speech"] as? String == "medium")
        #expect(alg["compressor_music"] as? String == "hard")
        #expect(alg["musicgain"] as? Int == 3)
    }

    @Test func getSettingsBroadcastMode() {
        let opts = ManualOptionsState()
        opts.levelerEnabled = true
        opts.broadcastMode = true
        opts.maxLRA = 8
        opts.maxShortTerm = 5
        opts.maxMomentary = 12
        opts.musicGain = -3
        let settings = opts.getSettings()
        let alg = settings["algorithms"] as! [String: Any]
        #expect(alg["maxlra"] as? Int == 8)
        #expect(alg["maxs"] as? Int == 5)
        #expect(alg["maxm"] as? Int == 12)
        #expect(alg["musicgain"] as? Int == -3)
    }

    // MARK: - getSettings (Noise)

    @Test func getSettingsNoiseDisabled() {
        let opts = ManualOptionsState()
        opts.noiseEnabled = false
        let settings = opts.getSettings()
        let alg = settings["algorithms"] as! [String: Any]
        #expect(alg["denoise"] as? Bool == false)
        #expect(alg["denoiseamount"] as? Int == -1)
        #expect(alg["debreathamount"] as? Int == -1)
        #expect(alg["dehumamount"] as? Int == -1)
    }

    @Test func getSettingsNoiseClassic() {
        let opts = ManualOptionsState()
        opts.noiseEnabled = true
        opts.noiseMethod = 1
        opts.noiseAmount = 12
        opts.dehum = 50
        opts.dehumAmount = 6
        let settings = opts.getSettings()
        let alg = settings["algorithms"] as! [String: Any]
        #expect(alg["denoise"] as? Bool == true)
        #expect(alg["denoisemethod"] as? String == "classic")
        #expect(alg["denoiseamount"] as? Int == 12)
        #expect(alg["dehum"] as? Int == 50)
        #expect(alg["dehumamount"] as? Int == 6)
    }

    @Test func getSettingsNoiseDynamic() {
        let opts = ManualOptionsState()
        opts.noiseEnabled = true
        opts.noiseMethod = 2
        opts.reverbAmount = 6
        opts.breathAmount = 12
        let settings = opts.getSettings()
        let alg = settings["algorithms"] as! [String: Any]
        #expect(alg["denoisemethod"] as? String == "dynamic")
        #expect(alg["deverbamount"] as? Int == 6)
        #expect(alg["debreathamount"] as? Int == 12)
        // Classic-only fields should not be present
        #expect(alg["dehum"] == nil)
    }

    @Test func getSettingsNoiseSpeechIsolation() {
        let opts = ManualOptionsState()
        opts.noiseEnabled = true
        opts.noiseMethod = 3
        let settings = opts.getSettings()
        let alg = settings["algorithms"] as! [String: Any]
        #expect(alg["denoisemethod"] as? String == "speech_isolation")
        #expect(alg["deverbamount"] != nil) // method >= 2
        #expect(alg["debreathamount"] != nil) // method 2 or 3
    }

    @Test func getSettingsNoiseStatic() {
        let opts = ManualOptionsState()
        opts.noiseEnabled = true
        opts.noiseMethod = 4
        let settings = opts.getSettings()
        let alg = settings["algorithms"] as! [String: Any]
        #expect(alg["denoisemethod"] as? String == "static")
        #expect(alg["deverbamount"] != nil) // method >= 2
        #expect(alg["debreathamount"] == nil) // only method 2 or 3
    }

    // MARK: - getSettings (Filtering)

    @Test func getSettingsFilteringEnabled() {
        let opts = ManualOptionsState()
        opts.filteringEnabled = true
        opts.filteringMethod = 2 // Auto EQ
        let settings = opts.getSettings()
        let alg = settings["algorithms"] as! [String: Any]
        #expect(alg["filtering"] as? Bool == true)
        #expect(alg["filtermethod"] as? String == "autoeq")
    }

    @Test func getSettingsFilteringBwe() {
        let opts = ManualOptionsState()
        opts.filteringEnabled = true
        opts.filteringMethod = 3
        let settings = opts.getSettings()
        let alg = settings["algorithms"] as! [String: Any]
        #expect(alg["filtermethod"] as? String == "bwe")
    }

    // MARK: - getSettings (Loudness)

    @Test func getSettingsLoudnessEnabled() {
        let opts = ManualOptionsState()
        opts.loudnessEnabled = true
        opts.loudnessTarget = -23
        opts.maxPeak = -1.0
        opts.dualMono = true
        opts.loudnessMethod = 2 // Dialog
        let settings = opts.getSettings()
        let alg = settings["algorithms"] as! [String: Any]
        #expect(alg["normloudness"] as? Bool == true)
        #expect(alg["loudnesstarget"] as? Int == -23)
        #expect(alg["maxpeak"] as? Double == -1.0)
        #expect(alg["dualmono"] as? Bool == true)
        #expect(alg["loudnessmethod"] as? String == "dialog")
    }

    // MARK: - getSettings (Output Format)

    @Test func getSettingsKeepFormat() {
        let opts = ManualOptionsState()
        opts.outputFormat = .keep
        let settings = opts.getSettings()
        // "keep" should omit output_format
        #expect(settings["output_format"] == nil)
        #expect(settings["output_files"] == nil)
    }

    @Test func getSettingsWav24Format() {
        let opts = ManualOptionsState()
        opts.outputFormat = .wav24
        let settings = opts.getSettings()
        #expect(settings["output_format"] as? String == "wav-24bit")
        let outputFiles = settings["output_files"] as? [[String: Any]]
        #expect(outputFiles?.first?["format"] as? String == "wav-24bit")
    }

    @Test func getSettingsMp3FormatWithBitrate() {
        let opts = ManualOptionsState()
        opts.outputFormat = .mp3
        opts.bitrate = 256
        let settings = opts.getSettings()
        #expect(settings["output_format"] as? String == "mp3")
        #expect(settings["bitrate"] as? String == "256")
        let outputFiles = settings["output_files"] as? [[String: Any]]
        #expect(outputFiles?.first?["bitrate"] as? String == "256")
    }

    @Test func getSettingsForcedFormat() {
        let opts = ManualOptionsState()
        opts.forcedOutputFormat = "wav-24bit"
        opts.outputFormat = .mp3 // Should be ignored
        let settings = opts.getSettings()
        #expect(settings["output_format"] as? String == "wav-24bit")
    }

    // MARK: - Widget State Persistence

    @Test func widgetStateRoundTrip() {
        let original = ManualOptionsState()
        original.levelerEnabled = true
        original.levelerStrength = 80
        original.compressor = 3
        original.noiseEnabled = true
        original.noiseMethod = 2
        original.noiseAmount = 12
        original.filteringEnabled = true
        original.filteringMethod = 2
        original.loudnessEnabled = true
        original.loudnessTarget = -23
        original.maxPeak = -1.5
        original.dualMono = true
        original.outputFormat = .mp3
        original.bitrate = 192
        original.avoidOverwrite = false
        original.outputSuffix = "_processed"
        original.keepTimecode = true
        original.previewEnabled = true
        original.previewDuration = 180

        let state = original.getWidgetState()

        let restored = ManualOptionsState()
        restored.applyWidgetState(state)

        #expect(restored.levelerEnabled == true)
        #expect(restored.levelerStrength == 80)
        #expect(restored.compressor == 3)
        #expect(restored.noiseEnabled == true)
        #expect(restored.noiseMethod == 2)
        #expect(restored.noiseAmount == 12)
        #expect(restored.filteringEnabled == true)
        #expect(restored.filteringMethod == 2)
        #expect(restored.loudnessEnabled == true)
        #expect(restored.loudnessTarget == -23)
        #expect(restored.maxPeak == -1.5)
        #expect(restored.dualMono == true)
        #expect(restored.outputFormat == .mp3)
        #expect(restored.bitrate == 192)
        #expect(restored.avoidOverwrite == false)
        #expect(restored.outputSuffix == "_processed")
        #expect(restored.keepTimecode == true)
        #expect(restored.previewEnabled == true)
        #expect(restored.previewDuration == 180)
    }

    @Test func applyWidgetStateWithMissingKeys() {
        let opts = ManualOptionsState()
        opts.applyWidgetState([:]) // Empty state should use defaults
        #expect(!opts.levelerEnabled)
        #expect(opts.levelerStrength == 100)
        #expect(opts.compressor == 1)
        #expect(opts.outputFormat == .keep)
        #expect(opts.avoidOverwrite == true)
        #expect(opts.breathAmount == -1)
    }

    // MARK: - applyApiSettings

    @Test func applyApiSettingsLeveler() {
        let opts = ManualOptionsState()
        opts.applyApiSettings([
            "leveler": true,
            "levelerstrength": 80,
            "compressor": "soft"
        ])
        #expect(opts.levelerEnabled)
        #expect(opts.levelerStrength == 80)
        #expect(opts.compressor == 2)
        #expect(!opts.separateMS)
    }

    @Test func applyApiSettingsLevelerDisabled() {
        let opts = ManualOptionsState()
        opts.levelerEnabled = true
        opts.applyApiSettings(["leveler": false])
        #expect(!opts.levelerEnabled)
    }

    @Test func applyApiSettingsSeparateMS() {
        let opts = ManualOptionsState()
        opts.applyApiSettings([
            "leveler": true,
            "msclassifier": "speech",
            "levelerstrength_speech": 90,
            "levelerstrength_music": 70,
            "compressor_speech": "medium",
            "compressor_music": "hard",
            "musicgain": 3
        ])
        #expect(opts.separateMS)
        #expect(opts.classifier == 2) // speech
        #expect(opts.speechStrength == 90)
        #expect(opts.musicStrength == 70)
        #expect(opts.speechCompressor == 3) // medium
        #expect(opts.musicCompressor == 4) // hard
        #expect(opts.musicGain == 3)
    }

    @Test func applyApiSettingsBroadcastMode() {
        let opts = ManualOptionsState()
        opts.applyApiSettings([
            "leveler": true,
            "maxlra": 8,
            "maxs": 5,
            "maxm": 12
        ])
        #expect(opts.broadcastMode)
        #expect(opts.maxLRA == 8)
        #expect(opts.maxShortTerm == 5)
        #expect(opts.maxMomentary == 12)
    }

    @Test func applyApiSettingsNoise() {
        let opts = ManualOptionsState()
        opts.applyApiSettings([
            "denoise": true,
            "denoisemethod": "dynamic",
            "denoiseamount": 12,
            "deverbamount": 6,
            "debreathamount": 9
        ])
        #expect(opts.noiseEnabled)
        #expect(opts.noiseMethod == 2)
        #expect(opts.noiseAmount == 12)
        #expect(opts.reverbAmount == 6)
        #expect(opts.breathAmount == 9)
    }

    @Test func applyApiSettingsFiltering() {
        let opts = ManualOptionsState()
        opts.applyApiSettings([
            "filtering": true,
            "filtermethod": "autoeq"
        ])
        #expect(opts.filteringEnabled)
        #expect(opts.filteringMethod == 2)
    }

    @Test func applyApiSettingsLoudness() {
        let opts = ManualOptionsState()
        opts.applyApiSettings([
            "normloudness": true,
            "loudnesstarget": -23,
            "maxpeak": -1.5,
            "dualmono": true,
            "loudnessmethod": "dialog"
        ])
        #expect(opts.loudnessEnabled)
        #expect(opts.loudnessTarget == -23)
        #expect(opts.maxPeak == -1.5)
        #expect(opts.dualMono)
        #expect(opts.loudnessMethod == 2)
    }

    @Test func applyApiSettingsLoudnessTargetAsDouble() {
        let opts = ManualOptionsState()
        opts.applyApiSettings([
            "normloudness": true,
            "loudnesstarget": -16.0  // Double from API
        ])
        #expect(opts.loudnessTarget == -16)
    }

    // MARK: - Settings Round Trip

    @Test func settingsRoundTripViaApi() {
        let original = ManualOptionsState()
        original.levelerEnabled = true
        original.levelerStrength = 90
        original.compressor = 2
        original.noiseEnabled = true
        original.noiseMethod = 1
        original.noiseAmount = 6
        original.dehum = 50
        original.dehumAmount = 9
        original.filteringEnabled = true
        original.filteringMethod = 1
        original.loudnessEnabled = true
        original.loudnessTarget = -16
        original.loudnessMethod = 1

        let settings = original.getSettings()
        let algorithms = settings["algorithms"] as! [String: Any]

        let restored = ManualOptionsState()
        restored.applyApiSettings(algorithms)

        #expect(restored.levelerEnabled == original.levelerEnabled)
        #expect(restored.levelerStrength == original.levelerStrength)
        #expect(restored.compressor == original.compressor)
        #expect(restored.noiseEnabled == original.noiseEnabled)
        #expect(restored.noiseMethod == original.noiseMethod)
        #expect(restored.noiseAmount == original.noiseAmount)
        #expect(restored.dehum == original.dehum)
        #expect(restored.dehumAmount == original.dehumAmount)
        #expect(restored.filteringEnabled == original.filteringEnabled)
        #expect(restored.filteringMethod == original.filteringMethod)
        #expect(restored.loudnessEnabled == original.loudnessEnabled)
        #expect(restored.loudnessTarget == original.loudnessTarget)
        #expect(restored.loudnessMethod == original.loudnessMethod)
    }
}
