import Foundation
import UniformTypeIdentifiers

/// Which files the app accepts.
///
/// Standard mode takes everything Core Audio can decode — WAV/BWF, AIFF/AIFC,
/// CAF, MP3, AAC/M4A, ALAC, FLAC and the rest. Mix Preparation is WAV only:
/// its output is a byte-for-byte copy of the original with single channels
/// patched into the RIFF data chunk, which no other container supports.
///
/// This is only the cheap pre-filter used by the open panel, drag & drop and
/// folder scans. Whether a file really decodes is decided when `AVAudioFile`
/// opens it in `BatchFile.init`, and unreadable files are reported there.
nonisolated enum AudioFileTypes {
    /// Fallback for files whose content type the system cannot resolve, e.g.
    /// recorder cards that hand out extensions without a registered type.
    static let knownExtensions: Set<String> = [
        "wav", "wave", "bwf", "rf64", "w64",
        "aif", "aiff", "aifc", "caf", "au", "snd",
        "mp3", "mp2", "mpa", "m4a", "m4b", "aac", "adts",
        "flac", "alac", "ac3", "eac3", "amr", "3gp", "3g2"
    ]

    /// RIFF/WAV containers — the only ones `ChannelReplacer` can patch
    static let wavExtensions: Set<String> = ["wav", "wave", "bwf", "rf64"]

    /// Content types offered in the open panel (folders are expanded)
    static func openPanelTypes(for mode: AppMode) -> [UTType] {
        switch mode {
        case .standard:
            return [.audio, .folder]
        case .mixPreparation:
            return [.wav, .folder]
        }
    }

    /// True when the URL looks like audio the given mode can work with
    static func isAudioFile(_ url: URL, mode: AppMode = .standard) -> Bool {
        let ext = url.pathExtension.lowercased()

        guard mode == .standard else {
            return wavExtensions.contains(ext)
        }

        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           type.conforms(to: .audio) {
            return true
        }
        return knownExtensions.contains(ext)
    }
}
