import Testing
@testable import AuphonicApp

struct OutputFormatTests {

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

    // MARK: - Resolve Keep

    @Test func resolveKeepForWav() {
        let result = OutputFormat.resolveKeep(for: "wav")
        #expect(result.format == "wav-24bit")
        #expect(result.targetExtension == nil)
    }

    @Test func resolveKeepForFlac() {
        let result = OutputFormat.resolveKeep(for: "flac")
        #expect(result.format == "flac")
        #expect(result.targetExtension == nil)
    }

    @Test func resolveKeepForMp3() {
        let result = OutputFormat.resolveKeep(for: "mp3")
        #expect(result.format == "mp3")
        #expect(result.targetExtension == nil)
    }

    @Test func resolveKeepForAac() {
        let result = OutputFormat.resolveKeep(for: "aac")
        #expect(result.format == "aac")
        #expect(result.targetExtension == nil)
    }

    @Test func resolveKeepForM4a() {
        let result = OutputFormat.resolveKeep(for: "m4a")
        #expect(result.format == "aac")
        #expect(result.targetExtension == nil)
    }

    @Test func resolveKeepForOgg() {
        let result = OutputFormat.resolveKeep(for: "ogg")
        #expect(result.format == "vorbis")
        #expect(result.targetExtension == nil)
    }

    @Test func resolveKeepForOpus() {
        let result = OutputFormat.resolveKeep(for: "opus")
        #expect(result.format == "opus")
        #expect(result.targetExtension == nil)
    }

    @Test func resolveKeepForAlac() {
        let result = OutputFormat.resolveKeep(for: "alac")
        #expect(result.format == "alac")
        #expect(result.targetExtension == nil)
    }

    @Test func resolveKeepForAiff() {
        let resultAif = OutputFormat.resolveKeep(for: "aif")
        #expect(resultAif.format == "wav-24bit")
        #expect(resultAif.targetExtension == "aif")

        let resultAiff = OutputFormat.resolveKeep(for: "aiff")
        #expect(resultAiff.format == "wav-24bit")
        #expect(resultAiff.targetExtension == "aif")
    }

    @Test func resolveKeepCaseInsensitive() {
        let result = OutputFormat.resolveKeep(for: "WAV")
        #expect(result.format == "wav-24bit")
    }

    @Test func resolveKeepUnknownExtension() {
        let result = OutputFormat.resolveKeep(for: "xyz")
        #expect(result.format == "wav-24bit")
        #expect(result.targetExtension == nil)
    }

    // MARK: - All Cases

    @Test func allCasesCount() {
        #expect(OutputFormat.allCases.count == 10)
    }
}
