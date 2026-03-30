import SwiftUI

struct ChannelConfigView: View {
    @Bindable var config: ChannelConfig
    var presets: [AuphonicPreset]
    var onChange: (() -> Void)?
    var onSavePreset: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Stereo / Multi-Mono toggle (only for 2-channel files)
            if config.showsModeToggle {
                Picker("", selection: Binding(
                    get: { config.stereoMode },
                    set: { newValue in
                        config.stereoMode = newValue
                        onChange?()
                    }
                )) {
                    Text("Stereo").tag(true)
                    Text("Multi-Mono").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            if config.isWholeFileMode {
                // Stereo or mono: single preset + options
                ScrollView {
                    PresetListView(
                        presets: presets,
                        selectedUuid: $config.selectedPresetUuid,
                        isModified: $config.presetModified,
                        onSavePreset: { onSavePreset?() }
                    )
                    .padding(.horizontal, 4)
                    .padding(.top, 4)

                    ManualOptionsView(
                        options: config.sharedOptions,
                        onChange: onChange
                    )
                    .padding(4)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            } else {
                // Multi-mono mode: channel list + settings
                channelListSection
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                settingsToggles
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                ScrollView {
                    // Preset (applies when linked)
                    if config.linkedSettings {
                        PresetListView(
                            presets: presets,
                            selectedUuid: $config.selectedPresetUuid,
                            isModified: $config.presetModified,
                            onSavePreset: { onSavePreset?() }
                        )
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                    }

                    settingsContent
                        .padding(4)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Channel List

    private var channelListSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(config.channels) { channel in
                channelRow(channel)
            }

            HStack {
                Button(config.allSelected ? "Deselect All" : "Select All") {
                    if config.allSelected {
                        config.deselectAll()
                    } else {
                        config.selectAll()
                    }
                    onChange?()
                }
                .font(.system(size: 11))
                .buttonStyle(.borderless)

                Spacer()
            }
            .padding(.top, 2)
        }
    }

    private func channelRow(_ channel: ChannelEntry) -> some View {
        HStack(spacing: 6) {
            Toggle("", isOn: Binding(
                get: { channel.enabled },
                set: { newValue in
                    channel.enabled = newValue
                    // Sync paired channel
                    if let partner = channel.stereoPairPartner,
                       partner < config.channels.count {
                        config.channels[partner].enabled = newValue
                    }
                    onChange?()
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Text(channel.displayName)
                .font(.system(size: 12))
                .foregroundStyle(channel.enabled ? .primary : .secondary)

            Spacer()

            if let partner = channel.stereoPairPartner {
                // Show paired status
                let partnerName = partner < config.channels.count
                    ? config.channels[partner].displayName : "Ch \(partner + 1)"
                Text("⟷ \(partnerName)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button("Unlink") {
                    config.unlinkStereo(ch: channel.id)
                    onChange?()
                }
                .font(.system(size: 11))
                .buttonStyle(.borderless)
            } else if channel.enabled {
                // Show link stereo menu
                let partners = config.availableStereoPartners(for: channel.id)
                if !partners.isEmpty {
                    Menu("Link Stereo") {
                        ForEach(partners) { partner in
                            Button(partner.displayName) {
                                config.linkStereo(ch1: channel.id, ch2: partner.id)
                                onChange?()
                            }
                        }
                    }
                    .font(.system(size: 11))
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Settings Toggles

    private var settingsToggles: some View {
        HStack(spacing: 16) {
            Toggle("Link settings", isOn: Binding(
                get: { config.linkedSettings },
                set: { newValue in
                    config.linkedSettings = newValue
                    onChange?()
                }
            ))
            .font(.system(size: 12))
            .toggleStyle(.checkbox)

            if config.mergeAvailable {
                Toggle("Merge output", isOn: Binding(
                    get: { config.mergeOutput },
                    set: { newValue in
                        config.mergeOutput = newValue
                        // Update forced output format on channels
                        if newValue {
                            for ch in config.channels {
                                let wavFormat = config.bitDepth <= 16 ? "wav-16bit" : "wav-24bit"
                                ch.options.forcedOutputFormat = wavFormat
                                ch.options.outputFormat = config.bitDepth <= 16 ? .wav16 : .wav24
                            }
                            let wavFormat = config.bitDepth <= 16 ? "wav-16bit" : "wav-24bit"
                            config.sharedOptions.forcedOutputFormat = wavFormat
                            config.sharedOptions.outputFormat = config.bitDepth <= 16 ? .wav16 : .wav24
                        } else {
                            for ch in config.channels {
                                ch.options.forcedOutputFormat = nil
                            }
                            config.sharedOptions.forcedOutputFormat = nil
                        }
                        onChange?()
                    }
                ))
                .font(.system(size: 12))
                .toggleStyle(.checkbox)
            }

            Spacer()
        }
    }

    // MARK: - Settings Content

    @State private var selectedSettingsTab: Int = 0

    @ViewBuilder
    private var settingsContent: some View {
        if config.linkedSettings {
            // Single shared settings
            ManualOptionsView(
                options: config.sharedOptions,
                onChange: onChange
            )
        } else {
            // Per-channel tabs
            let enabledChannels = config.channels.filter(\.enabled)
            if !enabledChannels.isEmpty {
                VStack(spacing: 0) {
                    // Tab bar
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(enabledChannels) { channel in
                                tabButton(channel: channel)
                            }
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))

                    Divider()

                    // Tab content
                    let tabChannel = enabledChannels.first(where: { $0.id == selectedSettingsTab })
                        ?? enabledChannels.first
                    if let ch = tabChannel {
                        ManualOptionsView(
                            options: ch.options,
                            onChange: onChange
                        )
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    private func tabButton(channel: ChannelEntry) -> some View {
        Button {
            selectedSettingsTab = channel.id
        } label: {
            Text(channel.displayName)
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    selectedSettingsTab == channel.id
                        ? Color.accentColor.opacity(0.2)
                        : Color.clear
                )
        }
        .buttonStyle(.plain)
    }
}
