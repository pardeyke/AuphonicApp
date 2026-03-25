import SwiftUI

@Observable
final class ManualOptionsState {
    // Leveler
    var levelerEnabled = false
    var levelerStrength = 100       // 100, 90, 80, ..., 0
    var compressor = 1              // 1=Auto, 2=Soft, 3=Medium, 4=Hard, 5=Off
    var separateMS = false
    var classifier = 1              // 1=On, 2=Speech, 3=Music
    var speechStrength = 100
    var speechCompressor = 1
    var musicStrength = 100
    var musicCompressor = 0              // 0=Same, 1=Auto, 2=Soft, 3=Medium, 4=Hard, 5=Off
    var musicGain = 0               // -6 to +6
    var broadcastMode = false
    var maxLRA = 0                  // 0=Auto, 3-20
    var maxShortTerm = 0
    var maxMomentary = 0

    // Noise Reduction
    var noiseEnabled = false
    var noiseMethod = 1             // 1=Classic, 2=Dynamic, 3=Speech Isolation, 4=Static
    var noiseAmount = 0             // classic: 0=Auto, -1=Off; others: 0=Full, -1=Off
    var reverbAmount = 0            // 0=Full, -1=Off
    var breathAmount = -1           // -1=Off
    var dehum = 0                   // 0=Auto, 50, 60 Hz (classic only)
    var dehumAmount = 0             // 0=Auto, -1=Off

    // Filtering
    var filteringEnabled = false
    var filteringMethod = 1         // 1=High-Pass, 2=Auto EQ, 3=Bandwidth Extension

    // Loudness
    var loudnessEnabled = false
    var loudnessTarget = -16        // LUFS
    var maxPeak: Double = 0         // 0=Auto, dBTP values
    var dualMono = false
    var loudnessMethod = 1          // 1=Program, 2=Dialog, 3=RMS

    // Output Format
    var outputFormatEnabled = true
    var outputFormat: OutputFormat = .keep
    var bitrate = 112

    // Channel Selection
    var selectedChannel = 0         // 0=all, -1=L+R, 1-N=single
    var channelCount = 0
    var trackNames: [String] = []

    // Output Behavior
    var avoidOverwrite = true
    var outputSuffix = "_auphonic"
    var writeSettingsXml = false
    var keepTimecode = false

    // Preview
    var previewEnabled = false
    var previewDuration: Double = 60    // seconds
    var fileDuration: Double = 0        // seconds, set from outside
    var fileCount: Int = 1              // set from outside

    // Per-channel mode
    var isPerChannelMode = false
    var forcedOutputFormat: String?

    /// Effective preview duration for processing (0 = full)
    var effectivePreviewDuration: Double {
        guard previewEnabled, fileCount <= 1, !isPerChannelMode else { return 0 }
        return previewDuration
    }

