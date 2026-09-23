import Foundation
import os

@Observable
final class AuphonicAPIClient: AuphonicAPI {
    private static let logger = Logger(subsystem: "com.kpgbr.AuphonicApp", category: "api")
    private let baseURL = "https://auphonic.com/api"
    private let session = URLSession.shared
    var token: String = ""

    enum APIError: LocalizedError {
        case noToken
        case invalidToken
        case httpError(Int, String)
        case networkError(String)
        case decodingError(String)

        var errorDescription: String? {
            switch self {
            case .noToken: return "No API token configured"
            case .invalidToken: return "Invalid API token"
            case .httpError(let code, let msg): return msg.isEmpty ? "HTTP error \(code)" : msg
            case .networkError(let msg): return msg
            case .decodingError(let msg): return "Failed to parse response: \(msg)"
            }
        }
    }

    // MARK: - User Info

    func fetchUserInfo() async throws -> UserCredits {
        let json = try await get("/user.json")
        guard let data = json["data"] as? [String: Any] else {
            throw APIError.decodingError("Missing data field")
        }
        return UserCredits(
            credits: (data["credits"] as? Double) ?? 0,
            onetimeCredits: (data["onetime_credits"] as? Double) ?? 0,
            recurringCredits: (data["recurring_credits"] as? Double) ?? 0
        )
    }

    // MARK: - Presets

    func fetchPresets() async throws -> [AuphonicPreset] {
        let json = try await get("/presets.json")
        guard let dataArray = json["data"] as? [[String: Any]] else {
            throw APIError.decodingError("Missing data array")
        }
        return dataArray.compactMap { item in
            guard let uuid = item["uuid"] as? String else { return nil }
            let name = (item["preset_name"] as? String) ?? (item["name"] as? String) ?? "Unnamed"
            return AuphonicPreset(uuid: uuid, name: name)
        }
    }

    func fetchPresetDetails(uuid: String) async throws -> [String: Any] {
        let json = try await get("/preset/\(uuid).json")
        guard let data = json["data"] as? [String: Any] else {
            throw APIError.decodingError("Missing data field")
        }
        return data
    }

    func savePreset(name: String, settings: [String: Any]) async throws -> String {
        var body = settings
        body["preset_name"] = name
        let json = try await post("/presets.json", body: body)
        guard let data = json["data"] as? [String: Any],
              let uuid = data["uuid"] as? String else {
            throw APIError.decodingError("Missing preset UUID in response")
        }
        return uuid
    }

    // MARK: - Productions

    /// Request body of a singletrack production. `output_files` is only sent
    /// when the caller asks for a format: Mix Preparation always forces WAV via
    /// `ChannelConfig.settingsForJob`, and Standard mode omits it for "Keep
    /// Format" so Auphonic mirrors the input format (or applies the preset's
    /// own output files) instead of defaulting to WAV.
    nonisolated static func productionRequestBody(presetUuid: String, manualSettings: [String: Any], title: String) -> [String: Any] {
        var body: [String: Any] = [
            "title": title,
            "output_basename": title
        ]

        if !presetUuid.isEmpty {
            body["preset"] = presetUuid
        }

        // Merge manual settings
        for (key, value) in manualSettings {
            body[key] = value
        }

        return body
    }

    func createProduction(presetUuid: String, manualSettings: [String: Any], title: String) async throws -> String {
        let body = Self.productionRequestBody(presetUuid: presetUuid, manualSettings: manualSettings, title: title)
        let json = try await post("/productions.json", body: body)
        guard let data = json["data"] as? [String: Any],
              let uuid = data["uuid"] as? String else {
            throw APIError.decodingError("Missing production UUID in response")
        }
        return uuid
    }

