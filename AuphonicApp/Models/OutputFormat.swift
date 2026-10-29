import Foundation
import AVFoundation

enum OutputFormat: String, CaseIterable, Identifiable {
    case keep = "keep"
    case wav16 = "wav-16bit"
    case wav24 = "wav-24bit"
    case flac = "flac"
    case alac = "alac"
    case mp3 = "mp3"
    case mp3vbr = "mp3-vbr"
    case aac = "aac"
    case vorbis = "vorbis"
    case opus = "opus"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .keep: return "Keep Format"
        case .wav16: return "WAV 16-bit"
        case .wav24: return "WAV 24-bit"
        case .flac: return "FLAC"
        case .alac: return "ALAC"
        case .mp3: return "MP3 (CBR)"
        case .mp3vbr: return "MP3 (VBR)"
        case .aac: return "AAC"
        case .vorbis: return "OGG Vorbis"
        case .opus: return "Opus"
        }
    }

    var hasBitrate: Bool {
        switch self {
        case .mp3, .mp3vbr, .aac, .vorbis, .opus: return true
        default: return false
        }
    }

    var defaultBitrate: Int {
        switch self {
        case .mp3, .mp3vbr: return 112
        case .aac: return 80
        case .vorbis: return 80
        case .opus: return 48
        default: return 0
        }
    }

    var availableBitrates: [Int] {
        switch self {
        case .mp3, .mp3vbr: return [32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
        case .aac: return [24, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
        case .vorbis: return [32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
        case .opus: return [6, 12, 16, 24, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256]
        default: return []
        }
    }

    var fileExtension: String {
        switch self {
        case .keep: return ""
        case .wav16, .wav24: return "wav"
        case .flac: return "flac"
        case .alac: return "m4a"
        case .mp3, .mp3vbr: return "mp3"
        case .aac: return "aac"
        case .vorbis: return "ogg"
        case .opus: return "opus"
        }
    }

    // MARK: - Keep Format

    /// The Auphonic format that reproduces a source file's codec. Auphonic has
    /// no "same as input" audio format (its `input` format returns the
    /// unprocessed original), so "Keep Format" has to be resolved into one of
    /// these before the production is created. PCM containers (WAV, AIFF, CAF)
    /// come back as WAV, 16-bit when the source is 16-bit and 24-bit otherwise.
    static func matching(formatID: AudioFormatID, bitDepth: Int, isFloat: Bool) -> OutputFormat {
        switch formatID {
        case kAudioFormatMPEGLayer3:
            return .mp3
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2,
             kAudioFormatMPEG4AAC_LD, kAudioFormatMPEG4AAC_ELD, kAudioFormatMPEG4AAC_ELD_SBR,
             kAudioFormatMPEG4AAC_ELD_V2:
            return .aac
        case kAudioFormatFLAC:
            return .flac
        case kAudioFormatAppleLossless:
            return .alac
        case kAudioFormatOpus:
            return .opus
        default:
            return (isFloat || bitDepth > 16) ? .wav24 : .wav16
        }
    }

    /// Smallest available bitrate that is not below the source's, so "Keep
    /// Format" does not quietly degrade a lossy file. `nil` for lossless
    /// formats or when the source bitrate cannot be estimated.
    func bitrate(matchingBytes bytes: Int, duration: Double) -> Int? {
        guard hasBitrate, bytes > 0, duration > 0 else { return nil }
        let kbps = Double(bytes) * 8 / duration / 1000
        return availableBitrates.first { Double($0) >= kbps } ?? availableBitrates.last
    }
}
