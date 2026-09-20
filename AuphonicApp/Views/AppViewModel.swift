import SwiftUI
import AVFoundation

@MainActor
@Observable
final class AppViewModel {
    // Services
    let settingsManager = SettingsManager()
    let apiClient = AuphonicAPIClient()
    let audioPlayer = AudioPlayerService()

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

        isLoadingFiles = true
        Task {
            // Folder expansion and metadata reads are file I/O; keep them off the main actor
            let (attempted, loaded) = await Task.detached(priority: .userInitiated) {
                let wavURLs = Self.collectWavURLs(from: urls).filter { !known.contains($0) }
                return (wavURLs.count, wavURLs.compactMap { BatchFile(url: $0) })
            }.value

            batchFiles.append(contentsOf: loaded)
            rebuildGroups()
            isLoadingFiles = false

            if loaded.count < attempted {
                showAlert("\(attempted - loaded.count) file(s) could not be read and were skipped.")
            }
        }
    }

    /// Expand folders (recursively) to the WAV files they contain; plain WAV
    /// URLs pass through. Order is stable (by path) and duplicates are removed.
    nonisolated static func collectWavURLs(from urls: [URL]) -> [URL] {
        var result: [URL] = []
        var seen = Set<URL>()

        func add(_ url: URL) {
            let standardized = url.standardizedFileURL
            if url.pathExtension.lowercased() == "wav", seen.insert(standardized).inserted {
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

    func startProcessing() {
        guard !batchFiles.isEmpty else {
            showAlert("Please add WAV files first.")
            return
        }
        guard settingsManager.hasApiToken else {
            showAlert("Add your Auphonic API token to start processing.", offersSettings: true)
            return
        }

        let configuredGroups = groups.filter { $0.config.hasValidJobConfiguration }
        guard !configuredGroups.isEmpty else {
            showAlert("Please enable at least one channel and select a preset or processing options.")
            return
        }

        // Destination folder for the output files (originals are never modified)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the output folder (originals stay untouched; outputs keep their file names)"
        panel.prompt = "Process"

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let wf = BatchWorkflow(apiClient: apiClient)
        wf.deleteProductionsAfterDownload = settingsManager.deleteProductionsAfterDownload
        workflow = wf
        wf.start(groups: configuredGroups, destination: destination) { [weak self] in
            Task { await self?.refreshCredits() }
        }
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
        guard let group = selectedGroup else {
            showAlert("Select a group first.")
            return
        }
        guard group.config.hasValidJobConfiguration else {
            showAlert("Please enable at least one channel and select a preset or processing options.")
            return
        }

        // Representative take: the selected file if it belongs to this group, else the first
        let testFile: BatchFile
        if let selected = selectedFile, group.files.contains(where: { $0.id == selected.id }) {
            testFile = selected
        } else if let first = group.files.first {
            testFile = first
        } else {
            return
        }

        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("auphonic_settings_test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        // One-file group sharing the real group's config (same instance)
        let testGroup = FileGroup(channelCount: group.channelCount, files: [testFile], reusing: group.config)

        let wf = BatchWorkflow(apiClient: apiClient)
        wf.deleteProductionsAfterDownload = settingsManager.deleteProductionsAfterDownload
        // Never upload more than the 3-minute billing minimum for a test
        wf.maxUploadDuration = 180
        workflow = wf
        wf.start(groups: [testGroup], destination: testDir) { [weak self] in
            guard let self else { return }

            if case .done(let output) = testFile.status {
                // The test output is temporary — don't leave the file marked as done
                testFile.status = .pending
                self.selectFile(testFile)
                self.audioPlayer.loadProcessed(url: output)
            }
            Task { await self.refreshCredits() }
        }
    }

    // MARK: - Credit Estimate

    /// Billed seconds for the whole batch. Singletrack bills one production
    /// per channel, multitrack one production per file - each at the file
    /// duration with Auphonic's 3-minute minimum.
    var estimatedCostSeconds: Double {
        let minimumBilled = 180.0
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
        groups.reduce(0) { total, group in
            guard group.config.hasValidJobConfiguration else { return total }
            return total + group.config.apiCallCount * group.files.count
        }
    }

    // MARK: - Presets

    func loadPresetDetails(uuid: String) async {
        guard !uuid.isEmpty, let group = selectedGroup else { return }

        do {
            let details = try await apiClient.fetchPresetDetails(uuid: uuid)
            if let algorithms = details["algorithms"] as? [String: Any] {
                group.config.sharedOptions.applyApiSettings(algorithms)
                group.config.presetModified = false
            }
        } catch {
            // Silent preset load failure
        }
    }

    func savePreset(name: String) async {
        guard let group = selectedGroup else { return }
        let settings = group.config.sharedOptions.getSettings()

        do {
            let uuid = try await apiClient.savePreset(name: name, settings: settings)
            presets = try await apiClient.fetchPresets()
            group.config.selectedPresetUuid = uuid
            group.config.presetModified = false
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
