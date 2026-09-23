import Foundation
import AVFoundation
@testable import AuphonicApp

/// In-memory stand-in for the Auphonic API. Records every call the workflow
/// makes and answers status polls and downloads from test-provided data, so
/// `BatchWorkflow` can run end to end without a network.
@MainActor
final class MockAuphonicAPI: AuphonicAPI {

    struct Upload {
        let fieldName: String
        let file: URL
        let fileName: String
        let channels: Int
    }

    final class Production {
        let uuid: String
        let title: String
        let presetUuid: String
        let settings: [String: Any]
        let isMultitrack: Bool
        let trackIds: [String]
        let outputFiles: [[String: Any]]
        var uploads: [Upload] = []
        var started = false
        var polls = 0

        init(uuid: String, title: String, presetUuid: String, settings: [String: Any],
             isMultitrack: Bool, trackIds: [String], outputFiles: [[String: Any]]) {
            self.uuid = uuid; self.title = title; self.presetUuid = presetUuid; self.settings = settings
            self.isMultitrack = isMultitrack; self.trackIds = trackIds; self.outputFiles = outputFiles
        }
    }

    private(set) var productions: [Production] = []
    private(set) var deleted: [String] = []
    private(set) var downloadsReturned: [URL] = []

    /// Polls a production needs before it reports done
    var pollsUntilDone = 1
    /// Thrown by every status poll (e.g. a revoked token)
    var statusError: Error?
    /// Thrown by the first N status polls, then polling proceeds normally
    var transientStatusErrors = 0
    /// Makes every production fail with Auphonic's error status and this message
    var failProcessingWith: String?
    /// Content of a download, by its URL string. Missing entries throw.
    var downloadContent: [String: Data] = [:]

    func production(_ uuid: String) -> Production? { productions.first { $0.uuid == uuid } }

    static func singletrackOutputURL(_ uuid: String) -> String { "mock://\(uuid)/output.wav" }
    static func tracksURL(_ uuid: String) -> String { "mock://\(uuid)/tracks.zip" }
    static func mixdownURL(_ uuid: String) -> String { "mock://\(uuid)/mixdown.wav" }

    // MARK: AuphonicAPI

    func createProduction(presetUuid: String, manualSettings: [String: Any], title: String) async throws -> String {
        let uuid = "prod-\(productions.count + 1)"
        productions.append(Production(uuid: uuid, title: title, presetUuid: presetUuid, settings: manualSettings,
                                      isMultitrack: false, trackIds: [], outputFiles: []))
        return uuid
    }

    func createMultitrackProduction(trackIds: [String], trackAlgorithms: [String: [String: Any]],
                                    masterAlgorithms: [String: Any], outputFiles: [[String: Any]], title: String) async throws -> String {
        let uuid = "prod-\(productions.count + 1)"
        productions.append(Production(uuid: uuid, title: title, presetUuid: "",
                                      settings: ["algorithms": masterAlgorithms, "tracks": trackAlgorithms],
                                      isMultitrack: true, trackIds: trackIds, outputFiles: outputFiles))
        return uuid
    }

    func uploadFiles(productionUuid: String, files: [(fieldName: String, file: URL)],
                     onProgress: (@Sendable (Double) -> Void)?) async throws {
        guard let production = production(productionUuid) else { throw AuphonicAPIClient.APIError.httpError(404, "no such production") }
        for entry in files {
            let channels = (try? AVAudioFile(forReading: entry.file)).map { Int($0.fileFormat.channelCount) } ?? 0
            production.uploads.append(Upload(fieldName: entry.fieldName, file: entry.file,
                                             fileName: entry.file.lastPathComponent, channels: channels))
        }
        onProgress?(1)
    }

    func startProduction(productionUuid: String) async throws {
        production(productionUuid)?.started = true
    }

    func getProductionStatus(productionUuid: String) async throws -> ProductionStatus {
        guard let production = production(productionUuid) else { throw AuphonicAPIClient.APIError.httpError(404, "no such production") }
        production.polls += 1
        if let statusError { throw statusError }
        if transientStatusErrors > 0 {
            transientStatusErrors -= 1
            throw URLError(.timedOut)
        }
        if let message = failProcessingWith {
            return ProductionStatus(statusCode: 2, statusString: "Error", progress: 0, errorMessage: message,
                                    outputFileUrl: "", uuid: productionUuid)
        }
        guard production.polls >= pollsUntilDone else {
            return ProductionStatus(statusCode: 4, statusString: "Audio Processing", progress: 0.5, errorMessage: "",
                                    outputFileUrl: "", uuid: productionUuid)
        }

        var files: [ProductionOutputFile] = []
        if production.isMultitrack {
            files.append(ProductionOutputFile(format: "tracks", filename: "tracks.zip", downloadUrl: Self.tracksURL(productionUuid)))
            if production.outputFiles.contains(where: { ($0["mono_mixdown"] as? Bool) == true }) {
                files.append(ProductionOutputFile(format: "wav-24bit", filename: "mixdown.wav", downloadUrl: Self.mixdownURL(productionUuid)))
            }
        }
        return ProductionStatus(statusCode: 3, statusString: "Done", progress: 1, errorMessage: "",
                                outputFileUrl: production.isMultitrack ? "" : Self.singletrackOutputURL(productionUuid),
                                outputFiles: files, uuid: productionUuid)
    }

    func downloadFile(from urlString: String, onProgress: (@Sendable (Double) -> Void)?) async throws -> URL {
        guard let data = downloadContent[urlString] else {
            throw AuphonicAPIClient.APIError.networkError("no mock content for \(urlString)")
        }
        let ext = URL(string: urlString)?.pathExtension ?? "bin"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mock_download_\(UUID().uuidString)")
            .appendingPathExtension(ext)
        try data.write(to: url)
        downloadsReturned.append(url)
        onProgress?(1)
        return url
    }

    func deleteProduction(uuid: String) async throws {
        deleted.append(uuid)
    }
}
