import SwiftUI

/// Settings pane for Standard mode: one production per file, whole file in,
/// processed file back in the chosen output format.
struct StandardModeView: View {
    @Bindable var config: StandardModeConfig
    var presets: [AuphonicPreset]
    var fileCount: Int
    var onChange: (() -> Void)?
    var onSavePreset: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("Processing")
                .padding(.horizontal, 12)
                .padding(.top, 16)

            optionChips
                .padding(.horizontal, 12)
                .padding(.top, 10)

            uploadPlan
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    PresetListView(
                        presets: presets,
                        selectedUuid: $config.selectedPresetUuid,
                        isModified: $config.presetModified,
                        onSavePreset: { onSavePreset?() }
                    )

                    outputCard
                    ManualOptionsView(options: config.options, onChange: onChange)
                    cuttingCard
                }
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 4)
        }
    }

    private var optionChips: some View {
        GlassCheckbox(
            label: "Settings JSON",
            isOn: $config.writeSettingsJson,
            systemImage: "doc.text"
        )
    }

    private var uploadPlan: some View {
        Text(uploadPlanText)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var uploadPlanText: String {
        guard fileCount > 0 else { return "Add files to process them with these settings" }
        let format = config.outputFormat == .keep
            ? "the input format"
            : config.outputFormat.displayName
        let cut = config.cutting.isActive && config.cutting.cutMode == .applyCuts
            ? ", shortened by automatic cutting"
            : ""
        return "\(fileCount) production\(fileCount == 1 ? "" : "s") — one per file, returned as \(format)\(cut)"
    }

    // MARK: - Automatic Cutting

    private var cuttingCard: some View {
        AlgorithmCard(
            title: "Automatic Cutting",
            subtitle: "Cuts silence, filler words, coughs and music out of the file",
            info: AlgorithmInfo.automaticCutting,
            isEnabled: cuttingBinding(\.enabled)
        ) {
            ToggleRow("Silence", info: AlgorithmInfo.automaticCutting, isOn: cuttingBinding(\.cutSilence))
            ToggleRow("Filler Words", info: AlgorithmInfo.automaticCutting, isOn: cuttingBinding(\.cutFillers))
            ToggleRow("Coughs", info: AlgorithmInfo.automaticCutting, isOn: cuttingBinding(\.cutCoughs))
            ToggleRow("Music", info: AlgorithmInfo.automaticCutting, isOn: cuttingBinding(\.cutMusic))

            PickerRow("Cut Mode", info: AlgorithmInfo.cutMode, selection: cuttingBinding(\.cutMode)) {
                ForEach(CutMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            SliderRow(
                "Fade Time",
                info: AlgorithmInfo.cutFadeTime,
                values: [0, 25, 50, 100, 150, 200, 300, 500, 1000, 2000, 5000],
                selection: cuttingBinding(\.fadeTime),
                display: { "\($0) ms" }
            )
        }
    }

    /// Cutting lives in its own model, so its bindings are built by key path
    private func cuttingBinding<Value>(_ keyPath: ReferenceWritableKeyPath<CuttingOptions, Value>) -> Binding<Value> {
        Binding(
            get: { config.cutting[keyPath: keyPath] },
            set: { config.cutting[keyPath: keyPath] = $0; onChange?() }
        )
    }

    // MARK: - Output

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Output File")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Format Auphonic encodes the processed file in")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                InfoButton(title: "Output File", text: AlgorithmInfo.outputFormat)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                PickerRow("Format", info: AlgorithmInfo.outputFormat, selection: formatBinding) {
                    ForEach(OutputFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                if config.outputFormat.hasBitrate {
                    PickerRow("Bitrate", info: AlgorithmInfo.outputBitrate, selection: bitrateBinding) {
                        ForEach(config.outputFormat.availableBitrates, id: \.self) { rate in
                            Text("\(rate) kbps").tag(rate)
                        }
                    }
                }
            }
            .padding(.leading, 4)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    /// Switching the format resets the bitrate to that format's default when
    /// the current one isn't offered for it
    private var formatBinding: Binding<OutputFormat> {
        Binding(
            get: { config.options.outputFormat },
            set: { newFormat in
                config.options.outputFormat = newFormat
                if newFormat.hasBitrate, !newFormat.availableBitrates.contains(config.options.bitrate) {
                    config.options.bitrate = newFormat.defaultBitrate
                }
                onChange?()
            }
        )
    }

    private var bitrateBinding: Binding<Int> {
        Binding(
            get: { config.options.bitrate },
            set: { config.options.bitrate = $0; onChange?() }
        )
    }
}

// MARK: - Preview

#Preview("Standard mode") {
    let config = StandardModeConfig()
    config.options.levelerEnabled = true
    config.options.outputFormat = .mp3
    return StandardModeView(config: config, presets: [], fileCount: 12)
        .frame(width: 620, height: 820)
}
