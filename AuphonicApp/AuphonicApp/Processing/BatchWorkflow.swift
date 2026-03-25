import Foundation

@Observable
final class BatchWorkflow {
    private(set) var isRunning = false
    private(set) var results: [FileResult] = []
    private(set) var completedCount = 0
    private(set) var totalCount = 0
    private(set) var overallStatus: String = ""
    private(set) var lastOutputFile: URL?

    // Per-file status (index → status string)
    private(set) var fileStatuses: [Int: String] = [:]

    private var apiClient: AuphonicAPIClient
    private(set) var workflows: [ProcessingWorkflow] = []
    private var queuedIndices: [Int] = []
    private var activeIndices: Set<Int> = []
    private var createTimestamps: [Date] = []
    private var rateLimitTimer: Timer?

    // Per-channel mode
    private var isPerChannelMode = false
    private struct SlotInfo {
        let inputFile: URL
        let channel: Int
        let presetUuid: String
        let settings: [String: Any]
    }
    private var slotInfos: [SlotInfo] = []

    private struct FileGroup {
        let fileIndex: Int
        let inputFile: URL
        var slotIndices: [Int] = []
        var completedChannelFiles: [Int: URL] = [:]  // channel (0-based) → processed file
        var completedCount = 0
        var failedCount = 0
        var mergeComplete = false
    }
    private var fileGroups: [FileGroup] = []

    private var avoidOverwrite = false
    private var outputSuffix = "_auphonic"
    private var writeSettingsXml = false
    private var keepTimecode = false
    private var previewDuration: Double = 0
    private var outputDirectory: URL?

    private static let maxCreatesPerWindow = 38
    private static let windowSeconds: TimeInterval = 120

    init(apiClient: AuphonicAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Whole-File Batch

    func start(
        files: [URL],
        presetUuid: String,
        manualSettings: [String: Any],
        avoidOverwrite: Bool,
        outputSuffix: String,
        writeSettingsXml: Bool,
        channelToExtract: Int = 0,
        previewDuration: Double = 0,
        keepTimecode: Bool = false,
        outputDirectory: URL? = nil
    ) {
        reset()
        isPerChannelMode = false
        self.avoidOverwrite = avoidOverwrite
        self.outputSuffix = outputSuffix
        self.writeSettingsXml = writeSettingsXml
        self.keepTimecode = keepTimecode
        self.previewDuration = previewDuration
        self.outputDirectory = outputDirectory
        totalCount = files.count
        isRunning = true

        results = files.map { FileResult(inputFile: $0, success: false) }

        for (index, file) in files.enumerated() {
            let workflow = ProcessingWorkflow(apiClient: apiClient)
            workflows.append(workflow)

            // Store params for deferred launch
            slotInfos.append(SlotInfo(
                inputFile: file,
                channel: channelToExtract,
                presetUuid: presetUuid,
                settings: manualSettings
            ))
            queuedIndices.append(index)
        }

        startRateLimitTimer()
    }

    // MARK: - Per-Channel Batch

    func startPerChannel(
        fileJobs: [PerChannelFileJob],
        avoidOverwrite: Bool,
        outputSuffix: String,
        writeSettingsXml: Bool,
        outputDirectory: URL? = nil
    ) {
        reset()
        isPerChannelMode = true
        self.avoidOverwrite = avoidOverwrite
        self.outputSuffix = outputSuffix
        self.writeSettingsXml = writeSettingsXml
        self.outputDirectory = outputDirectory
        totalCount = fileJobs.count
        isRunning = true

        results = fileJobs.map { FileResult(inputFile: $0.inputFile, success: false) }

        for (fileIdx, job) in fileJobs.enumerated() {
            var group = FileGroup(fileIndex: fileIdx, inputFile: job.inputFile)

            for channelJob in job.channels {
                let slotIndex = workflows.count
                let workflow = ProcessingWorkflow(apiClient: apiClient)
                workflow.setTempOutputMode(true)
                workflows.append(workflow)

                var settings = channelJob.settings
                // Force WAV output for per-channel processing
                if settings["output_format"] == nil {
                    settings["output_format"] = "wav-24bit"
                }

                slotInfos.append(SlotInfo(
                    inputFile: job.inputFile,
                    channel: channelJob.channel,
                    presetUuid: channelJob.presetUuid,
                    settings: settings
                ))
                group.slotIndices.append(slotIndex)
                queuedIndices.append(slotIndex)
            }

            fileGroups.append(group)
        }

        startRateLimitTimer()
    }

    // MARK: - Cancel

    func cancel() {
        rateLimitTimer?.invalidate()
        rateLimitTimer = nil

        for workflow in workflows {
            workflow.cancel()
        }

        isRunning = false
        overallStatus = "Cancelled"
    }

    // MARK: - Rate Limiting

    private func startRateLimitTimer() {
        rateLimitTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.processQueue()
        }
        // Also process immediately
        processQueue()
    }