    func getSettings() -> [String: Any] {
        var settings: [String: Any] = [:]
        var algorithms: [String: Any] = [:]

        if levelerEnabled {
            algorithms["leveler"] = true

            let compressorValues = ["auto", "soft", "medium", "hard", "off"]

            if separateMS {
                let classifierValues = ["on", "speech", "music"]
                algorithms["msclassifier"] = classifierValues[classifier - 1]
                algorithms["levelerstrength_speech"] = speechStrength
                algorithms["levelerstrength_music"] = musicStrength
                algorithms["compressor_speech"] = compressorValues[speechCompressor - 1]
                let musicCompressorValues = ["same", "auto", "soft", "medium", "hard", "off"]
                algorithms["compressor_music"] = musicCompressorValues[musicCompressor]
                algorithms["musicgain"] = musicGain
            } else {
                algorithms["levelerstrength"] = levelerStrength
                algorithms["compressor"] = compressorValues[compressor - 1]
            }

            if broadcastMode {
                algorithms["maxlra"] = maxLRA
                algorithms["maxs"] = maxShortTerm
                algorithms["maxm"] = maxMomentary
                if !separateMS {
                    algorithms["musicgain"] = musicGain
                }
            }
        } else {
            algorithms["leveler"] = false
            algorithms["levelerstrength"] = 0
            algorithms["compressor"] = "off"
        }

        if noiseEnabled {
            algorithms["denoise"] = true
            let methods = ["classic", "dynamic", "speech_isolation", "static"]
            algorithms["denoisemethod"] = methods[noiseMethod - 1]
            algorithms["denoiseamount"] = noiseAmount
            if noiseMethod == 1 {
                algorithms["dehum"] = dehum
                algorithms["dehumamount"] = dehumAmount
            }
            if noiseMethod >= 2 {
                algorithms["deverbamount"] = reverbAmount
            }
            if noiseMethod == 2 || noiseMethod == 3 {
                algorithms["debreathamount"] = breathAmount
            }
        } else {
            algorithms["denoise"] = false
            algorithms["denoiseamount"] = -1
            algorithms["debreathamount"] = -1
            algorithms["dehumamount"] = -1
        }

        if filteringEnabled {
            algorithms["filtering"] = true
            let methods = ["hipfilter", "autoeq", "bwe"]
            algorithms["filtermethod"] = methods[filteringMethod - 1]
        } else {
            algorithms["filtering"] = false
        }

        if loudnessEnabled {
            algorithms["normloudness"] = true
            algorithms["loudnesstarget"] = loudnessTarget
            algorithms["maxpeak"] = maxPeak
            algorithms["dualmono"] = dualMono
            let loudnessMethods = ["program", "dialog", "rms"]
            algorithms["loudnessmethod"] = loudnessMethods[loudnessMethod - 1]
        } else {
            algorithms["normloudness"] = false
        }

        settings["algorithms"] = algorithms

        // Output format
        if let forced = forcedOutputFormat {
            settings["output_format"] = forced
            settings["output_files"] = [["format": forced]]
        } else if outputFormat != .keep {
            settings["output_format"] = outputFormat.rawValue
            var outputFile: [String: Any] = ["format": outputFormat.rawValue]
            if outputFormat.hasBitrate {
                settings["bitrate"] = "\(bitrate)"
                outputFile["bitrate"] = "\(bitrate)"
            }
            settings["output_files"] = [outputFile]
        }
        // When format is .keep, omit output_format/output_files so API keeps input format

        return settings
    }

    func hasAnyEnabled() -> Bool {
        levelerEnabled || noiseEnabled || filteringEnabled || loudnessEnabled || outputFormatEnabled
    }

    // MARK: - Widget State Persistence

    func getWidgetState() -> [String: Any] {
        [
            "levelerEnabled": levelerEnabled,
            "levelerStrength": levelerStrength,
            "compressor": compressor,
            "separateMS": separateMS,
            "classifier": classifier,
            "speechStrength": speechStrength,
            "speechCompressor": speechCompressor,
            "musicStrength": musicStrength,
            "musicCompressor": musicCompressor,
            "musicGain": musicGain,
            "broadcastMode": broadcastMode,
            "maxLRA": maxLRA,
            "maxShortTerm": maxShortTerm,
            "maxMomentary": maxMomentary,
            "noiseEnabled": noiseEnabled,
            "noiseMethod": noiseMethod,
            "noiseAmount": noiseAmount,
            "reverbAmount": reverbAmount,
            "breathAmount": breathAmount,
            "dehum": dehum,
            "dehumAmount": dehumAmount,
            "filteringEnabled": filteringEnabled,
            "filteringMethod": filteringMethod,
            "loudnessEnabled": loudnessEnabled,
            "loudnessTarget": loudnessTarget,
            "maxPeak": maxPeak,
            "dualMono": dualMono,
            "loudnessMethod": loudnessMethod,
            "outputFormatEnabled": outputFormatEnabled,
            "outputFormat": outputFormat.rawValue,
            "bitrate": bitrate,
            "avoidOverwrite": avoidOverwrite,
            "outputSuffix": outputSuffix,
            "writeSettingsXml": writeSettingsXml,
            "keepTimecode": keepTimecode,
            "selectedChannel": selectedChannel,
            "previewEnabled": previewEnabled,
            "previewDuration": previewDuration,
        ]
    }

