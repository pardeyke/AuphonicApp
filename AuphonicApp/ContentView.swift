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

            // Preset selector
            PresetListView(
                presets: viewModel.presets,
                selectedUuid: $viewModel.selectedPresetUuid,
                isModified: $viewModel.presetModified,
                onSavePreset: { viewModel.showingSavePreset = true }
            )
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .onChange(of: viewModel.selectedPresetUuid) { _, newValue in
                Task { await viewModel.loadPresetDetails(uuid: newValue) }
                viewModel.saveCurrentConfig()
            }

            // Mode toggle
            HStack(spacing: 8) {
                Button(viewModel.perChannelMode ? "All Channels" : "All Channels") {
                    viewModel.setProcessingMode(false)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(!viewModel.perChannelMode ? Color.accentColor.opacity(0.3) : Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))

                Button("Per Channel") {
                    viewModel.setProcessingMode(true)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(viewModel.perChannelMode ? Color.accentColor.opacity(0.3) : Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .disabled(viewModel.fileChannelCount < 2)

                Spacer()
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .padding(.top, 4)

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

            // Credits + Process button
            HStack(spacing: 12) {
                CreditsView(
                    credits: viewModel.credits,
                    fileDurations: viewModel.calculateFileDurations(),
                    previewDuration: viewModel.previewDuration,
                    channelMultiplier: viewModel.channelMultiplier
                )

                if viewModel.isProcessing {
                    Button("Cancel") {
                        viewModel.cancelProcessing()
                    }
                    .controlSize(.large)
                } else {
                    Button("Process") {
                        viewModel.startProcessing()
                    }
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(viewModel.files.isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

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
        .focusedValue(\.showSettings, $viewModel.showingSettings)
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
