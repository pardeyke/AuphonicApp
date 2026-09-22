import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: AppViewModel
    @State private var sidebarWidth: CGFloat = MainWindowSize.sidebarIdealWidth
    @State private var spaceBarMonitor: Any?
    @Environment(\.openSettings) private var openSettings

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
            ToolbarItem(placement: .principal) {
                TabsPicker(
                    values: AppMode.allCases,
                    titles: AppMode.allCases.map(\.displayName),
                    selection: $viewModel.mode
                )
                .fixedSize()
                .help(viewModel.mode.summary)
            }

            // The toolbar draws the Liquid Glass itself: adjacent items share
            // one capsule, a fixed spacer splits them into groups, and the
            // prominent style marks the primary action. The buttons carry no
            // glass style of their own.
            if viewModel.isProcessing {
                ToolbarItem(placement: .primaryAction) {
                    Button("Cancel") {
                        viewModel.cancelProcessing()
                    }
                }
            } else {
                // Test Settings and Process act on the selected take and share
                // a capsule. Overflow order as the window shrinks: Test
                // Settings goes first, then Process Batch; Process stays
                // visible longest.
                ToolbarItem(placement: .primaryAction) {
                    Button("Test Settings") {
                        viewModel.testSettings()
                    }
                    .disabled(viewModel.mode == .standard ? viewModel.batchFiles.isEmpty : viewModel.selectedGroup == nil)
                    .help("Process the selected take with this group's settings into a temporary file and load it into the player's Processed lane for A/B comparison. Uploads at most the first 3 minutes per upload (Auphonic's billing minimum), so a test never costs more than the minimum.")
                }
                .visibilityPriority(.low)

                ToolbarItem(placement: .primaryAction) {
                    Button("Process") {
                        viewModel.processSelectedFile()
                    }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(viewModel.selectedFile == nil)
                    .help("Run the selected take on its own, with the same settings and output folder as the batch.")
                }
                .visibilityPriority(.high)

                ToolbarSpacer(.fixed, placement: .primaryAction)

                ToolbarItem(placement: .primaryAction) {
                    Button("Process Batch") {
                        viewModel.startProcessing()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(viewModel.batchFiles.isEmpty)
                }
                .visibilityPriority(.automatic)
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
                    openSettings()
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage)
        }
        .clearingInitialFocus()
        .task {
            await viewModel.connectAndFetch()
        }
        .onAppear {
            guard spaceBarMonitor == nil else { return }
            spaceBarMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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
        .onDisappear {
            if let spaceBarMonitor {
                NSEvent.removeMonitor(spaceBarMonitor)
                self.spaceBarMonitor = nil
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

            settingsPane

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

    /// Standard mode configures the whole batch at once; Mix Preparation configures
    /// the selected group
    @ViewBuilder
    private var settingsPane: some View {
        switch viewModel.mode {
        case .standard:
            StandardModeView(
                config: viewModel.standardConfig,
                presets: viewModel.presets,
                fileCount: viewModel.batchFiles.count,
                onChange: { viewModel.standardConfig.presetModified = true },
                onSavePreset: { viewModel.showingSavePreset = true }
            )
            .onChange(of: viewModel.standardConfig.selectedPresetUuid) { _, newValue in
                Task { await viewModel.loadPresetDetails(uuid: newValue) }
            }

        case .mixPreparation:
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
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "waveform.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Add audio files to configure channel processing")
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
    ContentView(viewModel: AppViewModel())
        .frame(width: 1080, height: 760)
}