    func applyWidgetState(_ state: [String: Any]) {
        levelerEnabled = (state["levelerEnabled"] as? Bool) ?? false
        levelerStrength = (state["levelerStrength"] as? Int) ?? 100
        compressor = (state["compressor"] as? Int) ?? 1
        separateMS = (state["separateMS"] as? Bool) ?? false
        classifier = (state["classifier"] as? Int) ?? 1
        speechStrength = (state["speechStrength"] as? Int) ?? 100
        speechCompressor = (state["speechCompressor"] as? Int) ?? 1
        musicStrength = (state["musicStrength"] as? Int) ?? 100
        musicCompressor = (state["musicCompressor"] as? Int) ?? 0
        musicGain = (state["musicGain"] as? Int) ?? 0
        broadcastMode = (state["broadcastMode"] as? Bool) ?? false
        maxLRA = (state["maxLRA"] as? Int) ?? 0
        maxShortTerm = (state["maxShortTerm"] as? Int) ?? 0
        maxMomentary = (state["maxMomentary"] as? Int) ?? 0
        noiseEnabled = (state["noiseEnabled"] as? Bool) ?? false
        noiseMethod = (state["noiseMethod"] as? Int) ?? 1
        noiseAmount = (state["noiseAmount"] as? Int) ?? 0
        reverbAmount = (state["reverbAmount"] as? Int) ?? 0
        breathAmount = (state["breathAmount"] as? Int) ?? -1
        dehum = (state["dehum"] as? Int) ?? 0
        dehumAmount = (state["dehumAmount"] as? Int) ?? 0
        filteringEnabled = (state["filteringEnabled"] as? Bool) ?? false
        filteringMethod = (state["filteringMethod"] as? Int) ?? 1
        loudnessEnabled = (state["loudnessEnabled"] as? Bool) ?? false
        loudnessTarget = (state["loudnessTarget"] as? Int) ?? -16
        maxPeak = (state["maxPeak"] as? Double) ?? 0
        dualMono = (state["dualMono"] as? Bool) ?? false
        loudnessMethod = (state["loudnessMethod"] as? Int) ?? 1
        outputFormatEnabled = (state["outputFormatEnabled"] as? Bool) ?? true
        if let fmt = state["outputFormat"] as? String { outputFormat = OutputFormat(rawValue: fmt) ?? .keep }
        bitrate = (state["bitrate"] as? Int) ?? 112
        avoidOverwrite = (state["avoidOverwrite"] as? Bool) ?? true
        outputSuffix = (state["outputSuffix"] as? String) ?? "_auphonic"
        writeSettingsXml = (state["writeSettingsXml"] as? Bool) ?? false
        keepTimecode = (state["keepTimecode"] as? Bool) ?? false
        selectedChannel = (state["selectedChannel"] as? Int) ?? 0
        previewEnabled = (state["previewEnabled"] as? Bool) ?? false
        previewDuration = (state["previewDuration"] as? Double) ?? 60
    }

