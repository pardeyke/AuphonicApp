import SwiftUI
import AVFoundation

@Observable
final class AppViewModel {
    // Services
    let settingsManager = SettingsManager()
    let apiClient = AuphonicAPIClient()
    let audioPlayer = AudioPlayerService()

    // State
    var files: [URL] = []
    var selectedFileIndex: Int?
    var presets: [AuphonicPreset] = []
    var credits: UserCredits?
    var showingSettings = false
    var showingSavePreset = false
    var savePresetName = ""
    var alertMessage = ""
    var showingAlert = false

    // Manual options (mono file mode)
    let manualOptions = ManualOptionsState()

    // Channel config (multi-channel mode)
    let channelConfig = ChannelConfig()

    // Preset state (for mono mode)
    var selectedPresetUuid = ""
    var presetModified = false

    // Processing
    private var workflow: ProcessingWorkflow?
    var isProcessing: Bool { workflow?.state.isActive ?? false }

    // File info (for selected file)
    var fileChannelCount = 0
    var fileDuration: Double = 0
    var trackNames: [String] = []
    var fileBitDepth = 0

    // Status
    var statusText = "Ready"
    var progress: Double = -1
    var outputFile: URL?
    var outputDirectory: URL?

    var selectedFile: URL? {
        guard let idx = selectedFileIndex, idx >= 0, idx < files.count else { return nil }
        return files[idx]
    }

    var previewDuration: Double {
        if fileChannelCount <= 2 {
            return manualOptions.effectivePreviewDuration
        }
        if channelConfig.isWholeFileMode {
            return channelConfig.sharedOptions.effectivePreviewDuration
        }
        return 0
    }

    init() {
        apiClient.token = settingsManager.apiToken
        restoreLastConfig()
    }

    // MARK: - Connection

    func connectAndFetch() async {
        guard settingsManager.hasApiToken else { return }
        apiClient.token = settingsManager.apiToken

        do {
            credits = try await apiClient.fetchUserInfo()
            presets = try await apiClient.fetchPresets()
        } catch {
            showAlert("Connection failed: \(error.localizedDescription)")
        }
    }

    func refreshCredits() async {
        do {
            credits = try await apiClient.fetchUserInfo()
        } catch {
            // Silent refresh failure
        }
    }

    // MARK: - Files

    func updateFileInfo() {
        // Reset processing state when files change
        statusText = "Ready"
        progress = -1
        outputFile = nil
        outputDirectory = nil
        audioPlayer.clearProcessed()

        // Auto-select first file if nothing selected
        if selectedFileIndex == nil && !files.isEmpty {
            selectedFileIndex = 0
        }

        // Clamp selection to valid range
        if let idx = selectedFileIndex {
            if files.isEmpty {
                selectedFileIndex = nil
            } else if idx >= files.count {
                selectedFileIndex = files.count - 1
            }
        }

        loadSelectedFile()
    }

    func selectFile(at index: Int) {
        guard index >= 0, index < files.count else { return }
        selectedFileIndex = index
        loadSelectedFile()
    }

    private func loadSelectedFile() {
        guard let file = selectedFile else {
            fileChannelCount = 0
            fileDuration = 0
            trackNames = []
            fileBitDepth = 0
            manualOptions.fileDuration = 0
            audioPlayer.stop()
            return
        }

        do {
            let audioFile = try AVAudioFile(forReading: file)
            fileChannelCount = Int(audioFile.processingFormat.channelCount)
            fileDuration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            trackNames = WavChunkCopier.readIxmlTrackNames(from: file)
            fileBitDepth = WavChunkCopier.readWavBitDepth(from: file)

            // Remove index 0 (unused) from track names if present
            if !trackNames.isEmpty {
                trackNames.removeFirst()
            }

            manualOptions.fileDuration = fileDuration

            // Configure channel config for multi-channel files
            if fileChannelCount >= 3 {
                channelConfig.configure(
                    count: fileChannelCount,
                    trackNames: trackNames,
                    bitDepth: fileBitDepth > 0 ? fileBitDepth : 24
                )
                channelConfig.sharedOptions.fileDuration = fileDuration
            }

            audioPlayer.loadOriginal(url: file)
        } catch {
            fileChannelCount = 0
            fileDuration = 0
        }
    }

    // MARK: - Process

    func startProcessing() {
        guard let file = selectedFile else {
            showAlert("Please select an audio file first.")
            return
        }
        guard settingsManager.hasApiToken else {
            showAlert("Please enter your API token in Settings.")
            return
        }

        // Prompt for output folder
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose output folder for processed file"
        panel.prompt = "Select"

        guard panel.runModal() == .OK, let outputDir = panel.url else { return }

        if fileChannelCount <= 2 {
            startMonoProcessing(file: file, outputDir: outputDir)
        } else {
            startChannelProcessing(file: file, outputDir: outputDir)
        }
    }

    private func startMonoProcessing(file: URL, outputDir: URL) {
        let effectivePresetUuid = presetModified ? "" : selectedPresetUuid
        let settings = manualOptions.getSettings()

        guard !effectivePresetUuid.isEmpty || manualOptions.hasAnyEnabled() else {
            showAlert("Please select a preset or enable processing options.")
            return
        }

        statusText = "Starting..."
        progress = 0
        outputFile = nil
        outputDirectory = nil

        let wf = ProcessingWorkflow(apiClient: apiClient)
        wf.setOutputDirectory(outputDir)
        workflow = wf

        wf.start(
            inputFile: file,
            presetUuid: effectivePresetUuid,
            manualSettings: settings,
            avoidOverwrite: manualOptions.avoidOverwrite,
            outputSuffix: manualOptions.outputSuffix,
            writeSettingsXml: manualOptions.writeSettingsXml,
            previewDuration: previewDuration,
            keepTimecode: manualOptions.keepTimecode
        )

        monitorWorkflow(wf)
    }

