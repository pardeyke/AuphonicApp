import Foundation

/// What Auphonic does with the segments its cutters detect
enum CutMode: String, CaseIterable, Identifiable {
    case applyCuts = "apply_cuts"
    case setCutsToSilence = "set_cuts_to_silence"
    case exportUncutAudio = "export_uncut_audio"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .applyCuts: return "Apply Cuts"
        case .setCutsToSilence: return "Set Cuts to Silence"
        case .exportUncutAudio: return "Export Uncut Audio"
        }
    }
}

/// Auphonic's automatic cutting: detect and remove silence, filler words,
/// coughs and music.
///
/// Standard mode only — cutting changes the length of the audio, which would
/// break Mix Preparation's contract that a processed channel lines up
/// sample-for-sample with the original it is patched into.
@Observable
final class CuttingOptions {
    /// Master switch of the card; the individual cutters below only count
    /// while this is on
    var enabled = false

    var cutSilence = false
    var cutFillers = false
    var cutCoughs = false
    var cutMusic = false

    var cutMode: CutMode = .applyCuts
    var fadeTime = 100          // ms, 0-5000

    /// True when at least one cutter actually runs
    var isActive: Bool {
        enabled && (cutSilence || cutFillers || cutCoughs || cutMusic)
    }

    /// Merge the cutting keys into an `algorithms` dictionary. Nothing is
    /// written while inactive, so a preset's own cutting settings survive.
    func apply(to algorithms: inout [String: Any]) {
        guard isActive else { return }

        algorithms["silence_cutter"] = cutSilence
        algorithms["filler_cutter"] = cutFillers
        algorithms["cough_cutter"] = cutCoughs
        algorithms["music_cutter"] = cutMusic
        algorithms["cut_mode"] = cutMode.rawValue
        algorithms["fadetime"] = fadeTime
    }

    /// Restore the UI state from a preset's algorithms
    func applyApiSettings(_ algorithms: [String: Any]) {
        cutSilence = (algorithms["silence_cutter"] as? Bool) ?? false
        cutFillers = (algorithms["filler_cutter"] as? Bool) ?? false
        cutCoughs = (algorithms["cough_cutter"] as? Bool) ?? false
        cutMusic = (algorithms["music_cutter"] as? Bool) ?? false
        enabled = cutSilence || cutFillers || cutCoughs || cutMusic

        if let mode = algorithms["cut_mode"] as? String {
            cutMode = CutMode(rawValue: mode) ?? .applyCuts
        }
        if let fade = algorithms["fadetime"] as? Int {
            fadeTime = fade
        }
    }
}
