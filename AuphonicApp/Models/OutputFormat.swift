import Foundation

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

    /// Resolve "keep" format based on input file extension
    static func resolveKeep(for inputExtension: String) -> (format: String, targetExtension: String?) {
        switch inputExtension.lowercased() {
        case "wav": return ("wav-24bit", nil)
        case "flac": return ("flac", nil)
        case "mp3": return ("mp3", nil)
        case "aac", "m4a": return ("aac", nil)
        case "ogg": return ("vorbis", nil)
        case "opus": return ("opus", nil)
        case "alac": return ("alac", nil)
        case "aif", "aiff": return ("wav-24bit", "aif")
        default: return ("wav-24bit", nil)
        }
    }
}
