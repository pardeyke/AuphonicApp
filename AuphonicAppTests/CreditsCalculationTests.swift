import Testing
import Foundation
@testable import AuphonicApp

/// Tests for the credit calculation logic used in CreditsView.
/// The calculation logic is extracted here to test without SwiftUI rendering.
struct CreditsCalculationTests {

    private static let minimumBilledSeconds: Double = 180

    /// Mirror the estimatedCost calculation from CreditsView
    private func estimatedCost(fileDuration: Double, previewDuration: Double, apiCallCount: Int) -> Double {
        let calls = Double(max(1, apiCallCount))
        let effective = previewDuration > 0 ? min(previewDuration, fileDuration) : fileDuration
        let billed = max(effective, Self.minimumBilledSeconds)
        return billed * calls
    }

    private func hasMinimumApplied(fileDuration: Double, previewDuration: Double) -> Bool {
        let effective = previewDuration > 0 ? min(previewDuration, fileDuration) : fileDuration
        return effective < Self.minimumBilledSeconds
    }

    // MARK: - Basic Cost Calculation

    @Test func singleFileLongerThanMinimum() {
        let cost = estimatedCost(fileDuration: 300, previewDuration: 0, apiCallCount: 1)
        #expect(cost == 300)
    }

    @Test func singleFileShorterThanMinimum() {
        let cost = estimatedCost(fileDuration: 60, previewDuration: 0, apiCallCount: 1)
        #expect(cost == 180) // 3-minute minimum
    }

    @Test func singleFileExactlyMinimum() {
        let cost = estimatedCost(fileDuration: 180, previewDuration: 0, apiCallCount: 1)
        #expect(cost == 180)
    }

    // MARK: - Preview Duration

    @Test func previewTruncatesDuration() {
        // 600s file with 30s preview → billed as 180 (minimum)
        let cost = estimatedCost(fileDuration: 600, previewDuration: 30, apiCallCount: 1)
        #expect(cost == 180)
    }

    @Test func previewLongerThanMinimum() {
        // 600s file with 300s preview → billed as 300
        let cost = estimatedCost(fileDuration: 600, previewDuration: 300, apiCallCount: 1)
        #expect(cost == 300)
    }

    @Test func previewLongerThanFile() {
        // 60s file with 300s preview → min(300,60)=60 → bumped to 180
        let cost = estimatedCost(fileDuration: 60, previewDuration: 300, apiCallCount: 1)
        #expect(cost == 180)
    }

    // MARK: - Channel Multiplier

    @Test func apiCallCountDoubles() {
        let cost = estimatedCost(fileDuration: 300, previewDuration: 0, apiCallCount: 2)
        #expect(cost == 600)
    }

    @Test func apiCallCountQuadruples() {
        let cost = estimatedCost(fileDuration: 300, previewDuration: 0, apiCallCount: 4)
        #expect(cost == 1200)
    }

    @Test func apiCallCountZeroTreatedAsOne() {
        let cost = estimatedCost(fileDuration: 300, previewDuration: 0, apiCallCount: 0)
        #expect(cost == 300)
    }

    // MARK: - Minimum Applied Detection

    @Test func minimumAppliedForShortFile() {
        #expect(hasMinimumApplied(fileDuration: 60, previewDuration: 0))
    }

    @Test func minimumNotAppliedForLongFile() {
        #expect(!hasMinimumApplied(fileDuration: 300, previewDuration: 0))
    }

    @Test func minimumAppliedWithPreview() {
        #expect(hasMinimumApplied(fileDuration: 600, previewDuration: 30))
    }

    @Test func minimumNotAppliedWithLongPreview() {
        #expect(!hasMinimumApplied(fileDuration: 600, previewDuration: 300))
    }

    // MARK: - Display Credits

    @Test func displayCreditsCalculation() {
        let credits = UserCredits(credits: 5.0, onetimeCredits: 3.0, recurringCredits: 2.0)
        let totalCreditsSeconds = credits.displayCredits * 3600  // 3h = 10800s
        let cost = estimatedCost(fileDuration: 300, previewDuration: 0, apiCallCount: 1)
        let remaining = totalCreditsSeconds - cost
        #expect(remaining == 10500)
    }

    @Test func exceedsCredits() {
        let credits = UserCredits(credits: 2.1, onetimeCredits: 0.1, recurringCredits: 0.0)
        let totalCreditsSeconds = credits.displayCredits * 3600 // 0.1h = 360s
        let cost = estimatedCost(fileDuration: 600, previewDuration: 0, apiCallCount: 1)
        #expect(cost > totalCreditsSeconds)
    }

    // MARK: - Complex Scenarios

    @Test func perChannelCost() {
        // 1 file × 4 channels, 120s (bumped to 180)
        let cost = estimatedCost(fileDuration: 120, previewDuration: 0, apiCallCount: 4)
        #expect(cost == 180 * 4) // 720
    }
}
