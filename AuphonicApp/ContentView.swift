import SwiftUI

struct ContentView: View {
    @State var viewModel = AppViewModel()
    @State private var sidebarWidth: CGFloat = MainWindowSize.sidebarIdealWidth
    @FocusState private var focused: Bool

    var body: some View {
        NavigationSplitView {
            // Sidebar: the batch, grouped by timecode + channel count
            FileListView(
                viewModel: viewModel,
                isEnabled: !viewModel.isProcessing
            )
            .measuringSidebarWidth()
            .navigationSplitViewColumnWidth(
                min: MainWindowSize.sidebarMinWidth,
                ideal: MainWindowSize.sidebarIdealWidth,
                max: MainWindowSize.sidebarMaxWidth
            )
        } detail: {
            detailPane
        }
        .frame(minHeight: MainWindowSize.minHeight)
        .onPreferenceChange(SidebarWidthKey.self) { width in
            sidebarWidth = width
        }
        .enforcedWindowMinSize(
            width: MainWindowSize.minWidth(sidebarWidth: sidebarWidth),
            height: MainWindowSize.minHeight
        )
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.isProcessing {
                    Button("Cancel") {
                        viewModel.cancelProcessing()
                    }
                    .buttonStyle(.glass)
                } else {
                    Button("Test Settings") {
                        viewModel.testSettings()
                    }
                    .buttonStyle(.glass)
                    .disabled(viewModel.selectedGroup == nil)
                    .help("Process the selected take with this group's settings into a temporary file and load it into the player's Processed lane for A/B comparison. Uploads at most the first 3 minutes per upload (Auphonic's billing minimum), so a test never costs more than the minimum.")

                    Button("Process Batch") {
                        viewModel.startProcessing()
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(viewModel.batchFiles.isEmpty)
                }
            }
        }
        .sheet(isPresented: $viewModel.showingSettings) {
            SettingsView(settingsManager: viewModel.settingsManager, audioPlayer: viewModel.audioPlayer) {
                viewModel.apiClient.token = viewModel.settingsManager.apiToken
                Task { await viewModel.connectAndFetch() }
            }
        }
        .alert("Save Preset", isPresented: $viewModel.showingSavePreset) {
            TextField("Preset name", text: $viewModel.savePresetName)
            Button("Save") {
                let name = viewModel.savePresetName
                viewModel.savePresetName = ""
                Task { await viewModel.savePreset(name: name) }
            }
            Button("Cancel", role: .cancel) {
                viewModel.savePresetName = ""
            }
        }
        .alert("AuphonicApp", isPresented: $viewModel.showingAlert) {
            if viewModel.alertOffersSettings {
                Button("Open Settings…") {
                    viewModel.showingSettings = true
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage)
        }
        .focused($focused)
        .task {
            focused = false
            await viewModel.connectAndFetch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            viewModel.showingSettings = true
        }
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Space bar, not in a text field
                if event.keyCode == 49,
                   !(NSApp.keyWindow?.firstResponder is NSTextView) {
                    if viewModel.audioPlayer.hasOriginal {
                        viewModel.audioPlayer.togglePlayPause()
                        return nil // consume the event
                    }
                }
                return event
            }
        }
    }

    // MARK: - Detail

    private var detailPane: some View {
        VStack(spacing: 0) {
            // Multitrack player for the selected take
            if viewModel.selectedFile != nil {
                MultitrackPlayerView(player: viewModel.audioPlayer)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            // Per-group configuration
            if let group = viewModel.selectedGroup {
                ChannelConfigView(
                    config: group.config,
                    presets: viewModel.presets,
                    onChange: {
                        group.config.presetModified = true
                    },
                    onSavePreset: { viewModel.showingSavePreset = true }
                )
                .id(group.id)
                .onChange(of: group.config.selectedPresetUuid) { _, newValue in
                    Task { await viewModel.loadPresetDetails(uuid: newValue) }
                }
            } else {
                emptyState
            }

            Spacer(minLength: 4)

            CreditsView(
                credits: viewModel.credits,
                estimatedCostSeconds: viewModel.estimatedCostSeconds,
                apiCallCount: viewModel.totalApiCallCount
            )
            .padding(.horizontal, 12)
            .padding(.top, 6)

            StatusView(
                statusText: viewModel.statusText,
                progress: viewModel.progress,
                outputFile: nil,
                outputDirectory: viewModel.outputDirectory
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 560)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "waveform.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Add broadcast WAV files to configure channel processing")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Files are grouped by timecode order and channel count; each group is configured once.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Split layout") {
    ContentView()
        .frame(width: 1080, height: 760)
}
