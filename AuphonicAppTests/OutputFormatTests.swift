import Testing
import AVFoundation
@testable import AuphonicApp

struct OutputFormatTests {

    // MARK: - Keep Format

    /// Every codec Core Audio can hand us maps to the Auphonic format that
    /// reproduces it; PCM containers become WAV of the matching bit depth
    @Test func matchingFormatFollowsTheSourceCodec() {
        #expect(OutputFormat.matching(formatID: kAudioFormatMPEGLayer3, bitDepth: 0, isFloat: false) == .mp3)
        #expect(OutputFormat.matching(formatID: kAudioFormatMPEG4AAC, bitDepth: 0, isFloat: false) == .aac)
        #expect(OutputFormat.matching(formatID: kAudioFormatMPEG4AAC_HE, bitDepth: 0, isFloat: false) == .aac)
        #expect(OutputFormat.matching(formatID: kAudioFormatFLAC, bitDepth: 24, isFloat: false) == .flac)
        #expect(OutputFormat.matching(formatID: kAudioFormatAppleLossless, bitDepth: 0, isFloat: false) == .alac)
        #expect(OutputFormat.matching(formatID: kAudioFormatOpus, bitDepth: 0, isFloat: false) == .opus)
    }

    @Test func pcmSourcesBecomeWavOfTheirBitDepth() {
        #expect(OutputFormat.matching(formatID: kAudioFormatLinearPCM, bitDepth: 16, isFloat: false) == .wav16)
        #expect(OutputFormat.matching(formatID: kAudioFormatLinearPCM, bitDepth: 24, isFloat: false) == .wav24)
        #expect(OutputFormat.matching(formatID: kAudioFormatLinearPCM, bitDepth: 32, isFloat: true) == .wav24)
        // Unknown codecs fall back to the PCM rule rather than to a lossy format
        #expect(OutputFormat.matching(formatID: kAudioFormatMicrosoftGSM, bitDepth: 0, isFloat: false) == .wav16)
    }

    /// "Keep Format" on a lossy file asks for the next available bitrate at
    /// or above the source's, never below it
    @Test func matchingBitrateNeverDegradesTheSource() {
        // 1 MB over 60 s is about 133 kbps; the next MP3 step up is 160
        #expect(OutputFormat.mp3.bitrate(matchingBytes: 1_000_000, duration: 60) == 160)
        // Exactly 128 kbps keeps 128
        #expect(OutputFormat.mp3.bitrate(matchingBytes: 128_000 * 60 / 8, duration: 60) == 128)
        // Beyond the top of the list the top is used
        #expect(OutputFormat.aac.bitrate(matchingBytes: 100_000_000, duration: 60) == 320)
    }

    @Test func matchingBitrateIsNilWhenNotApplicable() {
        #expect(OutputFormat.wav24.bitrate(matchingBytes: 1_000_000, duration: 60) == nil)
        #expect(OutputFormat.flac.bitrate(matchingBytes: 1_000_000, duration: 60) == nil)
        #expect(OutputFormat.mp3.bitrate(matchingBytes: 0, duration: 60) == nil)
        #expect(OutputFormat.mp3.bitrate(matchingBytes: 1_000_000, duration: 0) == nil)
    }

    // MARK: - Raw Values

    @Test func rawValues() {
        #expect(OutputFormat.keep.rawValue == "keep")
        #expect(OutputFormat.wav16.rawValue == "wav-16bit")
        #expect(OutputFormat.wav24.rawValue == "wav-24bit")
        #expect(OutputFormat.flac.rawValue == "flac")
        #expect(OutputFormat.alac.rawValue == "alac")
        #expect(OutputFormat.mp3.rawValue == "mp3")
        #expect(OutputFormat.mp3vbr.rawValue == "mp3-vbr")
        #expect(OutputFormat.aac.rawValue == "aac")
        #expect(OutputFormat.vorbis.rawValue == "vorbis")
        #expect(OutputFormat.opus.rawValue == "opus")
    }

    @Test func identifiable() {
        for format in OutputFormat.allCases {
            #expect(format.id == format.rawValue)
        }
    }

    // MARK: - Display Names

