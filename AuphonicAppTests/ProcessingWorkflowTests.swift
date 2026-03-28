import Testing
import Foundation
@testable import AuphonicApp

struct ProcessingWorkflowTests {

    // MARK: - Initial State

    @Test func initialState() {
        let client = AuphonicAPIClient()
        let workflow = ProcessingWorkflow(apiClient: client)

        #expect(workflow.state == .idle)
        #expect(workflow.progress == -1)
        #expect(workflow.statusText == "")
        #expect(workflow.lastOutputFile == nil)
    }

    // MARK: - Cancel

    @Test func cancelResetsToIdle() {
        let client = AuphonicAPIClient()
        let workflow = ProcessingWorkflow(apiClient: client)

        workflow.cancel()
        #expect(workflow.state == .idle)
    }

    // MARK: - setTempOutputMode

    @Test func setTempOutputMode() {
        let client = AuphonicAPIClient()
        let workflow = ProcessingWorkflow(apiClient: client)

        workflow.setTempOutputMode(true)
        // No public property to verify, but should not crash
    }

    // MARK: - setOutputDirectory

    @Test func setOutputDirectory() {
        let client = AuphonicAPIClient()
        let workflow = ProcessingWorkflow(apiClient: client)

        let dir = FileManager.default.temporaryDirectory
        workflow.setOutputDirectory(dir)
        // No public property to verify, but should not crash
    }

    @Test func setOutputDirectoryNil() {
        let client = AuphonicAPIClient()
        let workflow = ProcessingWorkflow(apiClient: client)

        workflow.setOutputDirectory(nil)
        // Should not crash
    }
}
