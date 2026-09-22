import SwiftUI
import AVFoundation

/// Batch file list, organized into timecode-adjacent groups of equal channel
/// count. Selecting a row selects its group for configuration.
struct FileListView: View {
    var viewModel: AppViewModel
    var isEnabled: Bool

    @State private var isDropTargeted = false
    @State private var collapsedGroupIDs: Set<UUID> = []

    /// True when every group is collapsed
    private var allCollapsed: Bool {
        !viewModel.groups.isEmpty && viewModel.groups.allSatisfy { collapsedGroupIDs.contains($0.id) }
    }

    var body: some View {
        Group {
            if viewModel.batchFiles.isEmpty {
                dropZone
            } else if viewModel.mode == .standard {
                // Standard mode processes whole files, so there is nothing to group
                flatList
            } else {
                groupedList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Both bars float above the scroll view on blurred material, so rows
        // stay visible — blurred — while they scroll underneath.
        .safeAreaInset(edge: .top, spacing: 0) {
            if !viewModel.batchFiles.isEmpty {
                headerBar
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footerBar
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: 2)
                .padding(2)
                .opacity(isDropTargeted ? 1 : 0)
        )
        // All dropped URLs arrive in one call, so a folder plus files becomes
        // a single batch update instead of one per item
        .dropDestination(for: URL.self) { urls, _ in
            guard isEnabled else { return false }
            viewModel.addFiles(urls)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
    }

    /// Title bar floating on blurred material above the scrolling list
    private var headerBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Files")
                    .font(.largeTitle.weight(.bold))

                Spacer()

                // Nothing to collapse in Standard mode — the list is flat
                if viewModel.mode == .mixPreparation {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if allCollapsed {
                                collapsedGroupIDs.removeAll()
                            } else {
                                collapsedGroupIDs = Set(viewModel.groups.map(\.id))
                            }
                        }
                    } label: {
                        Image(systemName: allCollapsed
                              ? "rectangle.expand.vertical"
                              : "rectangle.compress.vertical")
                    }
                    .buttonStyle(.borderless)
                    .help(allCollapsed ? "Expand all groups" : "Collapse all groups")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)

            Divider()
        }
        .background(.ultraThinMaterial)
    }

    private var dropZone: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.down.doc")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(viewModel.mode == .mixPreparation
                 ? "Drop WAV files or folders here"
                 : "Drop audio files or folders here")
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

    /// A ScrollView with pinned section headers rather than a `List`: macOS
    /// list headers paint their own opaque backing and separators, which
    /// prevents rows from scrolling behind the translucent glass bubble.
    private var groupedList: some View {
        ScrollView {
            // One glass layer for all group bubbles
            GlassEffectContainer(spacing: GlassSpacing.chips) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(viewModel.groups) { group in
                        Section {
                            if !collapsedGroupIDs.contains(group.id) {
                                ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                                    fileRowContainer(file)
                                        // The gap to the next group hangs off the
                                        // last row, so collapsed groups sit flush
                                        .padding(.bottom, index == group.files.count - 1 ? 10 : 0)
                                }
                            }
                        } header: {
                            groupHeaderRow(group)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    // Clicking an inactive group makes it the
                                    // configured one by selecting its first take
                                    guard viewModel.selectedGroupID != group.id,
                                          let first = group.files.first else { return }
                                    viewModel.selectFile(first)
                                }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .scrollContentBackground(.hidden)
    }

    /// Plain list of takes for Standard mode
    private var flatList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.batchFiles) { file in
                    fileRowContainer(file)
                }
            }
            .padding(.top, 4)
        }
        .scrollContentBackground(.hidden)
    }

    private func fileRowContainer(_ file: BatchFile) -> some View {
        let isSelected = viewModel.selectedFileID == file.id

        return fileRow(file)
            // Same inner padding as the bubble's content …
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: GroupHeaderBubble.cornerRadius)
                    .fill(isSelected ? Color.accentColor.opacity(0.28) : Color.clear)
            )
            // … and the same outer margin, so rows line up with the bubbles
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.selectFile(file)
            }
    }

    private func groupHeaderRow(_ group: FileGroup) -> some View {
        GroupHeaderBubble(
            timecodeRange: group.timecodeRangeString,
            channelCount: group.channelCount,
            fileCount: group.files.count,
            mode: group.config.productionMode,
            isSelected: viewModel.selectedGroupID == group.id,
            isConfigured: group.config.hasValidJobConfiguration,
            isCollapsed: collapsedGroupIDs.contains(group.id),
            onToggleCollapse: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if collapsedGroupIDs.contains(group.id) {
                        collapsedGroupIDs.remove(group.id)
                    } else {
                        collapsedGroupIDs.insert(group.id)
                    }
                }
            }
        )
        .contextMenu {
            Button("Select Group") {
                if let first = group.files.first { viewModel.selectFile(first) }
            }
            Button(collapsedGroupIDs.contains(group.id) ? "Expand Group" : "Collapse Group") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if collapsedGroupIDs.contains(group.id) {
                        collapsedGroupIDs.remove(group.id)
                    } else {
                        collapsedGroupIDs.insert(group.id)
                    }
                }
            }
            Divider()
            Button("Remove Group", role: .destructive) {
                viewModel.removeGroup(group)
            }
            .disabled(!isEnabled)
        }
    }

    /// Pinned to the bottom of the sidebar
    private var footerBar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 8) {
                Button {
                    openFilePicker()
                } label: {
                    Label("Add Files", systemImage: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .disabled(!isEnabled)

                if viewModel.isLoadingFiles {
                    ProgressView().controlSize(.small)
                }

                Spacer()

                if !viewModel.batchFiles.isEmpty {
                    Text("\(viewModel.batchFiles.count) file\(viewModel.batchFiles.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Button {
                        viewModel.clearFiles()
                    } label: {
                        Text("Clear")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .disabled(!isEnabled)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    private let infoFont = Font.system(size: 11, design: .monospaced)

    /// Compact two-line row: name on top, timecode/format/status below —
    /// fits the narrow sidebar without truncating the important bits.
    private func fileRow(_ file: BatchFile) -> some View {
        HStack(spacing: 8) {
            statusIcon(file)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)

                switch file.status {
                case .processing(let step):
                    HStack(spacing: 6) {
                        ProgressView(value: file.progress)
                            .frame(maxWidth: 70)
                            .controlSize(.small)
                        Text(step)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                case .failed(let message):
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .truncationMode(.tail)
                case .done:
                    Text("\(file.timecodeString) · processed")
                        .font(infoFont)
                        .foregroundStyle(.green)
                        .lineLimit(1)
                case .pending:
                    Text("\(file.timecodeString) · \(file.channelCount)ch · \(file.bitDepth)\(file.isFloat ? "f" : "")bit · \(formatDuration(file.duration))")
                        .font(infoFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)

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
        Group {
            switch file.status {
            case .pending:
                Image(systemName: "waveform")
                    .foregroundStyle(.secondary)
            case .processing:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Color.accentColor)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: 18))
        .frame(width: 22)
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
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.message = viewModel.mode == .mixPreparation
            ? "Choose WAV files or folders of recordings"
            : "Choose audio files or folders of recordings"
        panel.prompt = "Add"
        // Folders must be listed explicitly, otherwise restricting the types
        // to audio lets you browse into folders but never select one.
        panel.allowedContentTypes = AudioFileTypes.openPanelTypes(for: viewModel.mode)

        if panel.runModal() == .OK {
            viewModel.addFiles(panel.urls)
        }
    }
}

// MARK: - Preview

private struct FileListPreviewHost: View {
    @State private var viewModel = AppViewModel()

    /// Short takes with different channel counts so grouping, the pinned
    /// bubbles and the row layout can be checked in the canvas.
    private static func makeSampleFiles() -> [URL] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview_takes", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let takes: [(name: String, channels: Int, seconds: Double)] = [
            ("MixPre-001", 3, 12), ("MixPre-002", 3, 37), ("MixPre-003", 3, 23),
            ("MixPre-004", 4, 121), ("MixPre-005", 4, 45), ("MixPre-006", 2, 25)
        ]

        var urls: [URL] = []
        for (index, take) in takes.enumerated() {
            let url = directory.appendingPathComponent("\(take.name).wav")
            if !FileManager.default.fileExists(atPath: url.path) {
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 48000.0,
                    AVNumberOfChannelsKey: take.channels,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
                guard let file = try? AVAudioFile(forWriting: url, settings: settings),
                      let layout = AVAudioChannelLayout(
                        layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(take.channels)) else { continue }
                let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000,
                                           interleaved: false, channelLayout: layout)
                let frames = AVAudioFrameCount(take.seconds * 48000)
                if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) {
                    buffer.frameLength = frames
                    try? file.write(from: buffer)
                }
            }
            let timeReference = UInt64(48000 * (36_000 + index * 240))
            var bext = Data(count: 602)
            bext.withUnsafeMutableBytes { raw in
                raw.storeBytes(of: UInt32(truncatingIfNeeded: timeReference).littleEndian,
                               toByteOffset: 338, as: UInt32.self)
            }
            _ = WavChunkCopier.writeChunk(to: url, chunkId: "bext", data: bext)
            urls.append(url)
        }
        return urls
    }

    var body: some View {
        FileListView(viewModel: viewModel, isEnabled: true)
            .frame(width: 320, height: 560)
            .task {
                viewModel.addFiles(Self.makeSampleFiles())
            }
    }
}

#Preview("Sidebar with takes") {
    FileListPreviewHost()
}
