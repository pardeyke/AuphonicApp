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
}
