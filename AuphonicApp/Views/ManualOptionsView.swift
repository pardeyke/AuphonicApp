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
    var filteringMethod = 1         // 1=High-Pass, 2=Auto EQ, 3=Bandwidth Extension, 4=Studio Voice

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

    // Output Behavior
    var avoidOverwrite = true
    var outputSuffix = "_auphonic"
    var writeSettingsXml = false
    var keepTimecode = false

    // Preview
    var previewEnabled = false
    var previewDuration: Double = 60    // seconds
    var fileDuration: Double = 0        // seconds, set from outside

    // Forced output format (set when merge requires WAV)
    var forcedOutputFormat: String?

    /// Effective preview duration for processing (0 = full)
    var effectivePreviewDuration: Double {
        guard previewEnabled else { return 0 }
        return previewDuration
    }

    /// `filtermethod` values in picker order — same enum for singletrack
    /// productions and for the per-track algorithms of a multitrack production.
    static let filterMethods = ["hipfilter", "autoeq", "bwe", "studiovoice"]

    private var filterMethodValue: String {
        let index = filteringMethod - 1
        guard Self.filterMethods.indices.contains(index) else { return "hipfilter" }
        return Self.filterMethods[index]
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
            algorithms["filtermethod"] = filterMethodValue
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

        // Output format: only `output_files` is an API field. When the format
        // is .keep it is omitted so Auphonic keeps the input format.
        if let forced = forcedOutputFormat {
            settings["output_files"] = [["format": forced]]
        } else if outputFormat != .keep {
            var outputFile: [String: Any] = ["format": outputFormat.rawValue]
            if outputFormat.hasBitrate {
                outputFile["bitrate"] = "\(bitrate)"
            }
            settings["output_files"] = [outputFile]
        }

        return settings
    }

    /// Per-track `algorithms` of a multitrack production. Only the keys that
    /// are valid inside `multi_input_files[]` are emitted — loudness
    /// normalization and the leveler on/off switch belong to the master track.
    func getMultitrackTrackSettings() -> [String: Any] {
        var algorithms: [String: Any] = [:]
        let compressorValues = ["auto", "soft", "medium", "hard", "off"]

        if levelerEnabled {
            if separateMS {
                let classifierValues = ["on", "speech", "music"]
                algorithms["msclassifier"] = classifierValues[classifier - 1]
                algorithms["levelerstrength"] = speechStrength
                algorithms["compressor"] = compressorValues[speechCompressor - 1]
            } else {
                algorithms["levelerstrength"] = levelerStrength
                algorithms["compressor"] = compressorValues[compressor - 1]
            }
        } else {
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
        } else {
            algorithms["denoise"] = false
        }

        if filteringEnabled {
            algorithms["filtering"] = true
            algorithms["filtermethod"] = filterMethodValue
        } else {
            algorithms["filtering"] = false
        }

        return algorithms
    }

    func hasAnyEnabled() -> Bool {
        levelerEnabled || noiseEnabled || filteringEnabled || loudnessEnabled || outputFormatEnabled
    }

    /// True when at least one actual processing algorithm is enabled
    /// (output format alone doesn't count — it's forced to WAV anyway)
    func hasAnyAlgorithmEnabled() -> Bool {
        levelerEnabled || noiseEnabled || filteringEnabled || loudnessEnabled
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
                filteringMethod = (Self.filterMethods.firstIndex(of: method) ?? 0) + 1
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

/// Auphonic algorithm settings styled after the Auphonic web production UI:
/// one card per algorithm with a switch, short description, info popovers,
/// and sliders/dropdowns for the parameters.
struct ManualOptionsView: View {
    @Bindable var options: ManualOptionsState
    var onChange: (() -> Void)?

    private let strengthValues = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120]
    private let musicStrengthValues = [-1, 100, 90, 80, 70, 60, 50, 40, 30, 20, 10, 0]
    private let compressorLabels = ["Auto", "Soft", "Medium", "Hard", "Off"]
    private let musicCompressorLabels = ["Same", "Auto", "Soft", "Medium", "Hard", "Off"]
    private let musicGainValues = [-6, -5, -4, -3, -2, 0, 2, 3, 4, 5, 6]
    private let maxLRAValues = [0, 3, 4, 5, 6, 8, 9, 10, 12, 15, 18, 20]
    private let maxShortTermValues = [0, 3, 4, 5, 6, 8, 9, 10, 12]
    private let maxMomentaryValues = [0, 8, 9, 10, 11, 12, 15, 18, 20]
    private let noiseAmountValues = [0, -1, 3, 6, 9, 12, 15, 18, 24, 30, 36, 100]
    private let loudnessTargets = [-31, -27, -26, -24, -23, -20, -19, -18, -16, -15, -14, -13]
    private let maxPeakValues: [Double] = [0, -0.5, -1, -1.5, -2, -3, -4, -5, -6]

    var body: some View {
        // Signal-chain order: clean up first, then level and normalize
        VStack(alignment: .leading, spacing: 10) {
            noiseCard
            filteringCard
            levelerCard
            loudnessCard
        }
    }

    /// Wrap a binding so every change also notifies onChange (marks preset as modified)
    private func changed<T>(_ binding: Binding<T>) -> Binding<T> {
        Binding(
            get: { binding.wrappedValue },
            set: { binding.wrappedValue = $0; onChange?() }
        )
    }

    // MARK: - Adaptive Leveler

    /// 0 = Default, 1 = Separate Music/Speech, 2 = Broadcast Mode
    private var levelerMode: Binding<Int> {
        Binding(
            get: {
                if options.broadcastMode { return 2 }
                if options.separateMS { return 1 }
                return 0
            },
            set: { mode in
                options.separateMS = (mode == 1)
                options.broadcastMode = (mode == 2)
                onChange?()
            }
        )
    }

    private func strengthLabel(_ v: Int) -> String {
        switch v {
        case 110: return "110% (Fast)"
        case 120: return "120% (Amplify All)"
        default: return "\(v)%"
        }
    }

    private var levelerCard: some View {
        SettingsCard(
            title: "Adaptive Leveler",
            subtitle: "Corrects level differences between speakers, music and speech",
            info: AlgorithmInfo.leveler,
            isEnabled: changed($options.levelerEnabled)
        ) {
            PickerRow("Leveler Mode", info: AlgorithmInfo.levelerMode, selection: levelerMode) {
                Text("Default").tag(0)
                Text("Separate Music/Speech").tag(1)
                Text("Broadcast Mode").tag(2)
            }

            if !options.separateMS {
                SliderRow(
                    "Strength",
                    info: AlgorithmInfo.levelerStrength,
                    values: strengthValues,
                    selection: changed($options.levelerStrength),
                    display: strengthLabel
                )

                PickerRow("Compressor", info: AlgorithmInfo.compressor, selection: changed($options.compressor)) {
                    ForEach(1...5, id: \.self) { i in
                        Text(compressorLabels[i - 1]).tag(i)
                    }
                }
            }

            if options.separateMS {
                PickerRow("Classifier", info: AlgorithmInfo.classifier, selection: changed($options.classifier)) {
                    Text("Level Music and Speech").tag(1)
                    Text("Level Speech only").tag(2)
                    Text("Level Music only").tag(3)
                }

                SliderRow(
                    "Speech Strength",
                    info: AlgorithmInfo.levelerStrength,
                    values: strengthValues,
                    selection: changed($options.speechStrength),
                    display: strengthLabel
                )

                PickerRow("Speech Compressor", info: AlgorithmInfo.compressor, selection: changed($options.speechCompressor)) {
                    ForEach(1...5, id: \.self) { i in
                        Text(compressorLabels[i - 1]).tag(i)
                    }
                }

                PickerRow("Music Strength", info: AlgorithmInfo.levelerStrength, selection: changed($options.musicStrength)) {
                    ForEach(musicStrengthValues, id: \.self) { v in
                        Text(v == -1 ? "Same as Speech" : "\(v)%").tag(v)
                    }
                }

                PickerRow("Music Compressor", info: AlgorithmInfo.compressor, selection: changed($options.musicCompressor)) {
                    ForEach(0...5, id: \.self) { i in
                        Text(musicCompressorLabels[i]).tag(i)
                    }
                }

                SliderRow(
                    "Music Gain",
                    info: AlgorithmInfo.musicGain,
                    values: musicGainValues,
                    selection: changed($options.musicGain),
                    display: { v in v == 0 ? "0 dB" : "\(v > 0 ? "+" : "")\(v) dB" }
                )
            }

            if options.broadcastMode {
                PickerRow("Max LRA", info: AlgorithmInfo.maxLRA, selection: changed($options.maxLRA)) {
                    ForEach(maxLRAValues, id: \.self) { v in
                        Text(v == 0 ? "Auto" : "\(v) LU").tag(v)
                    }
                }

                PickerRow("Max Short-Term", info: AlgorithmInfo.maxShortTerm, selection: changed($options.maxShortTerm)) {
                    ForEach(maxShortTermValues, id: \.self) { v in
                        Text(v == 0 ? "Auto" : "\(v) LU").tag(v)
                    }
                }

                PickerRow("Max Momentary", info: AlgorithmInfo.maxMomentary, selection: changed($options.maxMomentary)) {
                    ForEach(maxMomentaryValues, id: \.self) { v in
                        Text(v == 0 ? "Auto" : "\(v) LU").tag(v)
                    }
                }

                if !options.separateMS {
                    SliderRow(
                        "Music Gain",
                        info: AlgorithmInfo.musicGain,
                        values: musicGainValues,
                        selection: changed($options.musicGain),
                        display: { v in v == 0 ? "0 dB" : "\(v > 0 ? "+" : "")\(v) dB" }
                    )
                }
            }
        }
    }

    // MARK: - Loudness Normalization

    private var loudnessCard: some View {
        SettingsCard(
            title: "Loudness Normalization",
            subtitle: "Normalizes the file to a loudness target with a true peak limiter",
            info: AlgorithmInfo.loudness,
            isEnabled: changed($options.loudnessEnabled)
        ) {
            SliderRow(
                "Loudness Target",
                info: AlgorithmInfo.loudnessTarget,
                values: loudnessTargets,
                selection: changed($options.loudnessTarget),
                display: { "\($0) LUFS" }
            )

            PickerRow("Max Peak Level", info: AlgorithmInfo.maxPeak, selection: changed($options.maxPeak)) {
                ForEach(maxPeakValues, id: \.self) { v in
                    Text(v == 0 ? "Auto" : String(format: "%.1f dBTP", v)).tag(v)
                }
            }

            PickerRow("Method", info: AlgorithmInfo.loudnessMethod, selection: changed($options.loudnessMethod)) {
                Text("Program Loudness").tag(1)
                Text("Dialog Loudness").tag(2)
                Text("RMS").tag(3)
            }

            ToggleRow("Dual Mono", info: AlgorithmInfo.dualMono, isOn: changed($options.dualMono))
        }
    }

    // MARK: - Filtering

    private var filteringCard: some View {
        SettingsCard(
            title: "Filtering",
            subtitle: "Adaptive high-pass filtering and voice spectrum optimization",
            info: AlgorithmInfo.filtering,
            isEnabled: changed($options.filteringEnabled)
        ) {
            PickerRow("Method", info: AlgorithmInfo.filteringMethod, selection: changed($options.filteringMethod)) {
                Text("Adaptive High-Pass Filter").tag(1)
                Text("Voice AutoEQ").tag(2)
                Text("Voice AutoEQ + Bandwidth Extension").tag(3)
                Text("Studio Voice (beta)").tag(4)
            }
        }
    }

    // MARK: - Noise & Reverb Reduction

    /// dB amount labels with the web UI's low/medium/high/full annotations.
    /// Per the API docs, 0 means "Auto" for the Classic denoiser but
    /// "100 dB full" for the other methods — where it duplicates the explicit
    /// 100 entry, so callers hide 100 for non-classic methods.
    private func noiseAmountLabel(_ v: Int, isClassic: Bool) -> String {
        switch v {
        case 0: return isClassic ? "Auto" : "Full (100 dB)"
        case -1: return "Off"
        case 6: return "6 dB (low)"
        case 12: return "12 dB (medium)"
        case 24: return "24 dB (high)"
        case 100: return "100 dB (full)"
        default: return "\(v) dB"
        }
    }

    /// Valid amount values for the current method: the explicit 100 entry is
    /// redundant when 0 already means "full" (all methods except Classic).
    /// "Full" is always the last menu entry, like in the web UI.
    private func noiseAmountOptions(isClassic: Bool) -> [Int] {
        if isClassic { return noiseAmountValues }
        return noiseAmountValues.filter { $0 != 100 && $0 != 0 } + [0]
    }

    private var noiseCard: some View {
        SettingsCard(
            title: "Noise & Reverb Reduction",
            subtitle: "Removes background noise, hum and reverb from speech",
            info: AlgorithmInfo.denoise,
            isEnabled: changed($options.noiseEnabled)
        ) {
            PickerRow("Method", info: AlgorithmInfo.denoiseMethod, selection: Binding(
                get: { options.noiseMethod },
                set: { method in
                    options.noiseMethod = method
                    // Outside Classic, 0 already means "full" — fold the explicit 100 into it
                    if method != 1 && options.noiseAmount == 100 {
                        options.noiseAmount = 0
                    }
                    onChange?()
                }
            )) {
                Text("Classic Denoiser").tag(1)
                Text("Dynamic Denoiser").tag(2)
                Text("Speech Isolation").tag(3)
                Text("Static Denoiser").tag(4)
            }

            PickerRow("Remove Noise", info: AlgorithmInfo.denoiseAmount, selection: changed($options.noiseAmount)) {
                ForEach(noiseAmountOptions(isClassic: options.noiseMethod == 1), id: \.self) { v in
                    Text(noiseAmountLabel(v, isClassic: options.noiseMethod == 1)).tag(v)
                }
            }

            if options.noiseMethod == 1 {
                PickerRow("Hum Base Frequency", info: AlgorithmInfo.dehum, selection: changed($options.dehum)) {
                    Text("Auto").tag(0)
                    Text("50 Hz").tag(50)
                    Text("60 Hz").tag(60)
                }

                PickerRow("Remove Hum", info: AlgorithmInfo.dehumAmount, selection: changed($options.dehumAmount)) {
                    ForEach(noiseAmountValues.filter { $0 != 36 }, id: \.self) { v in
                        Text(noiseAmountLabel(v, isClassic: true)).tag(v)
                    }
                }
            }

            if options.noiseMethod >= 2 {
                PickerRow("Remove Reverb", info: AlgorithmInfo.reverbAmount, selection: changed($options.reverbAmount)) {
                    ForEach(noiseAmountOptions(isClassic: false), id: \.self) { v in
                        Text(noiseAmountLabel(v, isClassic: false)).tag(v)
                    }
                }
            }

            if options.noiseMethod == 2 || options.noiseMethod == 3 {
                PickerRow("Remove Breaths", info: AlgorithmInfo.breathAmount, selection: changed($options.breathAmount)) {
                    ForEach(noiseAmountValues.filter { $0 != 0 }, id: \.self) { v in
                        Text(noiseAmountLabel(v, isClassic: false)).tag(v)
                    }
                }
            }
        }
    }
}

