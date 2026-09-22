import Testing
import Foundation
@testable import AuphonicApp

// MARK: - ProductionStatus Tests

struct ProductionStatusTests {

    @Test func isDone() {
        let status = ProductionStatus(statusCode: 3, statusString: "", progress: 1.0, errorMessage: "", outputFileUrl: "", uuid: "")
        #expect(status.isDone)
        #expect(!status.isError)
        #expect(!status.isProcessing)
    }

    /// 2 is Auphonic's "Error" state for a production that failed while
    /// processing; 9 Incomplete, 11 Outdated and 98 Empty cannot run either.
    @Test func isError() {
        for code in [2, 9, 11, 98] {
            let status = ProductionStatus(statusCode: code, statusString: "", progress: 0, errorMessage: "err", outputFileUrl: "", uuid: "")
            #expect(status.isError, "Status code \(code) should be error")
            #expect(!status.isDone)
            #expect(!status.isProcessing)
        }
    }

    /// Intermediate states must not be mistaken for failures — 12 to 15 were
    /// caught by the old `>= 9` rule.
    @Test func isProcessing() {
        for code in [4, 5, 6, 7, 8, 12, 13, 14, 15] {
            let status = ProductionStatus(statusCode: code, statusString: "", progress: 0.5, errorMessage: "", outputFileUrl: "", uuid: "")
            #expect(status.isProcessing, "Status code \(code) should be processing")
            #expect(!status.isDone)
            #expect(!status.isError)
        }
    }

    /// Waiting for upload/start is neither done, failed nor processing
    @Test func waitingStatesAreNotErrors() {
        for code in [0, 1, 10] {
            let status = ProductionStatus(statusCode: code, statusString: "", progress: 0, errorMessage: "", outputFileUrl: "", uuid: "")
            #expect(!status.isError, "Status code \(code) should not be an error")
            #expect(!status.isDone)
        }
    }

    @Test func failureDescriptionPrefersErrorMessageThenStatusName() {
        let withMessage = ProductionStatus(statusCode: 2, statusString: "Error", progress: 0, errorMessage: "Input file corrupt", outputFileUrl: "", uuid: "")
        #expect(withMessage.failureDescription == "Input file corrupt")

        let statusOnly = ProductionStatus(statusCode: 11, statusString: "Production Outdated", progress: 0, errorMessage: "", outputFileUrl: "", uuid: "")
        #expect(statusOnly.failureDescription == "Production Outdated")

        let bare = ProductionStatus(statusCode: 2, statusString: "", progress: 0, errorMessage: "", outputFileUrl: "", uuid: "")
        #expect(bare.failureDescription == "Processing failed")
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