    private func processQueue() {
        // Purge old timestamps
        let cutoff = Date().addingTimeInterval(-Self.windowSeconds)
        createTimestamps.removeAll { $0 < cutoff }

        // Launch queued workflows if under rate limit
        while !queuedIndices.isEmpty && createTimestamps.count < Self.maxCreatesPerWindow {
            let index = queuedIndices.removeFirst()
            activeIndices.insert(index)
            createTimestamps.append(Date())
            launchWorkflow(at: index)
        }

        // Check if all done
        if queuedIndices.isEmpty && activeIndices.isEmpty && isRunning {
            finishBatch()
        }
    }

    private func launchWorkflow(at index: Int) {
        guard index < workflows.count, index < slotInfos.count else { return }

        let workflow = workflows[index]
        let info = slotInfos[index]

        let fileIndex = isPerChannelMode ? fileGroupIndex(forSlot: index) : index
        fileStatuses[fileIndex] = "Starting..."

        // Observe workflow state changes
        Task { @MainActor in
            await self.monitorWorkflow(workflow, slotIndex: index, fileIndex: fileIndex)
        }

        workflow.setOutputDirectory(outputDirectory)

        workflow.start(
            inputFile: info.inputFile,
            presetUuid: info.presetUuid,
            manualSettings: info.settings,
            avoidOverwrite: avoidOverwrite,
            outputSuffix: outputSuffix,
            writeSettingsXml: writeSettingsXml,
            channelToExtract: info.channel,
            previewDuration: previewDuration,
            keepTimecode: keepTimecode
        )
    }

    private func monitorWorkflow(_ workflow: ProcessingWorkflow, slotIndex: Int, fileIndex: Int) async {
        // Poll the workflow state
        while workflow.state.isActive {
            fileStatuses[fileIndex] = workflow.statusText.isEmpty ? workflow.state.statusText : workflow.statusText
            overallStatus = "Processing \(completedCount + 1)/\(totalCount)..."
            try? await Task.sleep(for: .milliseconds(250))
        }

        // Workflow finished
        activeIndices.remove(slotIndex)

        if case .done = workflow.state {
            if isPerChannelMode {
                handlePerChannelSlotComplete(slotIndex: slotIndex, output: workflow.lastOutputFile)
            } else {
                results[fileIndex].success = true
                results[fileIndex].outputFile = workflow.lastOutputFile
                if let output = workflow.lastOutputFile { lastOutputFile = output }
                completedCount += 1
                fileStatuses[fileIndex] = "Done"
            }
        } else if case .error(let msg) = workflow.state {
            if isPerChannelMode {
                handlePerChannelSlotFailed(slotIndex: slotIndex, error: msg)
            } else {
                results[fileIndex].success = false
                results[fileIndex].errorMessage = msg
                completedCount += 1
                fileStatuses[fileIndex] = "Error: \(msg)"
            }
        }
    }

    // MARK: - Per-Channel Completion

    private func handlePerChannelSlotComplete(slotIndex: Int, output: URL?) {
        guard let groupIdx = fileGroups.firstIndex(where: { $0.slotIndices.contains(slotIndex) }) else { return }

        let channelInGroup = fileGroups[groupIdx].slotIndices.firstIndex(of: slotIndex) ?? 0
        let info = slotInfos[slotIndex]
        let channelIndex = info.channel - 1  // Convert 1-based to 0-based

        if let outputFile = output {
            fileGroups[groupIdx].completedChannelFiles[channelIndex] = outputFile
        }
        fileGroups[groupIdx].completedCount += 1

        checkGroupCompletion(groupIdx)
    }

