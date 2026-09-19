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

