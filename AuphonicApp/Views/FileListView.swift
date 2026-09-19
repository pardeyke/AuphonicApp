import SwiftUI
import UniformTypeIdentifiers

/// Batch file list, organized into timecode-adjacent groups of equal channel
/// count. Selecting a row selects its group for configuration.
struct FileListView: View {
    var viewModel: AppViewModel
    var isEnabled: Bool

    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if viewModel.batchFiles.isEmpty {
                    dropZone
                } else {
                    groupedList
                }
            }
            .frame(minHeight: 100, maxHeight: 260)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isDropTargeted ? 2 : 1)
            )
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
                return true
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
    }

    private var dropZone: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.down.doc")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Drop multichannel WAV files or folders here")
                .foregroundStyle(.secondary)
                .font(.caption)
            if viewModel.isLoadingFiles {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEnabled { openFilePicker() }
        }
    }

    private var groupedList: some View {
        List(selection: Binding(
            get: { viewModel.selectedFileID },
            set: { newValue in
                if let id = newValue,
                   let file = viewModel.batchFiles.first(where: { $0.id == id }) {
                    viewModel.selectFile(file)
                }
            }
        )) {
            ForEach(viewModel.groups) { group in
                Section {
                    ForEach(group.files) { file in
                        fileRow(file)
                            .tag(file.id)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                } header: {
                    HStack {
                        Text(group.title)
                            .font(.system(size: 11, weight: .semibold))
                        if viewModel.selectedGroupID == group.id {
                            Text("• configuring")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.accentColor)
                        }
                        Spacer()
                        if !group.config.hasValidJobConfiguration {
                            Text("not configured")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }
                        if isEnabled {
                            Button {
                                viewModel.removeGroup(group)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove this group and its files from the batch")
                        }
                    }
                }
            }

            footerRow
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.vertical, 4)
    }

    private var footerRow: some View {
        HStack {
            Button {
                openFilePicker()
            } label: {
                Label("Add Files", systemImage: "plus")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)

            if viewModel.isLoadingFiles {
                ProgressView().controlSize(.small)
            }

            Spacer()

            Button {
                viewModel.clearFiles()
            } label: {
                Text("Clear All")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        }
    }

    private let infoFont = Font.system(size: 11, design: .monospaced)

    private func fileRow(_ file: BatchFile) -> some View {
        HStack(spacing: 8) {
            statusIcon(file)

            Text(file.url.deletingPathExtension().lastPathComponent)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            switch file.status {
            case .processing(let step):
                Text(step)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: file.progress)
                    .frame(width: 60)
                    .controlSize(.small)
            case .failed(let message):
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 200, alignment: .trailing)
            default:
                Text(file.timecodeString)
                    .font(infoFont)
                    .foregroundStyle(.secondary)

                Text("\(file.channelCount)ch")
                    .font(infoFont)
                    .foregroundStyle(.secondary)

                Text("\(file.bitDepth)\(file.isFloat ? "f" : "")bit")
                    .font(infoFont)
                    .foregroundStyle(.secondary)

                Text(formatDuration(file.duration))
                    .font(infoFont)
                    .foregroundStyle(.secondary)
            }

            if isEnabled {
                Button {
                    viewModel.removeFile(file)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ file: BatchFile) -> some View {
        switch file.status {
        case .pending:
            Image(systemName: "waveform")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .processing:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - File Picker

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "wav")!]

        if panel.runModal() == .OK {
            viewModel.addFiles(panel.urls)
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard isEnabled else { return }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    viewModel.addFiles([url])
                }
            }
        }
    }
}
