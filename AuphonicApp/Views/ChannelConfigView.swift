import SwiftUI

/// Configuration UI for one file group: production mode, which channels are
/// processed, and the Auphonic settings.
struct ChannelConfigView: View {
    @Bindable var config: ChannelConfig
    var presets: [AuphonicPreset]
    var onChange: (() -> Void)?
    var onSavePreset: (() -> Void)?

    @State private var selectedSettingsTab: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.top, 16)

            channelSection
                .padding(.horizontal, 12)
                .padding(.top, 10)

            optionChips
                .padding(.horizontal, 12)
                .padding(.top, 8)

            uploadPlanSection
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 14)

            ScrollView {
                settingsArea
                    .padding(.horizontal, 8)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Header

    private var header: some View {
        SectionHeading(title: "Group Processing") {
            TabsPicker(
                values: ProductionMode.allCases,
                titles: ProductionMode.allCases.map(\.displayName),
                selection: Binding(
                    get: { config.productionMode },
                    set: { config.productionMode = $0; onChange?() }
                ),
                controlSize: .large
            )
            .fixedSize()

            InfoButton(title: "Production Mode", text: AlgorithmInfo.productionMode)
        }
    }

    @ViewBuilder
    private var settingsArea: some View {
        switch config.productionMode {
        case .singletrack:
            singletrackColumn
        case .multitrack:
            multitrackColumns
        }
    }

    // MARK: - Channels

    private var channelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsGroupLabel(text: "Channels")

            // Channel pills wrap to as many rows as needed
            GlassEffectContainer(spacing: GlassSpacing.chips) {
                FlowLayout(spacing: 6) {
                    ForEach(config.channels) { channel in
                        GlassCheckbox(
                            label: channel.displayName,
                            isOn: Binding(
                                get: { channel.enabled },
                                set: { channel.enabled = $0; onChange?() }
                            ),
                            systemImage: "waveform"
                        )
                    }
                }
            }
        }
    }

    private var optionChips: some View {
        GlassEffectContainer(spacing: GlassSpacing.chips) {
            FlowLayout(spacing: 6) {
                GlassCheckbox(
                    label: "Link settings",
                    isOn: Binding(
                        get: { config.linkedSettings },
                        set: { config.linkedSettings = $0; onChange?() }
                    ),
                    systemImage: "link"
                )

                GlassCheckbox(
                    label: "Settings JSON",
                    isOn: Binding(
                        get: { config.writeSettingsJson },
                        set: { config.writeSettingsJson = $0 }
                    ),
                    systemImage: "doc.text"
                )
            }
        }
    }

    // MARK: - Upload plan

    private var uploadPlanSection: some View {
        Text(uploadPlanText)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var uploadPlanText: String {
        let jobs = config.uploadJobs
        guard !jobs.isEmpty else { return "No channels selected" }

        switch config.productionMode {
        case .singletrack:
            return "\(jobs.count) production\(jobs.count == 1 ? "" : "s") per file: "
                + jobs.map(\.label).joined(separator: ", ")
        case .multitrack:
            let tracks = jobs.count
            let mixdown = config.downloadMixdown ? " + mixdown" : ""
            return "1 multitrack production per file — \(tracks) track\(tracks == 1 ? "" : "s")\(mixdown)"
        }
    }

    // MARK: - Settings

    private var singletrackColumn: some View {
        VStack(spacing: 10) {
            if config.linkedSettings {
                PresetListView(
                    presets: presets,
                    selectedUuid: $config.selectedPresetUuid,
                    isModified: $config.presetModified,
                    onSavePreset: { onSavePreset?() }
                )
            }
            settingsContent
        }
    }

    /// Side by side when the pane is wide enough, stacked otherwise
    private var multitrackColumns: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                trackSettingsColumn.frame(minWidth: 360, maxWidth: .infinity)
                masterColumn.frame(minWidth: 330, maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 14) {
                trackSettingsColumn
                masterColumn
            }
        }
    }

    private var trackSettingsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsGroupLabel(text: "Track settings")
            if config.productionMode == .multitrack {
                trackExportDisclaimer
            }
            settingsContent
        }
    }

    /// Auphonic currently returns the individual tracks of a multitrack
    /// production as 16-bit WAV, so the level should already be right on
    /// download — gaining a quiet 16-bit track up in the DAW lifts its noise
    /// floor with it.
    private var trackExportDisclaimer: some View {
        hint("In multitrack mode Auphonic exports the individual tracks as 16-bit WAV only — 24-bit is not available. Enable the Adaptive Leveler so the tracks come back at a usable level instead of being gained up later, which would raise the 16-bit noise floor.")
    }

    /// Warning note that wraps into the column instead of widening it
    private func hint(_ text: String) -> some View {
        HintWidth {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)

                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
        }
    }

    private var masterColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsGroupLabel(text: "Master & mixdown")
            masterDisclaimer
            MultitrackOptionsView(config: config, onChange: onChange)
        }
    }

    /// The master algorithms are not limited to the mixdown: Auphonic applies
    /// them while mastering, so the exported individual tracks change too —
    /// even when the mixdown itself is never downloaded.
    private var masterDisclaimer: some View {
        hint("These master settings also affect the exported individual tracks, not only the mixdown — even if the mixdown is not downloaded. Leave them all off to only process the individual tracks.")
    }

    @ViewBuilder
    private var settingsContent: some View {
        if config.linkedSettings {
            ManualOptionsView(options: config.sharedOptions, onChange: onChange)
        } else {
            let enabledChannels = config.channels.filter(\.enabled)
            if enabledChannels.isEmpty {
                Text("Enable a channel to configure it")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // Per-channel tabs as glass chips
                    GlassEffectContainer(spacing: GlassSpacing.chips) {
                        FlowLayout(spacing: 6) {
                            ForEach(enabledChannels) { channel in
                                channelTab(channel, isSelected: tabChannel(in: enabledChannels)?.id == channel.id)
                            }
                        }
                    }

                    if let channel = tabChannel(in: enabledChannels) {
                        ManualOptionsView(options: channel.options, onChange: onChange)
                    }
                }
            }
        }
    }

    private func tabChannel(in channels: [ChannelEntry]) -> ChannelEntry? {
        channels.first { $0.id == selectedSettingsTab } ?? channels.first
    }

    private func channelTab(_ channel: ChannelEntry, isSelected: Bool) -> some View {
        Button {
            selectedSettingsTab = channel.id
        } label: {
            Text(channel.displayName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(
                    isSelected ? .regular.tint(.accentColor.opacity(0.8)).interactive() : .regular.interactive(),
                    in: .rect(cornerRadius: 9)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Wraps long hint text into whatever width it is given without claiming any
/// width of its own: a `Text`'s ideal width is its full single line, which
/// would widen the settings column and make `ViewThatFits` drop the
/// side-by-side layout.
struct HintWidth: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }

        // Ideal measurement (no width proposed): take up no space so the
        // column keeps the width its controls need.
        guard let width = proposal.width, width > 0, width < .infinity else { return .zero }

        let height = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: bounds.width, height: nil)
        )
    }
}

/// Lays out subviews left to right, wrapping to new rows as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                widestRow = max(widestRow, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }

        widestRow = max(widestRow, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: min(widestRow, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Preview

private struct ChannelConfigPreviewHost: View {
    let config: ChannelConfig

    init(mode: ProductionMode, mixdown: Bool) {
        let config = ChannelConfig()
        config.configure(count: 4, trackNames: ["BOOM", "LAVMIX", "LAV1", "LAV2"])
        config.productionMode = mode
        config.downloadMixdown = mixdown
        if mixdown { config.mixdownTargetChannel = 1 }
        config.sharedOptions.levelerEnabled = true
        config.sharedOptions.noiseEnabled = true
        self.config = config
    }

    var body: some View {
        ChannelConfigView(config: config, presets: [])
    }
}

#Preview("Multitrack — wide") {
    ChannelConfigPreviewHost(mode: .multitrack, mixdown: true)
        .frame(width: 1000, height: 860)
}

#Preview("Multitrack — narrow") {
    ChannelConfigPreviewHost(mode: .multitrack, mixdown: true)
        .frame(width: 600, height: 860)
}