    @Test func displayNames() {
        #expect(OutputFormat.keep.displayName == "Keep Format")
        #expect(OutputFormat.wav16.displayName == "WAV 16-bit")
        #expect(OutputFormat.wav24.displayName == "WAV 24-bit")
        #expect(OutputFormat.flac.displayName == "FLAC")
        #expect(OutputFormat.alac.displayName == "ALAC")
        #expect(OutputFormat.mp3.displayName == "MP3 (CBR)")
        #expect(OutputFormat.mp3vbr.displayName == "MP3 (VBR)")
        #expect(OutputFormat.aac.displayName == "AAC")
        #expect(OutputFormat.vorbis.displayName == "OGG Vorbis")
        #expect(OutputFormat.opus.displayName == "Opus")
    }

    // MARK: - Has Bitrate

    @Test func hasBitrate() {
        let withBitrate: [OutputFormat] = [.mp3, .mp3vbr, .aac, .vorbis, .opus]
        let withoutBitrate: [OutputFormat] = [.keep, .wav16, .wav24, .flac, .alac]

        for format in withBitrate {
            #expect(format.hasBitrate, "Expected \(format) to have bitrate")
        }
        for format in withoutBitrate {
            #expect(!format.hasBitrate, "Expected \(format) to not have bitrate")
        }
    }

    // MARK: - Default Bitrate

    @Test func defaultBitrates() {
        #expect(OutputFormat.mp3.defaultBitrate == 112)
        #expect(OutputFormat.mp3vbr.defaultBitrate == 112)
        #expect(OutputFormat.aac.defaultBitrate == 80)
        #expect(OutputFormat.vorbis.defaultBitrate == 80)
        #expect(OutputFormat.opus.defaultBitrate == 48)
        #expect(OutputFormat.wav24.defaultBitrate == 0)
        #expect(OutputFormat.keep.defaultBitrate == 0)
    }

    // MARK: - Available Bitrates

    @Test func availableBitratesNonEmpty() {
        #expect(!OutputFormat.mp3.availableBitrates.isEmpty)
        #expect(!OutputFormat.mp3vbr.availableBitrates.isEmpty)
        #expect(!OutputFormat.aac.availableBitrates.isEmpty)
        #expect(!OutputFormat.vorbis.availableBitrates.isEmpty)
        #expect(!OutputFormat.opus.availableBitrates.isEmpty)
    }

    @Test func availableBitratesEmptyForLossless() {
        #expect(OutputFormat.keep.availableBitrates.isEmpty)
        #expect(OutputFormat.wav16.availableBitrates.isEmpty)
        #expect(OutputFormat.wav24.availableBitrates.isEmpty)
        #expect(OutputFormat.flac.availableBitrates.isEmpty)
        #expect(OutputFormat.alac.availableBitrates.isEmpty)
    }

    @Test func defaultBitrateIsInAvailableList() {
        for format in OutputFormat.allCases where format.hasBitrate {
            #expect(format.availableBitrates.contains(format.defaultBitrate),
                    "\(format) default bitrate \(format.defaultBitrate) not in available list")
        }
    }

    @Test func bitratesAreSorted() {
        for format in OutputFormat.allCases where format.hasBitrate {
            #expect(format.availableBitrates == format.availableBitrates.sorted(),
                    "\(format) bitrates are not sorted")
        }
    }

    // MARK: - File Extensions

    @Test func fileExtensions() {
        #expect(OutputFormat.keep.fileExtension == "")
        #expect(OutputFormat.wav16.fileExtension == "wav")
        #expect(OutputFormat.wav24.fileExtension == "wav")
        #expect(OutputFormat.flac.fileExtension == "flac")
        #expect(OutputFormat.alac.fileExtension == "m4a")
        #expect(OutputFormat.mp3.fileExtension == "mp3")
        #expect(OutputFormat.mp3vbr.fileExtension == "mp3")
        #expect(OutputFormat.aac.fileExtension == "aac")
        #expect(OutputFormat.vorbis.fileExtension == "ogg")
        #expect(OutputFormat.opus.fileExtension == "opus")
    }

    // MARK: - All Cases

    @Test func allCasesCount() {
        #expect(OutputFormat.allCases.count == 10)
    }
}
