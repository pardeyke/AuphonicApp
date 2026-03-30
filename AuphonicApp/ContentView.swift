import SwiftUI

struct ContentView: View {
    @State var viewModel = AppViewModel()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // File list
            FileListView(
                files: $viewModel.files,
                selectedIndex: $viewModel.selectedFileIndex,
                isEnabled: !viewModel.isProcessing
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .onChange(of: viewModel.files) {
                viewModel.updateFileInfo()
                viewModel.saveCurrentConfig()
            }
            .onChange(of: viewModel.selectedFileIndex) {
                viewModel.selectFile(at: viewModel.selectedFileIndex ?? -1)
            }

            // Audio player (when a file is selected)
            if viewModel.selectedFile != nil {
                AudioPlayerView(player: viewModel.audioPlayer)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }

            // Main options area
            if viewModel.fileChannelCount <= 1 {
                // Mono file (or no file): simple preset + options
                ScrollView {
                    PresetListView(
                        presets: viewModel.presets,
                        selectedUuid: $viewModel.selectedPresetUuid,
                        isModified: $viewModel.presetModified,
                        onSavePreset: { viewModel.showingSavePreset = true }
                    )
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    .onChange(of: viewModel.selectedPresetUuid) { _, newValue in
                        Task { await viewModel.loadPresetDetails(uuid: newValue) }
                        viewModel.saveCurrentConfig()
                    }

                    ManualOptionsView(
                        options: viewModel.manualOptions,
                        onChange: {
                            viewModel.presetModified = true
                            viewModel.saveCurrentConfig()
                        }
                    )
                    .padding(4)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            } else {
                // Multi-channel file: unified channel config
                ChannelConfigView(
                    config: viewModel.channelConfig,
                    presets: viewModel.presets,
                    onChange: {
                        viewModel.channelConfig.presetModified = true
                        viewModel.saveCurrentConfig()
                    },
                    onSavePreset: { viewModel.showingSavePreset = true }
                )
                .onChange(of: viewModel.channelConfig.selectedPresetUuid) { _, newValue in
                    Task { await viewModel.loadPresetDetails(uuid: newValue) }
                    viewModel.saveCurrentConfig()
                }
            }

            Spacer(minLength: 4)

            // Credits
            CreditsView(
                credits: viewModel.credits,
                fileDuration: viewModel.fileDuration,
                previewDuration: viewModel.previewDuration,
                apiCallCount: viewModel.apiCallCount
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
                Button("Process") {
                    viewModel.startProcessing()
                }
                .controlSize(.extraLarge)
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(viewModel.selectedFile == nil)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }

            // Status bar
            StatusView(
                statusText: viewModel.statusText,
                progress: viewModel.progress,
                outputFile: viewModel.outputFile,
                outputDirectory: viewModel.outputDirectory
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 480, maxWidth: 800, minHeight: 500, maxHeight: 1200)
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
