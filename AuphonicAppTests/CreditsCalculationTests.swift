import Testing
import Foundation
@testable import AuphonicApp

/// Tests for the credit calculation logic used in CreditsView.
/// The calculation logic is extracted here to test without SwiftUI rendering.
struct CreditsCalculationTests {

    private static let minimumBilledSeconds: Double = 180

    /// Mirror the estimatedCost calculation from CreditsView
    private func estimatedCost(fileDurations: [Double], previewDuration: Double, channelMultiplier: Int) -> Double {
        let multiplier = Double(max(1, channelMultiplier))
        return fileDurations.reduce(0.0) { total, duration in
            let effective = previewDuration > 0 ? min(previewDuration, duration) : duration
            let billed = max(effective, Self.minimumBilledSeconds)
            return total + billed * multiplier
        }
    }

    private func hasMinimumApplied(fileDurations: [Double], previewDuration: Double) -> Bool {
        fileDurations.contains { duration in
            let effective = previewDuration > 0 ? min(previewDuration, duration) : duration
            return effective < Self.minimumBilledSeconds
        }
    }

    // MARK: - Basic Cost Calculation

    @Test func singleFileLongerThanMinimum() {
        let cost = estimatedCost(fileDurations: [300], previewDuration: 0, channelMultiplier: 1)
        #expect(cost == 300)
    }

    @Test func singleFileShorterThanMinimum() {
        let cost = estimatedCost(fileDurations: [60], previewDuration: 0, channelMultiplier: 1)
        #expect(cost == 180) // 3-minute minimum
    }

    @Test func singleFileExactlyMinimum() {
        let cost = estimatedCost(fileDurations: [180], previewDuration: 0, channelMultiplier: 1)
        #expect(cost == 180)
    }

    @Test func emptyFiles() {
        let cost = estimatedCost(fileDurations: [], previewDuration: 0, channelMultiplier: 1)
        #expect(cost == 0)
    }

    // MARK: - Multiple Files

    @Test func multipleFiles() {
        // 300s + 60s (bumped to 180) = 480
        let cost = estimatedCost(fileDurations: [300, 60], previewDuration: 0, channelMultiplier: 1)
        #expect(cost == 480)
    }

    @Test func multipleFilesAllShort() {
        // Each bumped to 180: 3 * 180 = 540
        let cost = estimatedCost(fileDurations: [10, 20, 30], previewDuration: 0, channelMultiplier: 1)
        #expect(cost == 540)
    }

    // MARK: - Preview Duration

    @Test func previewTruncatesDuration() {
        // 600s file with 30s preview → billed as 180 (minimum)
        let cost = estimatedCost(fileDurations: [600], previewDuration: 30, channelMultiplier: 1)
        #expect(cost == 180)
    }

    @Test func previewLongerThanMinimum() {
        // 600s file with 300s preview → billed as 300
        let cost = estimatedCost(fileDurations: [600], previewDuration: 300, channelMultiplier: 1)
        #expect(cost == 300)
    }

    @Test func previewLongerThanFile() {
        // 60s file with 300s preview → min(300,60)=60 → bumped to 180
        let cost = estimatedCost(fileDurations: [60], previewDuration: 300, channelMultiplier: 1)
        #expect(cost == 180)
    }

    // MARK: - Channel Multiplier

    @Test func channelMultiplierDoubles() {
        let cost = estimatedCost(fileDurations: [300], previewDuration: 0, channelMultiplier: 2)
        #expect(cost == 600)
    }

    @Test func channelMultiplierQuadruples() {
        let cost = estimatedCost(fileDurations: [300], previewDuration: 0, channelMultiplier: 4)
        #expect(cost == 1200)
    }

    @Test func channelMultiplierZeroTreatedAsOne() {
        let cost = estimatedCost(fileDurations: [300], previewDuration: 0, channelMultiplier: 0)
        #expect(cost == 300)
    }

    // MARK: - Minimum Applied Detection

    @Test func minimumAppliedForShortFile() {
        #expect(hasMinimumApplied(fileDurations: [60], previewDuration: 0))
    }

    @Test func minimumNotAppliedForLongFile() {
        #expect(!hasMinimumApplied(fileDurations: [300], previewDuration: 0))
    }

    @Test func minimumAppliedWithPreview() {
        #expect(hasMinimumApplied(fileDurations: [600], previewDuration: 30))
    }

    @Test func minimumNotAppliedWithLongPreview() {
        #expect(!hasMinimumApplied(fileDurations: [600], previewDuration: 300))
    }

    @Test func minimumAppliedMixedFiles() {
        #expect(hasMinimumApplied(fileDurations: [300, 60], previewDuration: 0))
    }

    // MARK: - Display Credits

    @Test func displayCreditsCalculation() {
        let credits = UserCredits(credits: 5.0, onetimeCredits: 3.0, recurringCredits: 2.0)
        let totalCreditsSeconds = credits.displayCredits * 3600  // 3h = 10800s
        let cost = estimatedCost(fileDurations: [300], previewDuration: 0, channelMultiplier: 1)
        let remaining = totalCreditsSeconds - cost
        #expect(remaining == 10500)
    }

    @Test func exceedsCredits() {
        let credits = UserCredits(credits: 2.1, onetimeCredits: 0.1, recurringCredits: 0.0)
        let totalCreditsSeconds = credits.displayCredits * 3600 // 0.1h = 360s
        let cost = estimatedCost(fileDurations: [600], previewDuration: 0, channelMultiplier: 1)
        #expect(cost > totalCreditsSeconds)
    }

    // MARK: - Complex Scenarios

    @Test func perChannelBatchCost() {
        // 3 files × 4 channels, each 120s (bumped to 180)
        let cost = estimatedCost(fileDurations: [120, 120, 120], previewDuration: 0, channelMultiplier: 4)
        #expect(cost == 180 * 3 * 4) // 2160
    }
}