    private func startChannelProcessing(file: URL, outputDir: URL) {
        let jobs = channelConfig.processingJobs

        guard !jobs.isEmpty else {
            showAlert("Please enable at least one channel for processing.")
            return
        }

        // For channel processing, use the first job (single-file, no batch)
        let job = jobs.first!
        let settings = channelConfig.settingsForJob(job)
        let presetUuid = channelConfig.presetUuidForJob(job)

        // Validate settings
        if channelConfig.isWholeFileMode {
            guard !presetUuid.isEmpty || channelConfig.sharedOptions.hasAnyEnabled() else {
                showAlert("Please select a preset or enable processing options.")
                return
            }
        } else {
            let hasSettings: Bool
            if channelConfig.linkedSettings {
                let pUuid = channelConfig.presetModified ? "" : channelConfig.selectedPresetUuid
                hasSettings = !pUuid.isEmpty || channelConfig.sharedOptions.hasAnyEnabled()
            } else {
                hasSettings = channelConfig.optionsForJob(job).hasAnyEnabled()
            }
            guard hasSettings else {
                showAlert("Please select a preset or enable processing options.")
                return
            }
        }

        statusText = "Starting..."
        progress = 0
        outputFile = nil
        outputDirectory = nil

        let wf = ProcessingWorkflow(apiClient: apiClient)
        wf.setOutputDirectory(outputDir)
        workflow = wf

        wf.start(
            inputFile: file,
            presetUuid: presetUuid,
            manualSettings: settings,
            avoidOverwrite: channelConfig.avoidOverwrite,
            outputSuffix: channelConfig.outputSuffix,
            writeSettingsXml: channelConfig.writeSettingsXml,
            channelsToExtract: job.channelIndices,
            previewDuration: previewDuration,
            keepTimecode: channelConfig.keepTimecode
        )

        monitorWorkflow(wf)
    }

    private func monitorWorkflow(_ wf: ProcessingWorkflow) {
        Task { @MainActor in
            while wf.state.isActive {
                statusText = wf.statusText.isEmpty ? "Processing..." : wf.statusText
                progress = wf.progress
                try? await Task.sleep(for: .milliseconds(250))
            }

            // Completion
            statusText = wf.statusText
            progress = -1

            if let output = wf.lastOutputFile {
                outputFile = output
                outputDirectory = output.deletingLastPathComponent()
                audioPlayer.loadProcessed(url: output)
            }

            // Desktop notification
            let success = wf.state == .done
            let title = success ? "Processing Complete" : "Processing Failed"
            let body = success ? "File processed successfully" : wf.statusText
            NotificationService.show(title: title, body: body)

            // Refresh credits
            await refreshCredits()
        }
    }

    func cancelProcessing() {
        workflow?.cancel()
        statusText = "Cancelled"
        progress = -1
    }

    // MARK: - Presets

    func loadPresetDetails(uuid: String) async {
        guard !uuid.isEmpty else { return }

        do {
            let details = try await apiClient.fetchPresetDetails(uuid: uuid)
            if let algorithms = details["algorithms"] as? [String: Any] {
                await MainActor.run {
                    // Apply to the active options state
                    if fileChannelCount <= 2 {
                        manualOptions.applyApiSettings(algorithms)
                        presetModified = false
                    } else {
                        channelConfig.sharedOptions.applyApiSettings(algorithms)
                        channelConfig.presetModified = false
                    }
                }
            }
        } catch {
            // Silent preset load failure
        }
    }

    func savePreset(name: String) async {
        let settings: [String: Any]
        if fileChannelCount <= 2 {
            settings = manualOptions.getSettings()
        } else {
            settings = channelConfig.sharedOptions.getSettings()
        }

        do {
            let uuid = try await apiClient.savePreset(name: name, settings: settings)
            presets = try await apiClient.fetchPresets()
            await MainActor.run {
                if fileChannelCount <= 2 {
                    selectedPresetUuid = uuid
                    presetModified = false
                } else {
                    channelConfig.selectedPresetUuid = uuid
                    channelConfig.presetModified = false
                }
            }
        } catch {
            showAlert("Failed to save preset: \(error.localizedDescription)")
        }
    }

    // MARK: - Persistence

    func saveCurrentConfig() {
        if let jsonData = try? JSONSerialization.data(withJSONObject: manualOptions.getWidgetState()),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            settingsManager.lastManualSettings = jsonString
        }
        settingsManager.lastPresetUuid = selectedPresetUuid
    }

    private func restoreLastConfig() {
        let savedSettings = settingsManager.lastManualSettings
        if !savedSettings.isEmpty,
           let data = savedSettings.data(using: .utf8),
           let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            manualOptions.applyWidgetState(state)
        }

        selectedPresetUuid = settingsManager.lastPresetUuid
    }

    // MARK: - Alert

    func showAlert(_ message: String) {
        alertMessage = message
        showingAlert = true
    }

    // MARK: - Computed

    var apiCallCount: Int {
        if fileChannelCount <= 2 { return 1 }
        return channelConfig.apiCallCount
    }
}