private struct ManualOptionsPreviewHost: View {
    let options: ManualOptionsState

    init() {
        let state = ManualOptionsState()
        state.levelerEnabled = true
        state.noiseEnabled = true
        state.noiseMethod = 2
        state.loudnessEnabled = true
        self.options = state
    }

    var body: some View {
        ScrollView {
            ManualOptionsView(options: options)
                .padding(16)
        }
        .frame(width: 560, height: 760)
    }
}

#Preview("Algorithm Settings") {
    ManualOptionsPreviewHost()
}

// MARK: - Card & Row Components

/// One block of settings styled after the Auphonic web UI: title with a short
/// description, an info popover, and the parameters below a divider. With
/// `isEnabled` the header gets a switch and the parameters only show while
/// it is on (the algorithm cards); without it the content is always shown.
///
/// Content cards are not Liquid Glass — glass is for the controls floating
/// above the content — so this is a grouped background with a hairline.
struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    let info: String
    var isEnabled: Binding<Bool>? = nil
    @ViewBuilder var content: () -> Content

    static var cornerRadius: CGFloat { 12 }

    private var showsContent: Bool { isEnabled?.wrappedValue ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                if let isEnabled {
                    Toggle("", isOn: isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                InfoButton(title: title, text: info)
            }

            if showsContent {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .padding(.leading, 4)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }
}

/// ⓘ button that shows an explanation popover (texts from the Auphonic docs)
struct InfoButton: View {
    let title: String
    let text: String
    @State private var showingInfo = false

    var body: some View {
        Button {
            showingInfo.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingInfo, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(text)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(width: 340, alignment: .leading)
        }
    }
}

private let parameterLabelWidth: CGFloat = 130

/// Parameter row with a dropdown, like the web UI's selects
struct PickerRow<SelectionValue: Hashable, Content: View>: View {
    let label: String
    let info: String
    @Binding var selection: SelectionValue
    @ViewBuilder var content: () -> Content

    init(_ label: String, info: String, selection: Binding<SelectionValue>, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.info = info
        self._selection = selection
        self.content = content
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: parameterLabelWidth, alignment: .leading)

            Picker("", selection: $selection) {
                content()
            }
            .labelsHidden()
            .frame(maxWidth: 230)

            InfoButton(title: label, text: info)

            Spacer(minLength: 0)
        }
    }
}

