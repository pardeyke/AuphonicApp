import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settingsManager: SettingsManager
    var audioPlayer: AudioPlayerService
    var onSave: () -> Void

    @State private var token: String = ""
    @State private var selectedDeviceName: String = ""
    @State private var devices: [AudioPlayerService.AudioDevice] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)

            // API Token
            VStack(alignment: .leading, spacing: 4) {
                Text("Auphonic API Token")
                    .font(.system(size: 12, weight: .medium))

                SecureField("Enter API token", text: $token)
                    .textFieldStyle(.roundedBorder)

                Link("Get your API token at auphonic.com",
                     destination: URL(string: "https://auphonic.com/accounts/settings#api-key")!)
                    .font(.system(size: 11))
            }

            // Output Device
            VStack(alignment: .leading, spacing: 4) {
                Text("Audio Output Device")
                    .font(.system(size: 12, weight: .medium))

                Picker("", selection: $selectedDeviceName) {
                    Text("System Default").tag("")
                    ForEach(devices) { device in
                        Text(device.name).tag(device.name)
                    }
                }
                .labelsHidden()
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    settingsManager.apiToken = token
                    settingsManager.audioOutputDevice = selectedDeviceName

                    // Apply output device
                    if let device = devices.first(where: { $0.name == selectedDeviceName }) {
                        audioPlayer.setOutputDevice(device.id)
                    }

                    onSave()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 280)
        .onAppear {
            token = settingsManager.apiToken
            selectedDeviceName = settingsManager.audioOutputDevice
            devices = AudioPlayerService.availableOutputDevices()
        }
    }
}
