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

