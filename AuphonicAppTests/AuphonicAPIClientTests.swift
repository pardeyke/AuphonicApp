import Testing
import Foundation
@testable import AuphonicApp

struct AuphonicAPIClientTests {

    // MARK: - Error Descriptions

    @Test func errorDescriptions() {
        #expect(AuphonicAPIClient.APIError.noToken.errorDescription == "No API token configured")
        #expect(AuphonicAPIClient.APIError.invalidToken.errorDescription == "Invalid API token")
        #expect(AuphonicAPIClient.APIError.httpError(500, "Server error").errorDescription == "Server error")
        #expect(AuphonicAPIClient.APIError.httpError(500, "").errorDescription == "HTTP error 500")
        #expect(AuphonicAPIClient.APIError.networkError("timeout").errorDescription == "timeout")
        #expect(AuphonicAPIClient.APIError.decodingError("bad json").errorDescription == "Failed to parse response: bad json")
    }

    @Test func deleteProductionThrowsWithoutToken() async {
        let client = AuphonicAPIClient()
        await #expect(throws: AuphonicAPIClient.APIError.self) {
            try await client.deleteProduction(uuid: "abc")
        }
    }

    // MARK: - Token Requirement

    @Test func fetchUserInfoThrowsWithoutToken() async {
        let client = AuphonicAPIClient()
        client.token = ""

        do {
            _ = try await client.fetchUserInfo()
            #expect(Bool(false), "Should have thrown")
        } catch let error as AuphonicAPIClient.APIError {
            if case .noToken = error {
                // Expected
            } else {
                #expect(Bool(false), "Expected noToken, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test func fetchPresetsThrowsWithoutToken() async {
        let client = AuphonicAPIClient()
        client.token = ""

        do {
            _ = try await client.fetchPresets()
            #expect(Bool(false), "Should have thrown")
        } catch let error as AuphonicAPIClient.APIError {
            if case .noToken = error {
                // Expected
            } else {
                #expect(Bool(false), "Expected noToken error")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    @Test func createProductionThrowsWithoutToken() async {
        let client = AuphonicAPIClient()
        client.token = ""

        do {
            _ = try await client.createProduction(presetUuid: "test", manualSettings: [:], title: "Test")
            #expect(Bool(false), "Should have thrown")
        } catch let error as AuphonicAPIClient.APIError {
            if case .noToken = error {
                // Expected
            } else {
                #expect(Bool(false), "Expected noToken error")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    @Test func downloadFileInvalidURL() async {
        let client = AuphonicAPIClient()
        client.token = "test-token"

        do {
            _ = try await client.downloadFile(from: "not a valid url %%")
            #expect(Bool(false), "Should have thrown")
        } catch let error as AuphonicAPIClient.APIError {
            if case .networkError = error {
                // Expected
            } else {
                #expect(Bool(false), "Expected networkError")
            }
        } catch {
            // Other errors also acceptable for invalid URL
        }
    }

    // MARK: - Token Assignment

    @Test func tokenAssignment() {
        let client = AuphonicAPIClient()
        #expect(client.token == "")
        client.token = "my-secret-token"
        #expect(client.token == "my-secret-token")
    }

    // MARK: - Production Request Body

    /// Standard mode "Keep Format" must not send `output_files`; the client
    /// used to inject wav-24bit here, which turned every MP3 into a WAV.
    @Test func keepFormatSendsNoOutputFiles() {
        let config = StandardModeConfig()
        config.options.levelerEnabled = true

        let body = AuphonicAPIClient.productionRequestBody(
            presetUuid: "",
            manualSettings: config.productionSettings,
            title: "interview"
        )

        #expect(body["output_files"] == nil)
        #expect(body["output_format"] == nil)
        #expect(body["preset"] == nil)
        #expect(body["title"] as? String == "interview")
        #expect(body["output_basename"] as? String == "interview")
        #expect((body["algorithms"] as? [String: Any])?["leveler"] as? Bool == true)
    }

    /// A preset with "Keep Format" keeps the preset's own output files
    @Test func presetWithKeepFormatSendsOnlyPreset() {
        let config = StandardModeConfig()
        config.selectedPresetUuid = "preset-123"

        let body = AuphonicAPIClient.productionRequestBody(
            presetUuid: config.presetUuidForProduction,
            manualSettings: config.productionSettings,
            title: "take"
        )

        #expect(body["preset"] as? String == "preset-123")
        #expect(body["output_files"] == nil)
    }

    @Test func explicitFormatSendsOutputFilesWithBitrate() {
        let config = StandardModeConfig()
        config.options.outputFormat = .mp3
        config.options.bitrate = 128

        let body = AuphonicAPIClient.productionRequestBody(
            presetUuid: "",
            manualSettings: config.productionSettings,
            title: "take"
        )

        let files = body["output_files"] as? [[String: Any]]
        #expect(files?.count == 1)
        #expect(files?.first?["format"] as? String == "mp3")
        #expect(files?.first?["bitrate"] as? String == "128")
    }

    /// Mix Preparation always forces WAV so the channel can be written back
    @Test func mixPreparationJobAlwaysSendsForcedWav() {
        let config = ChannelConfig()
        config.configure(count: 2, trackNames: ["BOOM", "LAV"])
        config.channels[0].enabled = true
        config.channels[1].enabled = false
        config.sharedOptions.noiseEnabled = true

        let job = try! #require(config.uploadJobs.first)
        let body = AuphonicAPIClient.productionRequestBody(
            presetUuid: config.presetUuidForJob(job),
            manualSettings: config.settingsForJob(job, bitDepth: 32),
            title: "take_ch1"
        )

        let files = body["output_files"] as? [[String: Any]]
        #expect(files?.count == 1)
        #expect(files?.first?["format"] as? String == "wav-24bit")
        #expect(body["bitrate"] == nil)
    }

    // MARK: - Multipart body

    private func stage(_ parts: [AuphonicAPIClient.MultipartFile], boundary: String = "BOUNDARY") throws -> Data {
        let body = FileManager.default.temporaryDirectory.appendingPathComponent("body_\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: body) }
        try AuphonicAPIClient.stageMultipartBody(parts, boundary: boundary, to: body)
        return try Data(contentsOf: body)
    }

    private func tempFile(named name: String, contents: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mp_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    @Test func multipartBodyLayout() throws {
        let a = try tempFile(named: "Ch_1_BOOM.wav", contents: Data("AAAA".utf8))
        let b = try tempFile(named: "Ch_2_LAV.wav", contents: Data([0x00, 0xFF, 0x10]))
        defer { for u in [a, b] { try? FileManager.default.removeItem(at: u.deletingLastPathComponent()) } }

        let body = try stage([.init(fieldName: "Ch_1_BOOM", file: a), .init(fieldName: "Ch_2_LAV", file: b)])
        let pieces: [Data] = [
            Data("--BOUNDARY\r\n".utf8),
            Data("Content-Disposition: form-data; name=\"Ch_1_BOOM\"; filename=\"Ch_1_BOOM.wav\"\r\n".utf8),
            Data("Content-Type: application/octet-stream\r\n\r\n".utf8),
            Data("AAAA".utf8), Data("\r\n".utf8),
            Data("--BOUNDARY\r\n".utf8),
            Data("Content-Disposition: form-data; name=\"Ch_2_LAV\"; filename=\"Ch_2_LAV.wav\"\r\n".utf8),
            Data("Content-Type: application/octet-stream\r\n\r\n".utf8),
            Data([0x00, 0xFF, 0x10]), Data("\r\n".utf8),
            Data("--BOUNDARY--\r\n".utf8)
        ]
        let expected = pieces.reduce(Data()) { $0 + $1 }
        #expect(body == expected)
    }

    /// Files larger than one 4 MB chunk are copied completely
    @Test func multipartBodyCopiesLargeFilesInChunks() throws {
        var payload = Data(count: 9 * 1024 * 1024 + 123)
        payload[0] = 1; payload[payload.count - 1] = 2
        let file = try tempFile(named: "big.wav", contents: payload)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let body = try stage([.init(fieldName: "input_file", file: file)])
        let headerEnd = body.range(of: Data("\r\n\r\n".utf8))!.upperBound
        let copied = body[headerEnd..<(headerEnd + payload.count)]
        #expect(copied.count == payload.count)
        #expect(copied.first == 1)
        #expect(copied.last == 2)
        #expect(body.suffix(from: headerEnd + payload.count) == Data("\r\n--BOUNDARY--\r\n".utf8))
    }

    /// A quote or line break in a user's file name must not break the header
    @Test func multipartFilenameIsEscaped() {
        #expect(AuphonicAPIClient.multipartFilename("take \"one\".wav") == "take %22one%22.wav")
        #expect(AuphonicAPIClient.multipartFilename("a\r\nb.wav") == "a%0D%0Ab.wav")
        #expect(AuphonicAPIClient.multipartFilename("50%.wav") == "50%25.wav")
        #expect(AuphonicAPIClient.multipartFilename("plain-name_01.wav") == "plain-name_01.wav")
    }
}
