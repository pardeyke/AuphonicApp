import Foundation

/// The two ways the app can work with a batch of files.
enum AppMode: String, CaseIterable, Identifiable {
    /// Send whole files to Auphonic and save the processed result in the
    /// format you choose. No channel surgery, no grouping.
    case standard

    /// Film/mix workflow: replace individual channels inside untouched copies
    /// of the originals, configured per timecode/channel-count group.
    case mixPreparation

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .mixPreparation: return "Mix Preparation"
        }
    }

    var summary: String {
        switch self {
        case .standard:
            return "Upload each file to Auphonic and download the processed result in the output format you pick."
        case .mixPreparation:
            return "Process single channels of multichannel WAV recordings and write them back into untouched copies of the originals, grouped by timecode and channel count."
        }
    }
}
