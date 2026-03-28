import Foundation

@Observable
final class AuphonicAPIClient {
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

    func createProduction(presetUuid: String, manualSettings: [String: Any], title: String) async throws -> String {
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

        // Ensure output_files is set
        if body["output_files"] == nil {
            let format = (manualSettings["output_format"] as? String) ?? "wav-24bit"
            var outputFile: [String: Any] = ["format": format]
            if let bitrate = manualSettings["bitrate"] as? String {
                outputFile["bitrate"] = bitrate
            }
            body["output_files"] = [outputFile]
        }

        let json = try await post("/productions.json", body: body)
        guard let data = json["data"] as? [String: Any],
              let uuid = data["uuid"] as? String else {
            throw APIError.decodingError("Missing production UUID in response")
        }
        return uuid
    }

    func uploadFile(productionUuid: String, file: URL, onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        let url = URL(string: "\(baseURL)/production/\(productionUuid)/upload.json")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 300

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fileData = try Data(contentsOf: file)
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"input_file\"; filename=\"\(file.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        // Write body to temp file for upload task (enables progress tracking)
        let tempBody = FileManager.default.temporaryDirectory
            .appendingPathComponent("auphonic_upload_\(UUID().uuidString).tmp")
        try body.write(to: tempBody)
        defer { try? FileManager.default.removeItem(at: tempBody) }

        let delegate = ProgressDelegate(onProgress: onProgress)
        let taskSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { taskSession.finishTasksAndInvalidate() }

        let (data, response) = try await taskSession.upload(for: request, fromFile: tempBody)
        try validateResponse(data: data, response: response)
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

        var outputUrl = ""
        if let outputFiles = data["output_files"] as? [[String: Any]],
           let first = outputFiles.first,
           let downloadUrl = first["download_url"] as? String {
            outputUrl = downloadUrl
        }

        return ProductionStatus(
            statusCode: statusCode,
            statusString: statusString,
            progress: progress,
            errorMessage: errorMessage,
            outputFileUrl: outputUrl,
            uuid: productionUuid
        )
    }

    func downloadFile(from urlString: String, onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
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
            print("[AuphonicAPI] POST \(path): \(bodyStr)")
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
        case 200, 201:
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
            print("[AuphonicAPI] HTTP \(httpResponse.statusCode): \(message)")
            throw APIError.httpError(httpResponse.statusCode, message)
        }
    }
}

// MARK: - Progress Delegate

private final class ProgressDelegate: NSObject, URLSessionTaskDelegate {
    let onProgress: (@Sendable (Double) -> Void)?

    init(onProgress: (@Sendable (Double) -> Void)?) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress?(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
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
