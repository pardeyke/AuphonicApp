import SwiftUI

/// Master-track (mixdown) settings of a multitrack production, plus the
/// mixdown export options. Per-track settings stay in `ManualOptionsView`.
struct MultitrackOptionsView: View {
    @Bindable var config: ChannelConfig
    var onChange: (() -> Void)?

    private let maxLRAValues = [0, 5, 6, 8, 9, 10, 12, 15, 18, 20, 25, 30]
    private let maxShortTermValues = [0, 3, 4, 5, 6, 8, 9, 10, 12]
    private let maxMomentaryValues = [0, 8, 9, 10, 11, 12, 15, 18, 20]
    private let loudnessTargets = [-31, -27, -26, -24, -23, -20, -19, -18, -16, -15, -14, -13]
    private let maxPeakValues: [Double] = [0, -0.5, -1, -1.5, -2, -3, -4, -5, -6]

    private var master: MultitrackMasterOptions { config.masterOptions }

    private func changed<T>(_ binding: Binding<T>) -> Binding<T> {
        Binding(
            get: { binding.wrappedValue },
            set: { binding.wrappedValue = $0; onChange?() }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            mixdownCard
            masterLevelerCard
            gatesCard
            masterLoudnessCard
        }
    }

    // MARK: - Mixdown Export

    private var mixdownCard: some View {
        SettingsCard(
            title: "Mixdown",
            subtitle: "Individual tracks are always exported and written back to their channels",
            info: AlgorithmInfo.multitrackMixdown
        ) {
            GlassCheckbox(
                label: "Also download the master mixdown",
                isOn: Binding(
                    get: { config.downloadMixdown },
                    set: { config.downloadMixdown = $0; onChange?() }
                ),
                systemImage: "square.and.arrow.down"
            )

            if config.downloadMixdown {
                HStack(spacing: 8) {
                    Text("Write mixdown to")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 130, alignment: .leading)

                    Picker("", selection: Binding(
                        get: { config.mixdownTargetChannel ?? -1 },
                        set: { config.mixdownTargetChannel = $0 < 0 ? nil : $0; onChange?() }
                    )) {
                        Text("Don't write into the file").tag(-1)
                        ForEach(config.channels) { channel in
                            Text(channel.displayName).tag(channel.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 230)

                    InfoButton(title: "Mixdown target channel", text: AlgorithmInfo.mixdownTarget)

                    Spacer(minLength: 0)
                }

                if let target = config.mixdownTargetChannel,
                   config.channels.indices.contains(target),
                   config.channels[target].enabled {
                    Label(
                        "Channel \(target + 1) is also processed as its own track — the mixdown overwrites it.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                }

                Text("The mixdown is always requested as a mono file.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Master Leveler

    private var masterLevelerCard: some View {
        SettingsCard(
            title: "Master Leveler",
            subtitle: "Balances the combined mix of all tracks",
            info: AlgorithmInfo.multitrackMasterLeveler,
            isEnabled: changed(Binding(get: { master.levelerEnabled }, set: { master.levelerEnabled = $0 }))
        ) {
            ToggleRow(
                "Broadcast Mode",
                info: AlgorithmInfo.maxLRA,
                isOn: changed(Binding(get: { master.broadcastMode }, set: { master.broadcastMode = $0 }))
            )

            if master.broadcastMode {
                PickerRow("Max LRA", info: AlgorithmInfo.maxLRA,
                          selection: changed(Binding(get: { master.maxLRA }, set: { master.maxLRA = $0 }))) {
                    ForEach(maxLRAValues, id: \.self) { v in
                        Text(v == 0 ? "Auto" : "\(v) LU").tag(v)
                    }
                }

                PickerRow("Max Short-Term", info: AlgorithmInfo.maxShortTerm,
                          selection: changed(Binding(get: { master.maxShortTerm }, set: { master.maxShortTerm = $0 }))) {
                    ForEach(maxShortTermValues, id: \.self) { v in
                        Text(v == 0 ? "Auto" : "\(v) LU").tag(v)
                    }
                }

                PickerRow("Max Momentary", info: AlgorithmInfo.maxMomentary,
                          selection: changed(Binding(get: { master.maxMomentary }, set: { master.maxMomentary = $0 }))) {
                    ForEach(maxMomentaryValues, id: \.self) { v in
                        Text(v == 0 ? "Auto" : "\(v) LU").tag(v)
                    }
                }
            }
        }
    }

    // MARK: - Gates

    private var gatesCard: some View {
        SettingsCard(
            title: "Gates & Crosstalk",
            subtitle: "Only available in multitrack productions",
            info: AlgorithmInfo.multitrackGates
        ) {
            ToggleRow(
                "Noise Gate",
                info: AlgorithmInfo.multitrackGate,
                isOn: changed(Binding(get: { master.gate }, set: { master.gate = $0 }))
            )

            ToggleRow(
                "Crosstalk / Mic Bleed Damping",
                info: AlgorithmInfo.multitrackCrossgate,
                isOn: changed(Binding(get: { master.crossgate }, set: { master.crossgate = $0 }))
            )
        }
    }

    // MARK: - Master Loudness

    private var masterLoudnessCard: some View {
        SettingsCard(
            title: "Master Loudness Normalization",
            subtitle: "Loudness target and true peak limiter of the mixdown",
            info: AlgorithmInfo.loudness,
            isEnabled: changed(Binding(get: { master.loudnessEnabled }, set: { master.loudnessEnabled = $0 }))
        ) {
            SliderRow(
                "Loudness Target",
                info: AlgorithmInfo.loudnessTarget,
                values: loudnessTargets,
                selection: changed(Binding(get: { master.loudnessTarget }, set: { master.loudnessTarget = $0 })),
                display: { "\($0) LUFS" }
            )

            PickerRow("Max Peak Level", info: AlgorithmInfo.maxPeak,
                      selection: changed(Binding(get: { master.maxPeak }, set: { master.maxPeak = $0 }))) {
                ForEach(maxPeakValues, id: \.self) { v in
                    Text(v == 0 ? "Auto" : String(format: "%.1f dBTP", v)).tag(v)
                }
            }

            PickerRow("Method", info: AlgorithmInfo.loudnessMethod,
                      selection: changed(Binding(get: { master.loudnessMethod }, set: { master.loudnessMethod = $0 }))) {
                Text("Program Loudness").tag(1)
                Text("Dialog Loudness").tag(2)
                Text("RMS").tag(3)
            }

            ToggleRow(
                "Dual Mono",
                info: AlgorithmInfo.dualMono,
                isOn: changed(Binding(get: { master.dualMono }, set: { master.dualMono = $0 }))
            )
        }
    }
}
