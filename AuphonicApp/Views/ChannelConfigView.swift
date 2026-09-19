import SwiftUI

/// Configuration UI for one file group: which channels to process, how they
/// are paired/packed into uploads, and the Auphonic settings.
struct ChannelConfigView: View {
    @Bindable var config: ChannelConfig
    var presets: [AuphonicPreset]
    var onChange: (() -> Void)?
    var onSavePreset: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            channelListSection
                .padding(.horizontal, 12)
                .padding(.top, 8)

            settingsToggles
                .padding(.horizontal, 12)
                .padding(.top, 6)

            uploadPlanSection
                .padding(.horizontal, 12)
                .padding(.top, 4)

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

            Toggle("Pack mono channels into stereo uploads", isOn: Binding(
                get: { config.packMonoChannels },
                set: { newValue in
                    config.packMonoChannels = newValue
                    onChange?()
                }
            ))
            .font(.system(size: 12))
            .toggleStyle(.checkbox)
            .help("Auphonic bills per minute regardless of channel count, so two mono channels sharing one stereo upload cost half. Disable if processing of one channel audibly affects the other.")

            Toggle("Settings JSON", isOn: Binding(
                get: { config.writeSettingsXml },
                set: { config.writeSettingsXml = $0 }
            ))
            .font(.system(size: 12))
            .toggleStyle(.checkbox)
            .help("Write the used Auphonic settings as a JSON file next to each output")

            Spacer()
        }
    }

    // MARK: - Upload Plan

    private var uploadPlanSection: some View {
        HStack {
            let jobs = config.uploadJobs
            Text(jobs.isEmpty
                 ? "No channels selected"
                 : "Uploads per file: " + jobs.map(\.label).joined(separator: ", "))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
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
