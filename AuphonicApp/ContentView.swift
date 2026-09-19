import SwiftUI

struct ContentView: View {
    @State var viewModel = AppViewModel()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Grouped batch file list
            FileListView(
                viewModel: viewModel,
                isEnabled: !viewModel.isProcessing
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Audio player (when a file is selected)
            if viewModel.selectedFile != nil {
                AudioPlayerView(player: viewModel.audioPlayer)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }

            // Per-group channel configuration
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
                VStack(spacing: 6) {
                    Spacer()
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

            Spacer(minLength: 4)

            // Credits with batch cost estimate
            CreditsView(
                credits: viewModel.credits,
                estimatedCostSeconds: viewModel.estimatedCostSeconds,
                apiCallCount: viewModel.totalApiCallCount
            )
            .padding(.horizontal, 12)
            .padding(.top, 6)

            // Process button
            if viewModel.isProcessing {
                Button("Cancel") {
                    viewModel.cancelProcessing()
                }
                .controlSize(.extraLarge)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            } else {
                HStack(spacing: 10) {
                    Button("Test Settings") {
                        viewModel.testSettings()
                    }
                    .controlSize(.extraLarge)
                    .disabled(viewModel.selectedGroup == nil)
                    .help("Process the selected take with this group's settings into a temporary file and load it into the player's Processed lane for A/B comparison. Uploads at most the first 3 minutes per upload (Auphonic's billing minimum), so a test never costs more than the minimum.")

                    Button("Process Batch") {
                        viewModel.startProcessing()
                    }
                    .controlSize(.extraLarge)
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(viewModel.batchFiles.isEmpty)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }

            // Status bar
            StatusView(
                statusText: viewModel.statusText,
                progress: viewModel.progress,
                outputFile: nil,
                outputDirectory: viewModel.outputDirectory
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 520, maxWidth: 900, minHeight: 560, maxHeight: 1200)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.showingSettings = true
                } label: {
                    Image(systemName: "gear")
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
}