/// Parameter row with a discrete slider and value label, like the web UI's sliders
struct SliderRow: View {
    let label: String
    let info: String
    let values: [Int]           // ascending
    @Binding var selection: Int
    let display: (Int) -> String

    init(_ label: String, info: String, values: [Int], selection: Binding<Int>, display: @escaping (Int) -> String) {
        self.label = label
        self.info = info
        self.values = values.sorted()
        self._selection = selection
        self.display = display
    }

    private var index: Binding<Double> {
        Binding(
            get: { Double(values.firstIndex(of: selection) ?? nearestIndex(to: selection)) },
            set: { selection = values[max(0, min(values.count - 1, Int($0.rounded())))] }
        )
    }

    private func nearestIndex(to value: Int) -> Int {
        values.enumerated().min(by: { abs($0.element - value) < abs($1.element - value) })?.offset ?? 0
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: parameterLabelWidth, alignment: .leading)

            Slider(value: index, in: 0...Double(values.count - 1), step: 1)
                .controlSize(.small)
                .frame(maxWidth: 230)

            Text(display(selection))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)

            InfoButton(title: label, text: info)

            Spacer(minLength: 0)
        }
    }
}

/// Parameter row with a glass checkbox
struct ToggleRow: View {
    let label: String
    let info: String
    @Binding var isOn: Bool

    init(_ label: String, info: String, isOn: Binding<Bool>) {
        self.label = label
        self.info = info
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: 8) {
            GlassCheckbox(label: label, isOn: $isOn)

            InfoButton(title: label, text: info)

            Spacer(minLength: 0)
        }
    }
}
