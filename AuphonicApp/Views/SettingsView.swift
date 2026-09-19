import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settingsManager: SettingsManager
    var audioPlayer: AudioPlayerService
    var onSave: () -> Void

    @State private var token: String = ""
    @State private var selectedDeviceName: String = ""
    @State private var devices: [AudioPlayerService.AudioDevice] = []
    @State private var deleteProductions = false

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

            // Housekeeping
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Delete productions on Auphonic after download", isOn: $deleteProductions)
                    .font(.system(size: 12))

                Text("Removes each production from your Auphonic account once its audio has been downloaded and written to the output file. Failed files keep their productions.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                    settingsManager.deleteProductionsAfterDownload = deleteProductions

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
        .frame(width: 400, height: 340)
        .onAppear {
            token = settingsManager.apiToken
            selectedDeviceName = settingsManager.audioOutputDevice
            deleteProductions = settingsManager.deleteProductionsAfterDownload
            devices = AudioPlayerService.availableOutputDevices()
        }
    }
}
