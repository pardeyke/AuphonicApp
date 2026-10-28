import Testing
import Foundation
import AVFoundation
@testable import AuphonicApp

/// Regression tests for the player's background waveform scan.
struct WaveformGenerationTests {

    /// Integer division leaves `totalFrames % resolution` frames past the last
    /// bin. When a read chunk starts inside that tail, the first bin index is
    /// past the end of the array and `firstBin...lastBin` used to trap.
    /// 1,048,576 + 100 frames puts the second 1M-frame chunk exactly there.
    @Test func chunkStartingInTailDoesNotTrap() throws {
        let url = tempWavURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = 1_048_576 + 100
        try makeWav(url: url, channels: 1, frames: frames, bitDepth: 32, isFloat: true) { _ in 0.5 }

        let waveforms = try #require(AudioPlayerService.generateAllWaveforms(url: url, resolution: 8192))

        // Combined lane plus one channel lane, every bin filled with the constant level
        #expect(waveforms.count == 2)
        let channel = try #require(waveforms[1])
        #expect(channel.count == 8192)
        #expect(channel.allSatisfy { abs($0 - 0.5) < 0.0001 })
        #expect(waveforms[0] == channel)
    }

    /// Files shorter than the resolution map one frame per bin; the unused
    /// bins stay silent and nothing traps.
    @Test func shortFileFillsLeadingBinsOnly() throws {
        let url = tempWavURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try makeWav(url: url, channels: 2, frames: 100, bitDepth: 32, isFloat: true) { ch in ch == 0 ? 0.25 : 0.75 }

        let waveforms = try #require(AudioPlayerService.generateAllWaveforms(url: url, resolution: 8192))

        let left = try #require(waveforms[1])
        let right = try #require(waveforms[2])
        let combined = try #require(waveforms[0])
        #expect(left[..<100].allSatisfy { abs($0 - 0.25) < 0.0001 })
        #expect(right[..<100].allSatisfy { abs($0 - 0.75) < 0.0001 })
        #expect(combined[..<100].allSatisfy { abs($0 - 0.75) < 0.0001 })
        #expect(left[100...].allSatisfy { $0 == 0 })
        #expect(combined[100...].allSatisfy { $0 == 0 })
    }
}
