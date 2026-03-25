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
    var presets: [AuphonicPreset] = []
    var credits: UserCredits?
    var selectedPresetUuid = ""
    var presetModified = false
    var previewDuration: Double { manualOptions.effectivePreviewDuration }
    var perChannelMode = false
    var showingSettings = false
    var showingSavePreset = false
    var savePresetName = ""
    var alertMessage = ""
    var showingAlert = false
    var channelWarning = ""

    // Manual options (whole-file mode)
    let manualOptions = ManualOptionsState()

    // Channel tabs (per-channel mode)
    let channelTabs = ChannelTabsState()

    // Processing
    private(set) var batchWorkflow: BatchWorkflow?
    var isProcessing: Bool { batchWorkflow?.isRunning ?? false }

    // File info
    var fileChannelCount = 0
    var fileDuration: Double = 0
    var trackNames: [String] = []
    var fileBitDepth = 0

    // Status
    var statusText = "Ready"
    var progress: Double = -1
    var outputFile: URL?
    var outputDirectory: URL?

    init() {
        apiClient.token = settingsManager.apiToken
        perChannelMode = settingsManager.perChannelMode
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
        guard let file = files.first else {
            fileChannelCount = 0
            fileDuration = 0
            trackNames = []
            fileBitDepth = 0
            channelWarning = ""
            manualOptions.fileDuration = 0
            manualOptions.fileCount = 0
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

            manualOptions.channelCount = fileChannelCount
            manualOptions.trackNames = trackNames
            manualOptions.fileDuration = fileDuration
            manualOptions.fileCount = files.count

            // Channel warning for 3+ channels
            if fileChannelCount >= 3 {
                channelWarning = "Multi-channel file (\(fileChannelCount)ch): Auphonic only support mono/stereo processing. Use Per Channel mode or select 1+2 / individual channels."
                // Default to L+R for 3+ channel files
                if manualOptions.selectedChannel == 0 {
                    manualOptions.selectedChannel = -1
                }
            } else {
                channelWarning = ""
            }

            // Load into audio player (single file only)
            if files.count == 1 {
                audioPlayer.loadOriginal(url: file)
            } else {
                audioPlayer.stop()
            }

            // Update channel tabs if in per-channel mode
            if perChannelMode {
                channelTabs.setChannels(count: fileChannelCount, trackNames: trackNames, bitDepth: fileBitDepth > 0 ? fileBitDepth : 24)
            }
        } catch {
            fileChannelCount = 0
            fileDuration = 0
        }
    }

    func calculateTotalDuration() -> Double {
        if files.count <= 1 { return fileDuration }
        return calculateFileDurations().reduce(0, +)
    }

    func calculateFileDurations() -> [Double] {
        if files.count <= 1 { return fileDuration > 0 ? [fileDuration] : [] }
        return files.compactMap { url -> Double? in
            guard let file = try? AVAudioFile(forReading: url) else { return nil }
            return Double(file.length) / file.processingFormat.sampleRate
        }
    }

    // MARK: - Processing Mode

    func setProcessingMode(_ isPerChannel: Bool) {
        perChannelMode = isPerChannel
        settingsManager.perChannelMode = isPerChannel

        manualOptions.isPerChannelMode = isPerChannel
        if isPerChannel && fileChannelCount > 0 {
            channelTabs.setChannels(count: fileChannelCount, trackNames: trackNames, bitDepth: fileBitDepth > 0 ? fileBitDepth : 24)
        }
    }

    // MARK: - Process

    func startProcessing() {
        // Validation
        guard !files.isEmpty else {
            showAlert("Please select audio files first.")
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
        panel.message = "Choose output folder for processed files"
        panel.prompt = "Select"

        guard panel.runModal() == .OK, let outputDir = panel.url else { return }

        if perChannelMode {
            startPerChannelProcessing(outputDir: outputDir)
        } else {
            startWholeFileProcessing(outputDir: outputDir)
        }
    }

    private func startWholeFileProcessing(outputDir: URL) {
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

        let workflow = BatchWorkflow(apiClient: apiClient)
        batchWorkflow = workflow

        workflow.start(
            files: files,
            presetUuid: effectivePresetUuid,
            manualSettings: settings,
            avoidOverwrite: manualOptions.avoidOverwrite,
            outputSuffix: manualOptions.outputSuffix,
            writeSettingsXml: manualOptions.writeSettingsXml,
            channelToExtract: manualOptions.selectedChannel,
            previewDuration: previewDuration,
            keepTimecode: manualOptions.keepTimecode,
            outputDirectory: outputDir
        )

        monitorBatchWorkflow(workflow)
    }

    private func startPerChannelProcessing(outputDir: URL) {
        guard channelTabs.hasAnyChannelEnabled else {
            showAlert("Please enable processing options for at least one channel.")
            return
        }

        // Verify all files have same channel count
        if files.count > 1 {
            for file in files {
                guard let audioFile = try? AVAudioFile(forReading: file) else { continue }
                if Int(audioFile.processingFormat.channelCount) != fileChannelCount {
                    showAlert("All files must have the same channel count for per-channel mode.")
                    return
                }
            }
        }

        statusText = "Starting per-channel processing..."
        progress = 0
        outputFile = nil
        outputDirectory = nil

        let channelSettings = channelTabs.getEnabledChannelSettings()
        let fileJobs = files.map { file in
            PerChannelFileJob(
                inputFile: file,
                channels: channelSettings.map { cs in
                    ChannelJob(channel: cs.channel, presetUuid: cs.presetUuid, settings: cs.settings)
                }
            )
        }

        let workflow = BatchWorkflow(apiClient: apiClient)
        batchWorkflow = workflow

        workflow.startPerChannel(
            fileJobs: fileJobs,
            avoidOverwrite: channelTabs.avoidOverwrite,
            outputSuffix: channelTabs.outputSuffix,
            writeSettingsXml: channelTabs.writeSettingsXml,
            outputDirectory: outputDir
        )

        monitorBatchWorkflow(workflow)
    }

    private func monitorBatchWorkflow(_ workflow: BatchWorkflow) {
        Task { @MainActor in
            while workflow.isRunning {
                statusText = workflow.overallStatus.isEmpty ? "Processing..." : workflow.overallStatus

                // Combine completed files + current file's progress
                let total = Double(max(1, workflow.totalCount))
                let completedFraction = Double(workflow.completedCount) / total

                // Find the best per-file progress from active workflows
                var currentFileProgress = 0.0
                for wf in workflow.workflows where wf.state.isActive {
                    currentFileProgress = max(currentFileProgress, wf.progress)
                }
                progress = completedFraction + (currentFileProgress / total)

                try? await Task.sleep(for: .milliseconds(250))
            }

            // Completion
            statusText = workflow.overallStatus
            progress = -1

            let successCount = workflow.results.filter(\.success).count
            let failCount = workflow.results.count - successCount

            if let output = workflow.lastOutputFile {
                outputFile = output
                outputDirectory = output.deletingLastPathComponent()

                // Load processed file for A/B playback
                if files.count == 1 {
                    audioPlayer.loadProcessed(url: output)
                }
            }

            // Desktop notification
            let title = failCount > 0 ? "Processing Complete (with errors)" : "Processing Complete"
            let body = "\(successCount) file\(successCount == 1 ? "" : "s") processed successfully"
            NotificationService.show(title: title, body: body)

            // Refresh credits
            await refreshCredits()
        }
    }

    func cancelProcessing() {
        batchWorkflow?.cancel()
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
                    manualOptions.applyApiSettings(algorithms)
                    presetModified = false
                }
            }
        } catch {
            // Silent preset load failure
        }
    }

    func savePreset(name: String) async {
        let settings = manualOptions.getSettings()
        do {
            let uuid = try await apiClient.savePreset(name: name, settings: settings)
            presets = try await apiClient.fetchPresets()
            await MainActor.run {
                selectedPresetUuid = uuid
                presetModified = false
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

    // MARK: - Channel Multiplier

    var channelMultiplier: Int {
        perChannelMode ? max(1, channelTabs.enabledChannelCount) : 1
    }
}
