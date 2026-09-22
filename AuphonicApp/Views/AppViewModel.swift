import SwiftUI
import AVFoundation

@MainActor
@Observable
final class AppViewModel {
    // Services
    let settingsManager = SettingsManager()
    let apiClient = AuphonicAPIClient()
    let audioPlayer = AudioPlayerService()

    /// Standard mode sends whole files, Mix Preparation does channel surgery
    var mode: AppMode {
        didSet {
            settingsManager.appMode = mode
            dropFilesUnsupportedByCurrentMode()
        }
    }

    /// Settings used in Standard mode (Mix Preparation configures per group)
    let standardConfig = StandardModeConfig()

    // Batch state
    private(set) var batchFiles: [BatchFile] = []
    private(set) var groups: [FileGroup] = []
    var selectedGroupID: UUID?
    var selectedFileID: UUID?
    var isLoadingFiles = false

    // API state
    var presets: [AuphonicPreset] = []
    var credits: UserCredits?

    // UI state
    var showingSettings = false
    var showingSavePreset = false
    var savePresetName = ""
    var alertMessage = ""
    var showingAlert = false
    /// Adds an "Open Settings…" button to the alert (missing API token)
    var alertOffersSettings = false

    // Processing
    private(set) var workflow: BatchWorkflow?
    var isProcessing: Bool { workflow?.isRunning ?? false }
    var statusText: String { workflow?.statusText ?? "Ready" }
    var progress: Double { workflow?.overallProgress ?? -1 }
    var outputDirectory: URL? { workflow?.lastOutputDirectory }

    var selectedGroup: FileGroup? {
        groups.first { $0.id == selectedGroupID }
    }

    var selectedFile: BatchFile? {
        batchFiles.first { $0.id == selectedFileID }
    }

    init() {
        apiClient.token = settingsManager.apiToken
        mode = settingsManager.appMode
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

    func addFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let known = Set(batchFiles.map(\.url))
        let mode = mode

        isLoadingFiles = true
        Task {
            // Folder expansion and metadata reads are file I/O; keep them off the main actor
            let (attempted, loaded) = await Task.detached(priority: .userInitiated) {
                let audioURLs = Self.collectAudioURLs(from: urls, mode: mode).filter { !known.contains($0) }
                return (audioURLs.count, audioURLs.compactMap { BatchFile(url: $0) })
            }.value

            batchFiles.append(contentsOf: loaded)
            rebuildGroups()
            isLoadingFiles = false

            if loaded.count < attempted {
                showAlert("\(attempted - loaded.count) file(s) could not be read and were skipped.")
            }
        }
    }

