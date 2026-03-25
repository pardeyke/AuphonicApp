import Foundation

struct AuphonicPreset: Identifiable, Hashable {
    let uuid: String
    let name: String
    var id: String { uuid }
}

struct UserCredits {
    let credits: Double        // total hours
    let onetimeCredits: Double
    let recurringCredits: Double

    /// Display credits minus 2 free watermark hours
    var displayCredits: Double {
        max(0, credits - 2.0)
    }
}

struct ProductionStatus {
    let statusCode: Int
    let statusString: String
    let progress: Double       // 0.0 - 1.0
    let errorMessage: String
    let outputFileUrl: String
    let uuid: String

    var isDone: Bool { statusCode == 3 }
    var isError: Bool { statusCode >= 9 }
    var isProcessing: Bool { statusCode == 4 || statusCode == 5 || statusCode == 6 || statusCode == 7 || statusCode == 8 }
}

enum ProcessingState: Equatable {
    case idle
    case extractingChannel
    case trimming
    case creatingProduction
    case uploading
    case starting
    case processing
    case downloading
    case converting
    case saving
    case done
    case error(String)

    var isActive: Bool {
        switch self {
        case .idle, .done, .error: return false
        default: return true
        }
    }

    var statusText: String {
        switch self {
        case .idle: return "Ready"
        case .extractingChannel: return "Extracting channel..."
        case .trimming: return "Trimming preview..."
        case .creatingProduction: return "Creating production..."
        case .uploading: return "Uploading..."
        case .starting: return "Starting production..."
        case .processing: return "Processing..."
        case .downloading: return "Downloading..."
        case .converting: return "Converting format..."
        case .saving: return "Saving..."
        case .done: return "Done"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

struct FileResult: Identifiable {
    let id = UUID()
    let inputFile: URL
    var outputFile: URL?
    var success: Bool
    var errorMessage: String?
}

struct ChannelJob {
    let channel: Int           // 1-based
    let presetUuid: String
    let settings: [String: Any]
}

struct PerChannelFileJob {
    let inputFile: URL
    let channels: [ChannelJob]
}
