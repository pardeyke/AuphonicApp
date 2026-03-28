import SwiftUI

struct PreviewDurationView: View {
    @Binding var selectedDuration: Double
    var fileDuration: Double
    var forceFullDuration: Bool

    private let presets: [(String, Double)] = [
        ("Full", 0), ("30s", 30), ("1m", 60),
        ("3m", 180), ("5m", 300), ("10m", 600)
    ]

    var body: some View {
        HStack(spacing: 4) {
            Text("Preview:")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            ForEach(presets, id: \.1) { label, duration in
                if duration == 0 || (fileDuration > 0 && duration < fileDuration) {
                    Button(label) {
                        selectedDuration = duration
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        selectedDuration == duration
                            ? Color.accentColor.opacity(0.3)
                            : Color(nsColor: .controlBackgroundColor)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .disabled(forceFullDuration)
                }
            }
        }
    }
}
