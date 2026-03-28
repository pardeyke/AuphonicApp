import Testing
import Foundation
@testable import AuphonicApp

// MARK: - ProcessingState Tests

struct ProcessingStateTests {

    @Test func isActiveForActiveStates() {
        let activeStates: [ProcessingState] = [
            .extractingChannel, .trimming, .creatingProduction,
            .uploading, .starting, .processing,
            .downloading, .converting, .saving
        ]
        for state in activeStates {
            #expect(state.isActive, "\(state) should be active")
        }
    }

    @Test func isActiveForInactiveStates() {
        #expect(!ProcessingState.idle.isActive)
        #expect(!ProcessingState.done.isActive)
        #expect(!ProcessingState.error("test").isActive)
    }

    @Test func statusTexts() {
        #expect(ProcessingState.idle.statusText == "Ready")
        #expect(ProcessingState.extractingChannel.statusText == "Extracting channel...")
        #expect(ProcessingState.trimming.statusText == "Trimming preview...")
        #expect(ProcessingState.creatingProduction.statusText == "Creating production...")
        #expect(ProcessingState.uploading.statusText == "Uploading...")
        #expect(ProcessingState.starting.statusText == "Starting production...")
        #expect(ProcessingState.processing.statusText == "Processing...")
        #expect(ProcessingState.downloading.statusText == "Downloading...")
        #expect(ProcessingState.converting.statusText == "Converting format...")
        #expect(ProcessingState.saving.statusText == "Saving...")
        #expect(ProcessingState.done.statusText == "Done")
    }

    @Test func errorStatusText() {
        let state = ProcessingState.error("Connection lost")
        #expect(state.statusText == "Error: Connection lost")
    }

    @Test func equatable() {
        #expect(ProcessingState.idle == ProcessingState.idle)
        #expect(ProcessingState.done == ProcessingState.done)
        #expect(ProcessingState.error("a") == ProcessingState.error("a"))
        #expect(ProcessingState.error("a") != ProcessingState.error("b"))
        #expect(ProcessingState.idle != ProcessingState.done)
    }
}

// MARK: - ProductionStatus Tests

struct ProductionStatusTests {

    @Test func isDone() {
        let status = ProductionStatus(statusCode: 3, statusString: "", progress: 1.0, errorMessage: "", outputFileUrl: "", uuid: "")
        #expect(status.isDone)
        #expect(!status.isError)
        #expect(!status.isProcessing)
    }

    @Test func isError() {
        for code in [9, 10, 11, 99] {
            let status = ProductionStatus(statusCode: code, statusString: "", progress: 0, errorMessage: "err", outputFileUrl: "", uuid: "")
            #expect(status.isError, "Status code \(code) should be error")
            #expect(!status.isDone)
        }
    }

    @Test func isProcessing() {
        for code in [4, 5, 6, 7, 8] {
            let status = ProductionStatus(statusCode: code, statusString: "", progress: 0.5, errorMessage: "", outputFileUrl: "", uuid: "")
            #expect(status.isProcessing, "Status code \(code) should be processing")
            #expect(!status.isDone)
            #expect(!status.isError)
        }
    }

    @Test func idleStatusIsNone() {
        let status = ProductionStatus(statusCode: 0, statusString: "", progress: 0, errorMessage: "", outputFileUrl: "", uuid: "")
        #expect(!status.isDone)
        #expect(!status.isError)
        #expect(!status.isProcessing)
    }
}

// MARK: - UserCredits Tests

struct UserCreditsTests {

    @Test func displayCreditsSubtracts2Hours() {
        let credits = UserCredits(credits: 5.0, onetimeCredits: 3.0, recurringCredits: 2.0)
        #expect(credits.displayCredits == 3.0)
    }

    @Test func displayCreditsMinimumZero() {
        let credits = UserCredits(credits: 1.0, onetimeCredits: 1.0, recurringCredits: 0.0)
        #expect(credits.displayCredits == 0.0)
    }

    @Test func displayCreditsExactly2Hours() {
        let credits = UserCredits(credits: 2.0, onetimeCredits: 2.0, recurringCredits: 0.0)
        #expect(credits.displayCredits == 0.0)
    }

    @Test func displayCreditsZero() {
        let credits = UserCredits(credits: 0.0, onetimeCredits: 0.0, recurringCredits: 0.0)
        #expect(credits.displayCredits == 0.0)
    }
}

// MARK: - AuphonicPreset Tests

struct AuphonicPresetTests {

    @Test func identifiable() {
        let preset = AuphonicPreset(uuid: "abc-123", name: "My Preset")
        #expect(preset.id == "abc-123")
        #expect(preset.uuid == "abc-123")
        #expect(preset.name == "My Preset")
    }

    @Test func hashable() {
        let a = AuphonicPreset(uuid: "abc", name: "Preset A")
        let b = AuphonicPreset(uuid: "abc", name: "Preset A")
        let c = AuphonicPreset(uuid: "def", name: "Preset B")
        #expect(a == b)
        #expect(a != c)
    }
}

// MARK: - FileResult Tests

struct FileResultTests {

    @Test func uniqueIds() {
        let a = FileResult(inputFile: URL(fileURLWithPath: "/a.wav"), success: true)
        let b = FileResult(inputFile: URL(fileURLWithPath: "/b.wav"), success: true)
        #expect(a.id != b.id)
    }

    @Test func defaultValues() {
        var result = FileResult(inputFile: URL(fileURLWithPath: "/a.wav"), success: false)
        #expect(result.outputFile == nil)
        #expect(result.errorMessage == nil)
        #expect(!result.success)

        result.success = true
        result.outputFile = URL(fileURLWithPath: "/out.wav")
        #expect(result.success)
        #expect(result.outputFile != nil)
    }
}
