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

/// One result file of a production (mixdown, individual-tracks zip, ...)
struct ProductionOutputFile {
    let format: String          // e.g. "wav-24bit", "tracks"
    let filename: String
    let downloadUrl: String

    /// True for the zipped individual tracks of a multitrack production
    var isTracksArchive: Bool {
        format == "tracks" || filename.lowercased().hasSuffix(".zip")
    }
}

/// One input track of a multitrack production
struct MultitrackTrackSpec {
    let id: String                      // form field name used for the upload
    let file: URL
    let algorithms: [String: Any]
}

struct ProductionStatus {
    let statusCode: Int
    let statusString: String
    let progress: Double       // 0.0 - 1.0
    let errorMessage: String
    let outputFileUrl: String
    let outputFiles: [ProductionOutputFile]
    let uuid: String

    init(
        statusCode: Int,
        statusString: String,
        progress: Double,
        errorMessage: String,
        outputFileUrl: String,
        outputFiles: [ProductionOutputFile] = [],
        uuid: String
    ) {
        self.statusCode = statusCode
        self.statusString = statusString
        self.progress = progress
        self.errorMessage = errorMessage
        self.outputFileUrl = outputFileUrl
        self.outputFiles = outputFiles
        self.uuid = uuid
    }

    /// Auphonic production status codes (GET /api/info/production_status.json):
    ///  0 File Upload, 1 Waiting, 2 Error, 3 Done, 4 Audio Processing,
    ///  5 Audio Encoding, 6 Outgoing File Transfer, 7 Audio Mono Mixdown,
    ///  8 Split Audio On Chapter Marks, 9 Incomplete, 10 Production Not
    ///  Started Yet, 11 Production Outdated, 12 Incoming File Transfer,
    ///  13 Stopping the Production, 14 Speech Recognition, 15 Production
    ///  Changed, 98 Empty Production.
    ///
    /// Only 2, 9, 11 and 98 are terminal failures. A production that fails
    /// while processing reports 2, which the old `>= 9` rule polled until the
    /// timeout; 12–15 are ordinary intermediate states, not errors.
    static let errorStatusCodes: Set<Int> = [2, 9, 11, 98]
    static let processingStatusCodes: Set<Int> = [4, 5, 6, 7, 8, 12, 13, 14, 15]

    var isDone: Bool { statusCode == 3 }
    var isError: Bool { Self.errorStatusCodes.contains(statusCode) }
    var isProcessing: Bool { Self.processingStatusCodes.contains(statusCode) }

    /// Human-readable reason for a failed production: Auphonic's message when
    /// it has one, else the status name ("Incomplete", "Production Outdated").
    var failureDescription: String {
        if !errorMessage.isEmpty { return errorMessage }
        if !statusString.isEmpty { return statusString }
        return "Processing failed"
    }
}