    func applyApiSettings(_ algorithms: [String: Any]) {
        // Leveler
        if let leveler = algorithms["leveler"] as? Bool, leveler {
            levelerEnabled = true
            if let str = algorithms["levelerstrength"] as? Int { levelerStrength = str }
            if let comp = algorithms["compressor"] as? String {
                let values = ["auto": 1, "soft": 2, "medium": 3, "hard": 4, "off": 5]
                compressor = values[comp] ?? 1
            }

            // Separate Music/Speech
            if let cls = algorithms["msclassifier"] as? String {
                separateMS = true
                let classifierValues = ["on": 1, "speech": 2, "music": 3]
                classifier = classifierValues[cls] ?? 1
                if let v = algorithms["levelerstrength_speech"] as? Int { speechStrength = v }
                if let v = algorithms["levelerstrength_music"] as? Int { musicStrength = v }
                if let c = algorithms["compressor_speech"] as? String {
                    let values = ["auto": 1, "soft": 2, "medium": 3, "hard": 4, "off": 5]
                    speechCompressor = values[c] ?? 1
                }
                if let c = algorithms["compressor_music"] as? String {
                    let values = ["same": 0, "auto": 1, "soft": 2, "medium": 3, "hard": 4, "off": 5]
                    musicCompressor = values[c] ?? 0
                }
            } else {
                separateMS = false
            }

            if let mg = algorithms["musicgain"] as? Int { musicGain = mg }

            // Broadcast mode
            let hasBroadcast = algorithms["maxlra"] != nil || algorithms["maxs"] != nil || algorithms["maxm"] != nil
            broadcastMode = hasBroadcast
            if hasBroadcast {
                if let v = algorithms["maxlra"] as? Int { maxLRA = v }
                if let v = algorithms["maxs"] as? Int { maxShortTerm = v }
                if let v = algorithms["maxm"] as? Int { maxMomentary = v }
            }
        } else {
            levelerEnabled = false
        }

        // Noise
        if let denoise = algorithms["denoise"] as? Bool, denoise {
            noiseEnabled = true
            if let method = algorithms["denoisemethod"] as? String {
                let methods = ["classic": 1, "dynamic": 2, "speech_isolation": 3, "static": 4]
                noiseMethod = methods[method] ?? 1
            }
            if let amount = algorithms["denoiseamount"] as? Int { noiseAmount = amount }
            if let amount = algorithms["deverbamount"] as? Int { reverbAmount = amount }
            if let amount = algorithms["debreathamount"] as? Int { breathAmount = amount }
            if let d = algorithms["dehum"] as? Int { dehum = d }
            if let d = algorithms["dehumamount"] as? Int { dehumAmount = d }
        } else {
            noiseEnabled = false
        }

        // Filtering
        if let filtering = algorithms["filtering"] as? Bool, filtering {
            filteringEnabled = true
            if let method = algorithms["filtermethod"] as? String {
                let methods = ["hipfilter": 1, "autoeq": 2, "bwe": 3]
                filteringMethod = methods[method] ?? 1
            }
        } else {
            filteringEnabled = false
        }

        // Loudness
        if let loud = algorithms["normloudness"] as? Bool, loud {
            loudnessEnabled = true
            if let target = algorithms["loudnesstarget"] as? Double {
                loudnessTarget = Int(target)
            } else if let target = algorithms["loudnesstarget"] as? Int {
                loudnessTarget = target
            }
            if let peak = algorithms["maxpeak"] as? Double { maxPeak = peak }
            if let dm = algorithms["dualmono"] as? Bool { dualMono = dm }
            if let method = algorithms["loudnessmethod"] as? String {
                let methods = ["program": 1, "dialog": 2, "rms": 3]
                loudnessMethod = methods[method] ?? 1
            }
        } else {
            loudnessEnabled = false
        }
    }
}

// MARK: - View

struct ManualOptionsView: View {
    @Bindable var options: ManualOptionsState
    var onChange: (() -> Void)?

