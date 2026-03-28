import SwiftUI

@Observable
final class ChannelTabsState {
    var channelOptions: [ManualOptionsState] = []
    var channelNames: [String] = []
    var selectedTab = 0

    // Shared output behavior
    var avoidOverwrite = true
    var outputSuffix = "_auphonic"
    var writeSettingsXml = false

    func setChannels(count: Int, trackNames: [String], bitDepth: Int) {
        channelNames = (1...count).map { ch in
            let name: String
            if ch <= trackNames.count && !trackNames[ch - 1].isEmpty {
                name = trackNames[ch - 1]
            } else if count == 2 {
                name = ch == 1 ? "Left" : "Right"
            } else {
                name = ""
            }
            return name.isEmpty ? "Ch \(ch)" : "Ch \(ch) (\(name))"
        }

        channelOptions = (0..<count).map { _ in
            let opts = ManualOptionsState()
            opts.isPerChannelMode = true
            let wavFormat = bitDepth <= 16 ? "wav-16bit" : "wav-24bit"
            opts.forcedOutputFormat = wavFormat
            opts.outputFormatEnabled = true
            opts.outputFormat = bitDepth <= 16 ? .wav16 : .wav24
            return opts
        }

        selectedTab = 0
    }

    func getEnabledChannelSettings() -> [(channel: Int, presetUuid: String, settings: [String: Any])] {
        var result: [(channel: Int, presetUuid: String, settings: [String: Any])] = []
        for (index, opts) in channelOptions.enumerated() {
            if opts.hasAnyEnabled() {
                var settings = opts.getSettings()
                // Force WAV output for per-channel processing
                settings["output_format"] = opts.forcedOutputFormat ?? "wav-24bit"
                settings["output_files"] = [["format": settings["output_format"] ?? "wav-24bit"]]
                result.append((channel: index + 1, presetUuid: "", settings: settings))
            }
        }
        return result
    }

    var enabledChannelCount: Int {
        channelOptions.filter { $0.hasAnyEnabled() }.count
    }

    var hasAnyChannelEnabled: Bool {
        channelOptions.contains { $0.hasAnyEnabled() }
    }
}

struct ChannelTabsView: View {
    @Bindable var state: ChannelTabsState
    var onChange: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(state.channelNames.enumerated()), id: \.offset) { index, name in
                        tabButton(name: name, index: index)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Tab content
            if state.selectedTab < state.channelOptions.count {
                ScrollView {
                    ManualOptionsView(
                        options: state.channelOptions[state.selectedTab],
                        onChange: onChange
                    )
                    .padding(8)
                }
            }

            Divider()

            // Shared output settings
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Create a new file (don't overwrite)", isOn: $state.avoidOverwrite)
                    .font(.system(size: 12))

                if state.avoidOverwrite {
                    HStack {
                        Text("Suffix:")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        TextField("Suffix", text: $state.outputSuffix)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .font(.system(size: 12))
                    }
                    .padding(.leading, 16)
                }

                Toggle("Write settings JSON alongside output", isOn: $state.writeSettingsXml)
                    .font(.system(size: 12))
            }
            .padding(8)
        }
    }

    private func tabButton(name: String, index: Int) -> some View {
        Button {
            state.selectedTab = index
        } label: {
            Text(name)
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    state.selectedTab == index
                        ? Color.accentColor.opacity(0.2)
                        : Color.clear
                )
        }
        .buttonStyle(.plain)
    }
}
