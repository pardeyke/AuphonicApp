import SwiftUI

struct ContentView: View {
    @State var viewModel = AppViewModel()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // File list
            FileListView(
                files: $viewModel.files,
                fileStatuses: viewModel.batchWorkflow?.fileStatuses ?? [:],
                isEnabled: !viewModel.isProcessing
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .onChange(of: viewModel.files) {
                viewModel.updateFileInfo()
                viewModel.saveCurrentConfig()
            }

            // Channel warning
            if !viewModel.channelWarning.isEmpty {
                Text(viewModel.channelWarning)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
            }

            // Audio player (single file only)
            if viewModel.files.count == 1 {
                AudioPlayerView(player: viewModel.audioPlayer)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }

            // Mode toggle
            Picker("", selection: Binding(
                get: { viewModel.perChannelMode },
                set: { viewModel.setProcessingMode($0) }
            )) {
                Text("All Channels").tag(false)
                Text("Per Channel").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.fileChannelCount < 2)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Main options area
            if viewModel.perChannelMode {
                ChannelTabsView(
                    state: viewModel.channelTabs,
                    onChange: {
                        viewModel.presetModified = true
                        viewModel.saveCurrentConfig()
                    }
                )
                .padding(.horizontal, 12)
                .padding(.top, 4)
            } else {
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
            }

            Spacer(minLength: 4)

            // Credits
            CreditsView(
                credits: viewModel.credits,
                fileDurations: viewModel.calculateFileDurations(),
                previewDuration: viewModel.previewDuration,
                channelMultiplier: viewModel.channelMultiplier
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
                .disabled(viewModel.files.isEmpty)
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