    private let strengthValues = [120, 110, 100, 90, 80, 70, 60, 50, 40, 30, 20, 10, 0]
    private let musicStrengthValues = [-1, 100, 90, 80, 70, 60, 50, 40, 30, 20, 10, 0]
    private let compressorLabels = ["Auto", "Soft", "Medium", "Hard", "Off"]
    private let musicCompressorLabels = ["Same", "Auto", "Soft", "Medium", "Hard", "Off"]
    private let musicGainValues = [-6, -5, -4, -3, -2, 0, 2, 3, 4, 5, 6]
    private let maxLRAValues = [0, 3, 4, 5, 6, 8, 9, 10, 12, 15, 18, 20]
    private let maxShortTermValues = [0, 3, 4, 5, 6, 8, 9, 10, 12]
    private let maxMomentaryValues = [0, 8, 9, 10, 11, 12, 15, 18, 20]
    private let noiseAmountValues = [0, -1, 3, 6, 9, 12, 15, 18, 24, 30, 36, 100]
    private let dehumValues = [0, 50, 60]
    private let loudnessTargets = [-13, -14, -15, -16, -18, -19, -20, -23, -24, -26, -27, -31]
    private let maxPeakValues: [Double] = [0, -0.5, -1, -1.5, -2, -3, -4, -5, -6]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            levelerSection
            noiseSection
            filteringSection
            loudnessSection

