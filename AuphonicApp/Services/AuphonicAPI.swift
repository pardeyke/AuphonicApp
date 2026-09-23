import Foundation

/// The part of the Auphonic API the batch engine drives. `AuphonicAPIClient`
/// is the real implementation; tests substitute a mock so the whole
/// workflow (extraction, upload, polling, download, write-back, cleanup) can
/// run without a network.
protocol AuphonicAPI: AnyObject {
    func createProduction(presetUuid: String, manualSettings: [String: Any], title: String) async throws -> String

    func createMultitrackProduction(
        trackIds: [String],
        trackAlgorithms: [String: [String: Any]],
        masterAlgorithms: [String: Any],
        outputFiles: [[String: Any]],
        title: String
    ) async throws -> String

    func uploadFiles(
        productionUuid: String,
        files: [(fieldName: String, file: URL)],
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws

    func startProduction(productionUuid: String) async throws
    func getProductionStatus(productionUuid: String) async throws -> ProductionStatus
    func downloadFile(from urlString: String, onProgress: (@Sendable (Double) -> Void)?) async throws -> URL
    func deleteProduction(uuid: String) async throws
}

extension AuphonicAPI {
    /// Singletrack productions take exactly one file under the `input_file` field
    func uploadFile(productionUuid: String, file: URL, onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        try await uploadFiles(productionUuid: productionUuid,
                              files: [(fieldName: "input_file", file: file)],
                              onProgress: onProgress)
    }

    func uploadFiles(productionUuid: String, files: [(fieldName: String, file: URL)]) async throws {
        try await uploadFiles(productionUuid: productionUuid, files: files, onProgress: nil)
    }

    func downloadFile(from urlString: String) async throws -> URL {
        try await downloadFile(from: urlString, onProgress: nil)
    }
}
