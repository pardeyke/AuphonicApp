import XCTest

/// Base class: every test gets a fresh app launch against the simulated
/// Auphonic API with its own fixture and output folders.
@MainActor
class AppUITestCase: XCTestCase {
    private(set) var session: AppSession!

    var app: XCUIApplication { session.app }

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        session?.terminate()
        session = nil
    }

    /// Creates the session; write fixtures, then call `session.launch()`
    @discardableResult
    func makeSession(mode: AppSession.Mode = .standard, token: String? = "uitest-token",
                     scenario: String = "", deleteAfterDownload: Bool = false) -> AppSession {
        session = AppSession(mode: mode, token: token, scenario: scenario, deleteAfterDownload: deleteAfterDownload)
        return session
    }

    /// Stereo 24-bit field takes, two seconds each, timecodes 10:00 / 10:05 …
    func makeStereoTakes(_ count: Int, format: WavFixture.SampleFormat = .int24) throws -> [URL] {
        try (1...count).map { index in
            try session.makeWav(String(format: "take_%02d.wav", index), WavFixture(
                channels: 2, format: format, seconds: 2,
                timeReference: WavFixture.timeReference(h: 10, m: 5 * (index - 1), s: 0)))
        }
    }
}