    private func handlePerChannelSlotFailed(slotIndex: Int, error: String) {
        guard let groupIdx = fileGroups.firstIndex(where: { $0.slotIndices.contains(slotIndex) }) else { return }
        fileGroups[groupIdx].failedCount += 1
        checkGroupCompletion(groupIdx)
    }

    private func checkGroupCompletion(_ groupIdx: Int) {
        let group = fileGroups[groupIdx]
        let totalSlots = group.slotIndices.count
        guard group.completedCount + group.failedCount >= totalSlots else { return }

        if group.failedCount > 0 {
            results[group.fileIndex].success = false
            results[group.fileIndex].errorMessage = "Some channels failed"
            completedCount += 1
            fileStatuses[group.fileIndex] = "Error"
            cleanupGroupTempFiles(groupIdx)
        } else {
            mergeFileGroup(groupIdx)
        }
    }

    private func mergeFileGroup(_ groupIdx: Int) {
        let group = fileGroups[groupIdx]
        fileStatuses[group.fileIndex] = "Merging channels..."

        Task.detached { [self] in
            let dir: URL
            if let outputDir = self.outputDirectory {
                _ = outputDir.startAccessingSecurityScopedResource()
                dir = outputDir
            } else {
                dir = group.inputFile.deletingLastPathComponent()
            }
            defer {
                if self.outputDirectory != nil {
                    self.outputDirectory?.stopAccessingSecurityScopedResource()
                }
            }
            let baseName = group.inputFile.deletingPathExtension().lastPathComponent
            var outputName = baseName
            if self.avoidOverwrite { outputName += self.outputSuffix }

            var outputURL = dir.appendingPathComponent(outputName).appendingPathExtension("wav")

            if self.avoidOverwrite {
                var counter = 2
                while FileManager.default.fileExists(atPath: outputURL.path) {
                    outputURL = dir.appendingPathComponent("\(outputName)_\(counter)").appendingPathExtension("wav")
                    counter += 1
                }
            }

            let success = WavChunkCopier.mergeChannels(
                original: group.inputFile,
                output: outputURL,
                processedChannels: group.completedChannelFiles
            )

            await MainActor.run {
                if success {
                    self.results[group.fileIndex].success = true
                    self.results[group.fileIndex].outputFile = outputURL
                    self.lastOutputFile = outputURL
                    self.fileStatuses[group.fileIndex] = "Done"
                } else {
                    self.results[group.fileIndex].success = false
                    self.results[group.fileIndex].errorMessage = "Channel merge failed"
                    self.fileStatuses[group.fileIndex] = "Merge failed"
                }
                self.fileGroups[groupIdx].mergeComplete = true
                self.completedCount += 1
                self.cleanupGroupTempFiles(groupIdx)
            }
        }
    }

    private func cleanupGroupTempFiles(_ groupIdx: Int) {
        for (_, url) in fileGroups[groupIdx].completedChannelFiles {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Finish

    private func finishBatch() {
        rateLimitTimer?.invalidate()
        rateLimitTimer = nil
        isRunning = false

        let successCount = results.filter(\.success).count
        let failCount = results.count - successCount
        if failCount > 0 {
            overallStatus = "Done: \(successCount) succeeded, \(failCount) failed"
        } else {
            overallStatus = "Done: \(successCount) file\(successCount == 1 ? "" : "s") processed"
        }
    }

    // MARK: - Helpers

    private func reset() {
        workflows.removeAll()
        slotInfos.removeAll()
        queuedIndices.removeAll()
        activeIndices.removeAll()
        createTimestamps.removeAll()
        fileGroups.removeAll()
        fileStatuses.removeAll()
        results.removeAll()
        completedCount = 0
        totalCount = 0
        lastOutputFile = nil
        overallStatus = ""
        isRunning = false
    }

    private func fileGroupIndex(forSlot slotIndex: Int) -> Int {
        fileGroups.firstIndex(where: { $0.slotIndices.contains(slotIndex) }).map { fileGroups[$0].fileIndex } ?? 0
    }
}
