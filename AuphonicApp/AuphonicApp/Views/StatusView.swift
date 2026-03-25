import SwiftUI
import AppKit

struct StatusView: View {
    var statusText: String
    var progress: Double            // 0-1 visible, < 0 hidden
    var outputFile: URL?
    var outputDirectory: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Status: \(statusText)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer()

                if let file = outputFile {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([file])
                    }
                    .font(.system(size: 11))
                } else if let dir = outputDirectory {
                    Button("Show in Finder") {
                        NSWorkspace.shared.open(dir)
                    }
                    .font(.system(size: 11))
                }
            }

            if progress >= 0 {
                ProgressView(value: max(0, min(1, progress)))
                    .progressViewStyle(.linear)
            }
        }
    }
}