    /// Upload one or more files to a production. Multitrack productions use the
    /// track id as the form field name; singletrack uses "input_file".
    /// The multipart body is streamed to a temp file so large multichannel
    /// takes never have to be held in memory; staging it copies the whole
    /// input once, so that runs off the main actor.
    func uploadFiles(
        productionUuid: String,
        files: [(fieldName: String, file: URL)],
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws {
        guard !token.isEmpty else { throw APIError.noToken }

        let url = URL(string: "\(baseURL)/production/\(productionUuid)/upload.json")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 1800

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let tempBody = FileManager.default.temporaryDirectory
            .appendingPathComponent("auphonic_upload_\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: tempBody) }

        let parts = files.map { MultipartFile(fieldName: $0.fieldName, file: $0.file) }
        try await Task.detached(priority: .userInitiated) {
            try Self.stageMultipartBody(parts, boundary: boundary, to: tempBody)
        }.value

        let delegate = ProgressDelegate(onProgress: onProgress)
        let taskSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { taskSession.finishTasksAndInvalidate() }

        let (data, response) = try await taskSession.upload(for: request, fromFile: tempBody)
        try validateResponse(data: data, response: response)
    }

    struct MultipartFile: Sendable {
        let fieldName: String
        let file: URL
    }

    /// Writes a multipart/form-data body with one file part per entry to
    /// `destination`, copying the files in 4 MB chunks. Checks for
    /// cancellation between chunks so Cancel takes effect during the copy.
    nonisolated static func stageMultipartBody(_ parts: [MultipartFile], boundary: String, to destination: URL) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let body = try? FileHandle(forWritingTo: destination) else {
            throw APIError.networkError("Could not stage upload body")
        }
        defer { try? body.close() }

        for part in parts {
            try Task.checkCancellation()
            var header = "--\(boundary)\r\n"
            header += "Content-Disposition: form-data; name=\"\(part.fieldName)\"; "
            header += "filename=\"\(multipartFilename(part.file.lastPathComponent))\"\r\n"
            header += "Content-Type: application/octet-stream\r\n\r\n"
            try body.write(contentsOf: Data(header.utf8))

            let source = try FileHandle(forReadingFrom: part.file)
            defer { try? source.close() }
            while let chunk = try source.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
                try Task.checkCancellation()
                try body.write(contentsOf: chunk)
            }

            try body.write(contentsOf: Data("\r\n".utf8))
        }
        try body.write(contentsOf: Data("--\(boundary)--\r\n".utf8))
    }

    /// File names go into a quoted header value: a quote, a line break or a
    /// backslash in the name (possible for user files in Standard mode) would
    /// break the part header. Percent-encoded as RFC 7578 recommends.
    nonisolated static func multipartFilename(_ name: String) -> String {
        name.replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\\", with: "%5C")
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
    }

    // MARK: - Multitrack Productions

    /// Create a multitrack production: every track is processed individually
    /// (denoise, leveler, crosstalk damping) and mixed into one master.
    func createMultitrackProduction(
        trackIds: [String],
        trackAlgorithms: [String: [String: Any]],
        masterAlgorithms: [String: Any],
        outputFiles: [[String: Any]],
        title: String
    ) async throws -> String {
        var body: [String: Any] = [
            "is_multitrack": true,
            "title": title,
            "output_basename": title,
            "algorithms": masterAlgorithms,
            "output_files": outputFiles
        ]

        body["multi_input_files"] = trackIds.map { id -> [String: Any] in
            var track: [String: Any] = ["type": "multitrack", "id": id]
            if let algorithms = trackAlgorithms[id] {
                track["algorithms"] = algorithms
            }
            return track
        }

        let json = try await post("/productions.json", body: body)
        guard let data = json["data"] as? [String: Any],
              let uuid = data["uuid"] as? String else {
            throw APIError.decodingError("Missing production UUID in response")
        }
        return uuid
    }

    func startProduction(productionUuid: String) async throws {
        _ = try await post("/production/\(productionUuid)/start.json", body: [:])
    }