            Divider()
            outputBehaviorSection
        }
        .padding(.horizontal, 4)
        .onChange(of: options.levelerEnabled) { _, _ in onChange?() }
        .onChange(of: options.noiseEnabled) { _, _ in onChange?() }
        .onChange(of: options.filteringEnabled) { _, _ in onChange?() }
        .onChange(of: options.loudnessEnabled) { _, _ in onChange?() }
        .onChange(of: options.outputFormat) { _, _ in onChange?() }
    }

    // MARK: - Leveler

    private var levelerSection: some View {
        OptionSection(title: "Adaptive Leveler", isEnabled: $options.levelerEnabled) {
            LabeledPicker("Strength", selection: $options.levelerStrength) {
                ForEach(strengthValues, id: \.self) { v in
                    Text("\(v)%").tag(v)
                }
            }

            LabeledPicker("Compressor", selection: $options.compressor) {
                ForEach(1...5, id: \.self) { i in
                    Text(compressorLabels[i - 1]).tag(i)
                }
            }

            LabeledToggle("Separate Music/Speech", isOn: $options.separateMS)

            if options.separateMS {
                LabeledPicker("Classifier", selection: $options.classifier) {
                    Text("On").tag(1)
                    Text("Speech").tag(2)
                    Text("Music").tag(3)
                }

                LabeledPicker("Speech Strength", selection: $options.speechStrength) {
                    ForEach(strengthValues, id: \.self) { v in
                        Text("\(v)%").tag(v)
                    }
                }

                LabeledPicker("Speech Compressor", selection: $options.speechCompressor) {
                    ForEach(1...5, id: \.self) { i in
                        Text(compressorLabels[i - 1]).tag(i)
                    }
                }

                LabeledPicker("Music Strength", selection: $options.musicStrength) {
                    ForEach(musicStrengthValues, id: \.self) { v in
                        Text(v == -1 ? "Same as Speech" : "\(v)%").tag(v)
                    }
                }

                LabeledPicker("Music Compressor", selection: $options.musicCompressor) {
                    ForEach(0...5, id: \.self) { i in
                        Text(musicCompressorLabels[i]).tag(i)
                    }
                }

                LabeledPicker("Music Gain", selection: $options.musicGain) {
                    ForEach(musicGainValues, id: \.self) { v in
                        Text(v == 0 ? "0 dB" : "\(v > 0 ? "+" : "")\(v) dB").tag(v)
                    }
                }
            }

            LabeledToggle("Broadcast Mode", isOn: $options.broadcastMode)

            if options.broadcastMode {
                LabeledPicker("Max LRA", selection: $options.maxLRA) {
                    ForEach(maxLRAValues, id: \.self) { v in
                        Text(v == 0 ? "Auto" : "\(v) LU").tag(v)
                    }
                }

                LabeledPicker("Max Short-Term", selection: $options.maxShortTerm) {
                    ForEach(maxShortTermValues, id: \.self) { v in
                        Text(v == 0 ? "Auto" : "\(v) LU").tag(v)
                    }
                }

                LabeledPicker("Max Momentary", selection: $options.maxMomentary) {
                    ForEach(maxMomentaryValues, id: \.self) { v in
                        Text(v == 0 ? "Auto" : "\(v) LU").tag(v)
                    }
                }

                if !options.separateMS {
                    LabeledPicker("Music Gain", selection: $options.musicGain) {
                        ForEach(musicGainValues, id: \.self) { v in
                            Text(v == 0 ? "0 dB" : "\(v > 0 ? "+" : "")\(v) dB").tag(v)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Noise

    private func noiseAmountLabel(_ v: Int, isClassic: Bool) -> String {
        switch v {
        case 0: return isClassic ? "Auto" : "Full"
        case -1: return "Off"
        case 100: return "100 dB"
        default: return "\(v) dB"
        }
    }

    private var noiseSection: some View {
        OptionSection(title: "Noise & Reverb Reduction", isEnabled: $options.noiseEnabled) {
            LabeledPicker("Method", selection: $options.noiseMethod) {
                Text("Classic").tag(1)
                Text("Dynamic").tag(2)
                Text("Speech Isolation").tag(3)
                Text("Static").tag(4)
            }

            LabeledPicker("Remove Noise", selection: $options.noiseAmount) {
                ForEach(noiseAmountValues, id: \.self) { v in
                    Text(noiseAmountLabel(v, isClassic: options.noiseMethod == 1)).tag(v)
                }
            }

            if options.noiseMethod == 1 {
                LabeledPicker("Hum Base Freq", selection: $options.dehum) {
                    Text("Auto").tag(0)
                    Text("50 Hz").tag(50)
                    Text("60 Hz").tag(60)
                }

                LabeledPicker("Remove Hum", selection: $options.dehumAmount) {
                    ForEach(noiseAmountValues.filter { $0 != 36 }, id: \.self) { v in
                        Text(noiseAmountLabel(v, isClassic: true)).tag(v)
                    }
                }
            }

            if options.noiseMethod >= 2 {
                LabeledPicker("Remove Reverb", selection: $options.reverbAmount) {
                    ForEach(noiseAmountValues, id: \.self) { v in
                        Text(noiseAmountLabel(v, isClassic: false)).tag(v)
                    }
                }
            }

            if options.noiseMethod == 2 || options.noiseMethod == 3 {
                LabeledPicker("Remove Breaths", selection: $options.breathAmount) {
                    ForEach(noiseAmountValues.filter { $0 != 0 }, id: \.self) { v in
                        Text(v == -1 ? "Off" : "\(v == 100 ? "100" : "\(v)") dB").tag(v)
                    }
                }
            }
        }
    }

    // MARK: - Filtering

    private var filteringSection: some View {
        OptionSection(title: "Filtering", isEnabled: $options.filteringEnabled) {
            LabeledPicker("Method", selection: $options.filteringMethod) {
                Text("High-Pass Filter").tag(1)
                Text("Auto EQ").tag(2)
                Text("Bandwidth Extension").tag(3)
            }
        }
    }

    // MARK: - Loudness

    private var loudnessSection: some View {
        OptionSection(title: "Loudness Normalization", isEnabled: $options.loudnessEnabled) {
            LabeledPicker("Target", selection: $options.loudnessTarget) {
                ForEach(loudnessTargets, id: \.self) { target in
                    Text("\(target) LUFS").tag(target)
                }
            }

            LabeledPicker("Max Peak", selection: $options.maxPeak) {
                ForEach(maxPeakValues, id: \.self) { v in
                    Text(v == 0 ? "Auto" : "\(v, specifier: "%.1f") dBTP").tag(v)
                }
            }

            LabeledPicker("Method", selection: $options.loudnessMethod) {
                Text("Program").tag(1)
                Text("Dialog").tag(2)
                Text("RMS").tag(3)
            }

            LabeledToggle("Dual Mono", isOn: $options.dualMono)
        }
    }

    // MARK: - Output Behavior

    private let previewDurations: [(String, Double)] = [
        ("30s", 30), ("1m", 60), ("3m", 180), ("5m", 300), ("10m", 600)
    ]

    private let lowerPickerWidth: CGFloat = 180

    private var outputBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if options.forcedOutputFormat == nil {
                HStack {
                    Text("Output Format")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: 110, alignment: .leading)
                    Picker("", selection: $options.outputFormat) {
                        ForEach(OutputFormat.allCases) { fmt in
                            Text(fmt.displayName).tag(fmt)
                        }
                    }
                    .labelsHidden()
                    .frame(width: lowerPickerWidth)
                }

                if options.outputFormat.hasBitrate {
                    HStack {
                        HStack(spacing: 0) {
                            Spacer().frame(width: 16)
                            Text("Bitrate")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .frame(width: 110, alignment: .leading)
                        Picker("", selection: $options.bitrate) {
                            ForEach(options.outputFormat.availableBitrates, id: \.self) { br in
                                Text("\(br) kbps").tag(br)
                            }
                        }
                        .labelsHidden()
                        .frame(width: lowerPickerWidth)
                    }
                }
            } else {
                HStack {
                    Text("Output Format")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: 110, alignment: .leading)
                    Text("WAV (forced)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if !options.isPerChannelMode && options.channelCount > 1 {
                HStack {
                    Text("Channel")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: 110, alignment: .leading)
                    Picker("", selection: $options.selectedChannel) {
                        Text("1+2 Channels").tag(-1)
                        ForEach(1...options.channelCount, id: \.self) { ch in
                            let name = ch <= options.trackNames.count ? options.trackNames[ch - 1] : ""
                            if name.isEmpty {
                                Text("Channel \(ch)").tag(ch)
                            } else {
                                Text("Ch \(ch) (\(name))").tag(ch)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(width: lowerPickerWidth)
                }
            }

            if options.fileDuration > 30 && options.fileCount <= 1 && !options.isPerChannelMode {
                HStack {
                    Toggle("Preview", isOn: $options.previewEnabled)
                        .font(.system(size: 12))
                        .fixedSize()
                    Picker("", selection: $options.previewDuration) {
                        ForEach(previewDurations.filter { $0.1 < options.fileDuration }, id: \.1) { label, dur in
                            Text(label).tag(dur)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 70)
                    .disabled(!options.previewEnabled)
                }
            }

            LabeledToggle("Create a new file (don't overwrite)", isOn: $options.avoidOverwrite)

            if options.avoidOverwrite {
                HStack {
                    HStack(spacing: 0) {
                        Spacer().frame(width: 16)
                        Text("Suffix")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .frame(width: 110, alignment: .leading)
                    TextField("Suffix", text: $options.outputSuffix)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: lowerPickerWidth)
                        .font(.system(size: 12))
                }
            }

            LabeledToggle("Write settings JSON alongside output", isOn: $options.writeSettingsXml)

            LabeledToggle("Keep WAV metadata (Timecode, Notes, etc.)", isOn: $options.keepTimecode)
        }
    }
}

// MARK: - Helper Views

struct OptionSection<Content: View>: View {
    let title: String
    @Binding var isEnabled: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: $isEnabled)
                .font(.system(size: 13, weight: .medium))

            if isEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    content()
                }
                .padding(.leading, 16)
            }
        }
    }
}

struct LabeledToggle: View {
    let label: String
    @Binding var isOn: Bool

    init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }

    var body: some View {
        Toggle(label, isOn: $isOn)
            .font(.system(size: 12))
    }
}

struct LabeledPicker<SelectionValue: Hashable, Content: View>: View {
    let label: String
    @Binding var selection: SelectionValue
    @ViewBuilder var content: () -> Content

    init(_ label: String, selection: Binding<SelectionValue>, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self._selection = selection
        self.content = content
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 110, alignment: .leading)

            Picker("", selection: $selection) {
                content()
            }
            .labelsHidden()
            .frame(maxWidth: 200)
        }
    }
}
