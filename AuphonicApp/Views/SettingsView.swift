import SwiftUI

/// Content of the Settings scene. Changes apply immediately, as in a system
/// settings window; the token is committed when the field loses focus or on
/// Return, so a half-typed token never triggers a connection attempt.
struct SettingsView: View {
    @Bindable var settingsManager: SettingsManager
    var audioPlayer: AudioPlayerService
    var onTokenChanged: () -> Void

    @State private var token = ""
    @State private var devices: [AudioPlayerService.AudioDevice] = []
    @FocusState private var tokenFieldFocused: Bool

    var body: some View {
        Form {
            Section("Auphonic Account") {
                SecureField("API Token", text: $token)
                    .focused($tokenFieldFocused)
                    .onSubmit(commitToken)
                    .onChange(of: tokenFieldFocused) { _, focused in
                        if !focused { commitToken() }
                    }

                Link("Get your API token at auphonic.com",
                     destination: URL(string: "https://auphonic.com/accounts/settings#api-key")!)
                    .font(.callout)
            }

            Section("Playback") {
                Picker("Output Device", selection: outputDevice) {
                    Text("System Default").tag("")
                    ForEach(devices) { device in
                        Text(device.name).tag(device.name)
                    }
                }
            }

            Section {
                Toggle("Delete productions on Auphonic after download",
                       isOn: $settingsManager.deleteProductionsAfterDownload)
                Text("Removes each production from your Auphonic account once its audio has been downloaded and written to the output file. Failed files keep their productions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Housekeeping")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear {
            token = settingsManager.apiToken
            devices = AudioPlayerService.availableOutputDevices()
        }
        .onDisappear(perform: commitToken)
    }

    /// Stored device name; "" is the system default. Applied right away.
    private var outputDevice: Binding<String> {
        Binding(
            get: {
                // A stored device that is no longer connected shows as default
                devices.contains { $0.name == settingsManager.audioOutputDevice }
                    ? settingsManager.audioOutputDevice : ""
            },
            set: { name in
                settingsManager.audioOutputDevice = name
                audioPlayer.applyOutputDevice(named: name)
            }
        )
    }

    private func commitToken() {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != settingsManager.apiToken else { return }
        settingsManager.apiToken = trimmed
        onTokenChanged()
    }
}

#Preview("Settings") {
    SettingsView(settingsManager: SettingsManager(), audioPlayer: AudioPlayerService(), onTokenChanged: {})
}
