import Testing
import Foundation
@testable import AuphonicApp

struct BatchWorkflowTests {

    // MARK: - Initial State

    @Test func initialState() {
        let client = AuphonicAPIClient()
        let workflow = BatchWorkflow(apiClient: client)

        #expect(!workflow.isRunning)
        #expect(workflow.results.isEmpty)
        #expect(workflow.completedCount == 0)
        #expect(workflow.totalCount == 0)
        #expect(workflow.overallStatus == "")
        #expect(workflow.lastOutputFile == nil)
        #expect(workflow.fileStatuses.isEmpty)
        #expect(workflow.workflows.isEmpty)
    }

    // MARK: - Cancel

    @Test func cancelSetsNotRunning() {
        let client = AuphonicAPIClient()
        let workflow = BatchWorkflow(apiClient: client)

        workflow.cancel()
        #expect(!workflow.isRunning)
        #expect(workflow.overallStatus == "Cancelled")
    }

    // MARK: - Start

    @Test @MainActor func startSetsRunning() {
        let client = AuphonicAPIClient()
        client.token = "test"
        let workflow = BatchWorkflow(apiClient: client)

        let files = [
            URL(fileURLWithPath: "/tmp/test1.wav"),
            URL(fileURLWithPath: "/tmp/test2.wav")
        ]

        workflow.start(
            files: files,
            presetUuid: "preset-123",
            manualSettings: [:],
            avoidOverwrite: true,
            outputSuffix: "_out",
            writeSettingsXml: false,
            outputDirectory: FileManager.default.temporaryDirectory
        )

        #expect(workflow.isRunning)
        #expect(workflow.totalCount == 2)
        #expect(workflow.results.count == 2)
        #expect(workflow.workflows.count == 2)

        // Cleanup
        workflow.cancel()
    }

    // MARK: - Per-Channel Start

    @Test @MainActor func startPerChannelSetsRunning() {
        let client = AuphonicAPIClient()
        client.token = "test"
        let workflow = BatchWorkflow(apiClient: client)

        let fileJobs = [
            PerChannelFileJob(
                inputFile: URL(fileURLWithPath: "/tmp/test.wav"),
                channels: [
                    ChannelJob(channel: 1, presetUuid: "", settings: ["output_format": "wav-24bit"]),
                    ChannelJob(channel: 2, presetUuid: "", settings: ["output_format": "wav-24bit"])
                ]
            )
        ]

        workflow.startPerChannel(
            fileJobs: fileJobs,
            avoidOverwrite: true,
            outputSuffix: "_out",
            writeSettingsXml: false,
            outputDirectory: FileManager.default.temporaryDirectory
        )

        #expect(workflow.isRunning)
        #expect(workflow.totalCount == 1)
        #expect(workflow.results.count == 1)
        #expect(workflow.workflows.count == 2) // One per channel

        workflow.cancel()
    }

    // MARK: - Results Initialization

    @Test @MainActor func resultsInitializedAsFailure() {
        let client = AuphonicAPIClient()
        client.token = "test"
        let workflow = BatchWorkflow(apiClient: client)

        let files = [URL(fileURLWithPath: "/tmp/test.wav")]
        workflow.start(
            files: files,
            presetUuid: "p",
            manualSettings: [:],
            avoidOverwrite: false,
            outputSuffix: "",
            writeSettingsXml: false
        )

        #expect(!workflow.results[0].success)
        #expect(workflow.results[0].inputFile.lastPathComponent == "test.wav")

        workflow.cancel()
    }

    // MARK: - Cancel During Processing

    @Test @MainActor func cancelDuringProcessing() {
        let client = AuphonicAPIClient()
        client.token = "test"
        let workflow = BatchWorkflow(apiClient: client)

        let files = [
            URL(fileURLWithPath: "/tmp/a.wav"),
            URL(fileURLWithPath: "/tmp/b.wav"),
            URL(fileURLWithPath: "/tmp/c.wav")
        ]

        workflow.start(
            files: files,
            presetUuid: "p",
            manualSettings: [:],
            avoidOverwrite: false,
            outputSuffix: "",
            writeSettingsXml: false
        )

        #expect(workflow.isRunning)
        workflow.cancel()
        #expect(!workflow.isRunning)
        #expect(workflow.overallStatus == "Cancelled")
    }
}
