 import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

private struct AudioFileInfo {
    var duration: TimeInterval = 0
    var sampleRate: Double = 0
    var bitDepth: Int = 0
    var channels: Int = 0
}

struct FileListView: View {
    @Binding var files: [URL]
    var fileStatuses: [Int: String]
    var isEnabled: Bool

    @State private var isDropTargeted = false
    @State private var fileInfo: [URL: AudioFileInfo] = [:]

    var body: some View {
        VStack(spacing: 0) {
            // File list / drop zone
            Group {
                if files.isEmpty {
                    dropZone
                } else {
                    fileList
                }
            }
            .frame(minHeight: 60, maxHeight: 180)
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
        .onChange(of: files) { _, newFiles in
            loadFileInfo(for: newFiles)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.down.doc")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Drop audio files here")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEnabled { openFilePicker() }
        }
    }

    private var fileList: some View {
        List {
            ForEach(Array(files.enumerated()), id: \.element) { index, file in
                fileRow(file: file, index: index)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowSeparator(.visible)
            }
            .onDelete { offsets in
                if isEnabled { files.remove(atOffsets: offsets) }
            }

            addFilesRow
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.vertical, 4)
    }

    private var addFilesRow: some View {
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

            if files.count > 1 {
                Text("\(files.count) files")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }

            Spacer()

            Button {
                files.removeAll()
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

    private func fileRow(file: URL, index: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text(file.deletingPathExtension().lastPathComponent)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)

            Text(file.pathExtension.uppercased())
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color(nsColor: .separatorColor).opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 3))

            Spacer()

            if let status = fileStatuses[index], !status.isEmpty {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(status.hasPrefix("Error") ? .red : .secondary)
                    .lineLimit(1)
            } else if let info = fileInfo[file] {
                Text("\(info.channels)ch")
                    .font(infoFont)
                    .foregroundStyle(.secondary)

                Text(formatSampleRate(info.sampleRate))
                    .font(infoFont)
                    .foregroundStyle(.secondary)

                Text("\(info.bitDepth)bit")
                    .font(infoFont)
                    .foregroundStyle(.secondary)

                Text(formatDuration(info.duration))
                    .font(infoFont)
                    .foregroundStyle(.secondary)
            }

            if isEnabled {
                Button {
                    files.remove(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - File Info

    private func loadFileInfo(for urls: [URL]) {
        for url in urls where fileInfo[url] == nil {
            Task.detached {
                var info = AudioFileInfo()

                // Duration via AVURLAsset
                let asset = AVURLAsset(url: url)
                if let dur = try? await asset.load(.duration) {
                    info.duration = CMTimeGetSeconds(dur)
                }

                // Sample rate, channels, bit depth via AVAudioFile
                if let file = try? AVAudioFile(forReading: url) {
                    let fmt = file.fileFormat
                    info.sampleRate = fmt.sampleRate
                    info.channels = Int(fmt.channelCount)
                    if let bitDepth = fmt.settings[AVLinearPCMBitDepthKey] as? Int {
                        info.bitDepth = bitDepth
                    } else {
                        // Estimate from bytes per frame for non-PCM or missing key
                        let bitsPerChannel = fmt.streamDescription.pointee.mBitsPerChannel
                        if bitsPerChannel > 0 {
                            info.bitDepth = Int(bitsPerChannel)
                        }
                    }
                }

                await MainActor.run {
                    fileInfo[url] = info
                }
            }
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

    private func formatSampleRate(_ rate: Double) -> String {
        if rate >= 1000 {
            let khz = rate / 1000.0
            if khz == khz.rounded() {
                return String(format: "%.0fkHz", khz)
            }
            return String(format: "%.1fkHz", khz)
        }
        return String(format: "%.0fHz", rate)
    }

    // MARK: - File Picker

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType.audio,
            UTType(filenameExtension: "wav")!,
            UTType(filenameExtension: "aif")!,
            UTType(filenameExtension: "aiff")!,
            UTType(filenameExtension: "flac")!,
            UTType(filenameExtension: "mp3")!,
            UTType(filenameExtension: "m4a")!,
            UTType(filenameExtension: "ogg")!,
            UTType(filenameExtension: "opus")!,
        ]

        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    addFiles([url])
                }
            }
        }
    }

    private func addFiles(_ urls: [URL]) {
        let audioExtensions: Set<String> = ["wav", "aif", "aiff", "flac", "mp3", "m4a", "aac", "ogg", "opus", "alac"]
        for url in urls {
            if audioExtensions.contains(url.pathExtension.lowercased()),
               !files.contains(url) {
                files.append(url)
            }
        }
    }
}