    /// Expand folders (recursively) to the audio files they contain; audio
    /// URLs pass through. Order is stable (by path) and duplicates are removed.
    /// Mix Preparation only collects WAV files.
    nonisolated static func collectAudioURLs(from urls: [URL], mode: AppMode = .standard) -> [URL] {
        var result: [URL] = []
        var seen = Set<URL>()

        func add(_ url: URL) {
            let standardized = url.standardizedFileURL
            if AudioFileTypes.isAudioFile(url, mode: mode), seen.insert(standardized).inserted {
                result.append(standardized)
            }
        }

        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                // Keep the folder's security scope open for the app session:
                // the contained files are read again later during processing.
                _ = url.startAccessingSecurityScopedResource()
                if let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    for case let item as URL in enumerator {
                        add(item)
                    }
                }
            } else {
                add(url)
            }
        }

        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func removeFile(_ file: BatchFile) {
        batchFiles.removeAll { $0.id == file.id }
        if selectedFileID == file.id {
            selectedFileID = nil
            audioPlayer.stop()
        }
        rebuildGroups()
    }

    func removeGroup(_ group: FileGroup) {
        let ids = Set(group.files.map(\.id))
        batchFiles.removeAll { ids.contains($0.id) }
        if let selected = selectedFileID, ids.contains(selected) {
            selectedFileID = nil
            audioPlayer.stop()
        }
        rebuildGroups()
    }

    func clearFiles() {
        batchFiles.removeAll()
        selectedFileID = nil
        selectedGroupID = nil
        groups = []
        audioPlayer.stop()
    }

    /// Mix Preparation can only write its output into a WAV container, so
    /// switching into it drops anything else that is already in the batch.
    private func dropFilesUnsupportedByCurrentMode() {
        let unsupported = batchFiles.filter { !AudioFileTypes.isAudioFile($0.url, mode: mode) }
        guard !unsupported.isEmpty else { return }

        let ids = Set(unsupported.map(\.id))
        batchFiles.removeAll { ids.contains($0.id) }
        if let selected = selectedFileID, ids.contains(selected) {
            selectedFileID = nil
            audioPlayer.stop()
        }
        rebuildGroups()

        let count = unsupported.count
        showAlert("\(count) non-WAV file\(count == 1 ? " was" : "s were") removed: Mix Preparation writes its output into a copy of the original WAV, which only works for WAV files.")
    }

    private func rebuildGroups() {
        groups = FileGrouper.makeGroups(from: batchFiles, previousGroups: groups)

        // Keep a valid group selection
        if selectedGroupID == nil || !groups.contains(where: { $0.id == selectedGroupID }) {
            selectedGroupID = groups.first?.id
        }
    }

    func selectFile(_ file: BatchFile) {
        selectedFileID = file.id
        if let group = groups.first(where: { g in g.files.contains { $0.id == file.id } }) {
            selectedGroupID = group.id
        }
        audioPlayer.loadOriginal(url: file.url)

        // Spot-checking: a processed file loads its output into the second lane for A/B
        if case .done(let output) = file.status,
           FileManager.default.fileExists(atPath: output.path) {
            audioPlayer.loadProcessed(url: output)
        } else {
            audioPlayer.clearProcessed()
        }
    }

    // MARK: - Process

    /// What a processing run covers
    private enum ProcessingScope {
        case wholeBatch
        case single(BatchFile)
    }

    func startProcessing() {
        process(scope: .wholeBatch)
    }

    /// Full run for just the take selected in the list — same settings and
    /// destination folder as the batch, only smaller
    func processSelectedFile() {
        guard let file = selectedFile else {
            showAlert("Select a file first.")
            return
        }
        process(scope: .single(file))
    }

    private func process(scope: ProcessingScope) {
        guard !isProcessing else { return }
        guard !batchFiles.isEmpty else {
            showAlert("Please add audio files first.")
            return
        }
        guard settingsManager.hasApiToken else {
            showAlert("Add your Auphonic API token to start processing.", offersSettings: true)
            return
        }

        // Work out what to run before asking for a destination folder
        var files: [BatchFile] = []
        var configuredGroups: [FileGroup] = []

        switch mode {
        case .standard:
            guard standardConfig.hasValidConfiguration else {
                showAlert("Select a preset, enable a processing option or choose an output format.")
                return
            }
            switch scope {
            case .wholeBatch: files = batchFiles
            case .single(let file): files = [file]
            }

        case .mixPreparation:
            switch scope {
            case .wholeBatch:
                configuredGroups = groups.filter { $0.config.hasValidJobConfiguration }
            case .single(let file):
                guard let group = groups.first(where: { g in g.files.contains { $0.id == file.id } }) else { return }
                guard group.config.hasValidJobConfiguration else {
                    showAlert("Please enable at least one channel and select a preset or processing options.")
                    return
                }
                // One-file group sharing the real group's config (same instance)
                configuredGroups = [FileGroup(channelCount: group.channelCount, files: [file], reusing: group.config)]
            }
            guard !configuredGroups.isEmpty else {
                showAlert("Please enable at least one channel and select a preset or processing options.")
                return
            }
        }

        guard let destination = chooseDestination() else { return }

        let wf = BatchWorkflow(apiClient: apiClient)
        wf.deleteProductionsAfterDownload = settingsManager.deleteProductionsAfterDownload
        workflow = wf

        let finished: () -> Void = { [weak self] in
            Task { await self?.refreshCredits() }
        }

        switch mode {
        case .standard:
            wf.start(files: files, config: standardConfig, destination: destination, onFinished: finished)
        case .mixPreparation:
            wf.start(groups: configuredGroups, destination: destination, onFinished: finished)
        }
    }

    /// Destination folder for the output files (originals are never modified)
    private func chooseDestination() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the output folder (originals stay untouched; outputs keep their file names)"
        panel.prompt = "Process"

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func cancelProcessing() {
        workflow?.cancel()
    }

    // MARK: - Settings Test Drive

    /// Process one representative take of the selected group with its current
    /// settings into a temp folder and load the result into the player's
    /// Processed lane for A/B comparison — before spending credits on the batch.
    func testSettings() {
        guard !isProcessing else { return }
        guard settingsManager.hasApiToken else {
            showAlert("Add your Auphonic API token to start processing.", offersSettings: true)
            return
        }
        // Representative take: the selected file, else the first of the group/batch
        let group = selectedGroup
        let testFile: BatchFile
        switch mode {
        case .standard:
            guard standardConfig.hasValidConfiguration else {
                showAlert("Select a preset, enable a processing option or choose an output format.")
                return
            }
            guard let file = selectedFile ?? batchFiles.first else {
                showAlert("Please add audio files first.")
                return
            }
            testFile = file
        case .mixPreparation:
            guard let group else {
                showAlert("Select a group first.")
                return
            }
            guard group.config.hasValidJobConfiguration else {
                showAlert("Please enable at least one channel and select a preset or processing options.")
                return
            }
            if let selected = selectedFile, group.files.contains(where: { $0.id == selected.id }) {
                testFile = selected
            } else if let first = group.files.first {
                testFile = first
            } else {
                return
            }
        }

        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("auphonic_settings_test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        let wf = BatchWorkflow(apiClient: apiClient)
        wf.deleteProductionsAfterDownload = settingsManager.deleteProductionsAfterDownload
        // Never upload more than the 3-minute billing minimum for a test
        wf.maxUploadDuration = 180
        workflow = wf

        let finished: () -> Void = { [weak self] in
            guard let self else { return }

            if case .done(let output) = testFile.status {
                // The test output is temporary — don't leave the file marked as done
                testFile.status = .pending
                self.selectFile(testFile)
                self.audioPlayer.loadProcessed(url: output)
            }
            Task { await self.refreshCredits() }
        }

        switch mode {
        case .standard:
            wf.start(files: [testFile], config: standardConfig, destination: testDir, onFinished: finished)
        case .mixPreparation:
            // One-file group sharing the real group's config (same instance)
            guard let group else { return }
            let testGroup = FileGroup(channelCount: group.channelCount, files: [testFile], reusing: group.config)
            wf.start(groups: [testGroup], destination: testDir, onFinished: finished)
        }
    }

    // MARK: - Credit Estimate

    /// Billed seconds for the whole batch. Singletrack bills one production
    /// per channel, multitrack one production per file - each at the file
    /// duration with Auphonic's 3-minute minimum.
    var estimatedCostSeconds: Double {
        let minimumBilled = 180.0

        if mode == .standard {
            guard standardConfig.hasValidConfiguration else { return 0 }
            return batchFiles.reduce(0) { $0 + max($1.duration, minimumBilled) }
        }

        return groups.reduce(0) { total, group in
            guard group.config.hasValidJobConfiguration else { return total }
            let productionsPerFile = Double(group.config.apiCallCount)
            let groupCost = group.files.reduce(0) { sum, file in
                sum + productionsPerFile * max(file.duration, minimumBilled)
            }
            return total + groupCost
        }
    }

    /// Total number of Auphonic productions in the batch
    var totalApiCallCount: Int {
        if mode == .standard {
            return standardConfig.hasValidConfiguration ? batchFiles.count : 0
        }

        return groups.reduce(0) { total, group in
            guard group.config.hasValidJobConfiguration else { return total }
            return total + group.config.apiCallCount * group.files.count
        }
    }

    // MARK: - Presets

    func loadPresetDetails(uuid: String) async {
        guard !uuid.isEmpty else { return }

        // Where the preset lands depends on the mode
        let apply: ([String: Any]) -> Void
        switch mode {
        case .standard:
            apply = { [standardConfig] algorithms in
                standardConfig.options.applyApiSettings(algorithms)
                standardConfig.cutting.applyApiSettings(algorithms)
                standardConfig.presetModified = false
            }
        case .mixPreparation:
            guard let group = selectedGroup else { return }
            apply = { algorithms in
                group.config.sharedOptions.applyApiSettings(algorithms)
                group.config.presetModified = false
            }
        }

        do {
            let details = try await apiClient.fetchPresetDetails(uuid: uuid)
            if let algorithms = details["algorithms"] as? [String: Any] {
                apply(algorithms)
            }
        } catch {
            // Silent preset load failure
        }
    }

    func savePreset(name: String) async {
        let settings: [String: Any]
        let store: (String) -> Void
        switch mode {
        case .standard:
            // Includes the cutting keys, so a stored preset restores them
            settings = standardConfig.productionSettings
            store = { [standardConfig] uuid in
                standardConfig.selectedPresetUuid = uuid
                standardConfig.presetModified = false
            }
        case .mixPreparation:
            guard let group = selectedGroup else { return }
            settings = group.config.sharedOptions.getSettings()
            store = { uuid in
                group.config.selectedPresetUuid = uuid
                group.config.presetModified = false
            }
        }

        do {
            let uuid = try await apiClient.savePreset(name: name, settings: settings)
            presets = try await apiClient.fetchPresets()
            store(uuid)
        } catch {
            showAlert("Failed to save preset: \(error.localizedDescription)")
        }
    }

    // MARK: - Alert

    func showAlert(_ message: String, offersSettings: Bool = false) {
        alertMessage = message
        alertOffersSettings = offersSettings
        showingAlert = true
    }
}
