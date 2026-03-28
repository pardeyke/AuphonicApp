import SwiftUI

struct PresetListView: View {
    var presets: [AuphonicPreset]
    @Binding var selectedUuid: String
    @Binding var isModified: Bool
    var onSavePreset: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("Preset", selection: $selectedUuid) {
                Text("(No preset)").tag("")

                ForEach(presets) { preset in
                    Text(preset.name).tag(preset.uuid)
                }
            }
            .labelsHidden()
            .onChange(of: selectedUuid) {
                isModified = false
            }

            if isModified {
                Text("(modified)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Save Preset") {
                onSavePreset()
            }
        }
    }

    var selectedPresetName: String {
        if selectedUuid.isEmpty { return "" }
        return presets.first { $0.uuid == selectedUuid }?.name ?? ""
    }

    /// Returns UUID only if preset is not modified
    var effectivePresetUuid: String {
        isModified ? "" : selectedUuid
    }
}
