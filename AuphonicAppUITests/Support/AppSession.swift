import XCTest

/// One launch of the app in UI test mode, with its own fixture and output
/// folders and access to the simulated API's call log.
///
/// The runner and the app are both sandboxed: the runner can read the whole
/// disk but only write its own container, the app can only read what the
/// user picked. So fixtures are written into the runner's temp folder and
/// handed to the app through the real open panel (`addFiles`), and the
/// output folder is picked the same way when processing starts.
@MainActor
final class AppSession {
    /// Mirrors `UITestEnvironment.Key` in the app target
    enum Key {
        static let runID = "AUPHONIC_UITEST_RUN_ID"
        static let token = "AUPHONIC_UITEST_TOKEN"
        static let scenario = "AUPHONIC_UITEST_SCENARIO"
        static let mode = "AUPHONIC_UITEST_MODE"
        static let deleteAfterDownload = "AUPHONIC_UITEST_DELETE_AFTER_DOWNLOAD"
    }

    enum Mode: String {
        case standard
        case mixPreparation
    }

    let app = XCUIApplication()
    let runID = "run-" + UUID().uuidString.prefix(8)

    /// Fixtures for this test (runner container, readable by the app once picked)
    let inputDirectory: URL
    /// Destination the app writes into (picked through the panel)
    let outputDirectory: URL

    init(mode: Mode = .standard, token: String? = "uitest-token", scenario: String = "", deleteAfterDownload: Bool = false) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuphonicUITests", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
        inputDirectory = root.appendingPathComponent("input", isDirectory: true)
        outputDirectory = root.appendingPathComponent("output", isDirectory: true)
        try? FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        app.launchArguments = ["-AuphonicUITestMode"]
        app.launchEnvironment = [
            Key.runID: runID,
            Key.token: token ?? "",
            Key.scenario: scenario,
            Key.mode: mode.rawValue,
            Key.deleteAfterDownload: deleteAfterDownload ? "1" : "0"
        ]
    }

    func launch() {
        app.launch()
        if !app.windows.firstMatch.waitForExistence(timeout: 10) {
            XCTFail("main window did not appear:\n\(app.debugDescription)")
        }
        // Other apps' windows on top of ours make XCUITest run its
        // interruption handling, which can dismiss the open panel. Hide them
        // (App menu ▸ Hide Others); they stay open.
        app.activate()
        app.typeKey("h", modifierFlags: [.command, .option])
    }

    func terminate() {
        app.terminate()
        try? FileManager.default.removeItem(at: inputDirectory.deletingLastPathComponent())
    }

    // MARK: - Fixtures

    @discardableResult
    func makeWav(_ name: String, _ fixture: WavFixture, in directory: URL? = nil) throws -> URL {
        try fixture.write(to: (directory ?? inputDirectory).appendingPathComponent(name))
    }

    /// Copies a recording from the repository's untracked `Testfiles/`
    /// folder; `nil` when it is not there (other machines, CI)
    func copyTestfile(_ name: String) -> URL? {
        let source = Self.testfilesDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        let target = inputDirectory.appendingPathComponent(name)
        try? FileManager.default.copyItem(at: source, to: target)
        return target
    }

    static let testfilesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()    // Support
        .deletingLastPathComponent()    // AuphonicAppUITests
        .deletingLastPathComponent()    // repo
        .appendingPathComponent("Testfiles", isDirectory: true)

    // MARK: - Outputs

    var outputFiles: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    var outputNames: [String] { outputFiles.map(\.lastPathComponent) }

    // MARK: - Simulated API log

    /// The app's own temp folder for this launch (inside its container)
    var appWorkDirectory: URL {
        let home = String(cString: getpwuid(getuid())!.pointee.pw_dir)
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Containers/com.kpgbr.AuphonicApp/Data/tmp/UITest", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
    }

    /// Every call the app made to the simulated Auphonic API, in order
    var apiLog: [[String: Any]] {
        guard let data = try? Data(contentsOf: appWorkDirectory.appendingPathComponent("api-log.json")),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return entries
    }

    func apiCalls(_ name: String) -> [[String: Any]] {
        apiLog.filter { $0["call"] as? String == name }
    }
}
