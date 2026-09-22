import Testing
import Foundation
@testable import AuphonicApp

// MARK: - Mock URL Protocol

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var mockResponses: [String: (Data, HTTPURLResponse)] = [:]

    static func register(path: String, json: [String: Any], statusCode: Int = 200) {
        let data = try! JSONSerialization.data(withJSONObject: json)
        let url = URL(string: "https://auphonic.com/api\(path)")!
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        mockResponses[path] = (data, response)
    }

    static func reset() {
        mockResponses.removeAll()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let apiPath = path.replacingOccurrences(of: "/api", with: "", options: .anchored)

        if let (data, response) = Self.mockResponses[apiPath] ?? Self.mockResponses[path] {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
        } else {
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

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
        config.configure(count: 2, trackNames: ["BOOM", "LAV"], bitDepth: 32)
        config.channels[0].enabled = true
        config.channels[1].enabled = false
        config.sharedOptions.noiseEnabled = true

        let job = try! #require(config.uploadJobs.first)
        let body = AuphonicAPIClient.productionRequestBody(
            presetUuid: config.presetUuidForJob(job),
            manualSettings: config.settingsForJob(job),
            title: "take_ch1"
        )

        let files = body["output_files"] as? [[String: Any]]
        #expect(files?.count == 1)
        #expect(files?.first?["format"] as? String == "wav-24bit")
        #expect(body["bitrate"] == nil)
    }
}