    func getProductionStatus(productionUuid: String) async throws -> ProductionStatus {
        let json = try await get("/production/\(productionUuid).json")
        guard let data = json["data"] as? [String: Any] else {
            throw APIError.decodingError("Missing data field")
        }

        let statusCode = (data["status"] as? Int) ?? 0
        let statusString = (data["status_string"] as? String) ?? ""
        let progress = (data["progress"] as? Double) ?? 0
        let errorMessage = (data["error_message"] as? String) ?? ""

        var files: [ProductionOutputFile] = []
        if let outputFiles = data["output_files"] as? [[String: Any]] {
            for entry in outputFiles {
                guard let downloadUrl = entry["download_url"] as? String, !downloadUrl.isEmpty else { continue }
                files.append(ProductionOutputFile(
                    format: (entry["format"] as? String) ?? "",
                    filename: (entry["filename"] as? String) ?? "",
                    downloadUrl: downloadUrl
                ))
            }
        }

        return ProductionStatus(
            statusCode: statusCode,
            statusString: statusString,
            progress: progress,
            errorMessage: errorMessage,
            outputFileUrl: files.first?.downloadUrl ?? "",
            outputFiles: files,
            uuid: productionUuid
        )
    }

    /// Delete a production on Auphonic (housekeeping after successful download)
    func deleteProduction(uuid: String) async throws {
        guard !token.isEmpty else { throw APIError.noToken }

        var request = URLRequest(url: URL(string: "\(baseURL)/production/\(uuid).json")!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        try validateResponse(data: data, response: response)
    }

    func downloadFile(from urlString: String, onProgress: (@Sendable (Double) -> Void)?) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw APIError.networkError("Invalid download URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 300

        let delegate = DownloadProgressDelegate(onProgress: onProgress)
        let downloadSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { downloadSession.finishTasksAndInvalidate() }

        let (tempURL, response) = try await downloadSession.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.networkError("Download failed")
        }

        let ext = url.pathExtension.isEmpty ? "wav" : url.pathExtension
        let destFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("auphonic_download_\(Int64.random(in: 0...Int64.max))")
            .appendingPathExtension(ext)
        try FileManager.default.moveItem(at: tempURL, to: destFile)
        return destFile
    }

    // MARK: - HTTP Helpers

    private func get(_ path: String) async throws -> [String: Any] {
        guard !token.isEmpty else { throw APIError.noToken }

        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        return try parseResponse(data: data, response: response)
    }

    private func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        guard !token.isEmpty else { throw APIError.noToken }

        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        if let bodyStr = String(data: request.httpBody!, encoding: .utf8) {
            Self.logger.debug("POST \(path, privacy: .public): \(bodyStr, privacy: .private)")
        }

        let (data, response) = try await session.data(for: request)
        return try parseResponse(data: data, response: response)
    }

    private func parseResponse(data: Data, response: URLResponse) throws -> [String: Any] {
        try validateResponse(data: data, response: response)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingError("Response is not a JSON object")
        }
        return json
    }

    private func validateResponse(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError("Connection failed. Check your internet.")
        }

        switch httpResponse.statusCode {
        case 200, 201, 204:
            return
        case 401, 403:
            throw APIError.invalidToken
        default:
            var message = ""
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errorMsg = json["error_message"] as? String {
                    message = errorMsg
                } else if let errorMsg = json["error"] as? String {
                    message = errorMsg
                } else if let statusMsg = json["status_text"] as? String {
                    message = statusMsg
                }
                if message.isEmpty, let body = String(data: data, encoding: .utf8) {
                    message = String(body.prefix(500))
                }
            } else if let body = String(data: data, encoding: .utf8) {
                message = String(body.prefix(500))
            }
            Self.logger.error("HTTP \(httpResponse.statusCode): \(message, privacy: .public)")
            throw APIError.httpError(httpResponse.statusCode, message)
        }
    }
}

// MARK: - Progress Delegate

/// URLSession calls its delegates on its own queue, so these must not be
/// main-actor isolated; they only forward to a Sendable closure.
nonisolated private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let onProgress: (@Sendable (Double) -> Void)?

    init(onProgress: (@Sendable (Double) -> Void)?) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress?(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}

nonisolated private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let onProgress: (@Sendable (Double) -> Void)?

    init(onProgress: (@Sendable (Double) -> Void)?) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // handled by the async download(for:) call
    }
}
