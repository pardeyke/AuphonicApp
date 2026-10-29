import Foundation

/// Launch configuration for UI tests. The test runner launches the app with
/// `-AuphonicUITestMode` and a few environment variables; the app then runs
/// against `SimulatedAuphonicAPI` with a throwaway settings suite and an
/// in-memory token, so a test never touches the network, the user's
/// Keychain or their preferences. Without the launch argument nothing here
/// has any effect.
enum UITestEnvironment {
    static let launchArgument = "-AuphonicUITestMode"

    /// Environment keys shared with the UI test target (`UITestLaunch.swift`)
    enum Key {
        /// Folder name under the app's temp directory for this launch's API log
        static let runID = "AUPHONIC_UITEST_RUN_ID"
        /// API token to start with; an empty value starts without one
        static let token = "AUPHONIC_UITEST_TOKEN"
        /// Comma-separated `SimulatedAuphonicAPI.Scenario` flags
        static let scenario = "AUPHONIC_UITEST_SCENARIO"
        /// Initial `AppMode` raw value
        static let mode = "AUPHONIC_UITEST_MODE"
        /// "1" switches on "Delete productions after download"
        static let deleteAfterDownload = "AUPHONIC_UITEST_DELETE_AFTER_DOWNLOAD"
    }

    static let isActive = ProcessInfo.processInfo.arguments.contains(launchArgument)

    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// Per-launch working folder inside the app's own container. The test
    /// runner may read it (it gets read access to the whole disk) but not
    /// write it, so everything the runner provides comes through the open
    /// panel instead.
    static var workDirectory: URL {
        let runID = environment[Key.runID] ?? "default"
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("UITest", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
    }

    /// Status polls are instant in the simulation; no reason to wait 2 s
    static let pollInterval: Duration = .milliseconds(40)

    /// The view model for a UI test launch
    @MainActor
    static func makeViewModel() -> AppViewModel {
        try? FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        let suiteName = "com.kpgbr.AuphonicApp.uitest"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let token = environment[Key.token] ?? "uitest-token"
        let initialToken: String? = token.isEmpty ? nil : token
        let settings = SettingsManager(
            defaults: defaults,
            tokenStore: InMemoryTokenStore(token: initialToken)
        )
        if let rawMode = environment[Key.mode], let mode = AppMode(rawValue: rawMode) {
            settings.appMode = mode
        }
        settings.deleteProductionsAfterDownload = environment[Key.deleteAfterDownload] == "1"

        let api = SimulatedAuphonicAPI(
            scenario: SimulatedAuphonicAPI.Scenario(environment[Key.scenario] ?? ""),
            workDirectory: workDirectory
        )
        return AppViewModel(settingsManager: settings, apiClient: api, pollInterval: pollInterval)
    }
}

/// Token store that lives only as long as the process (UI test launches
/// and unit tests)
final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private(set) var token: String?
    init(token: String? = nil) { self.token = token }
    func readToken() -> String? { token }
    func writeToken(_ token: String?) { self.token = token }
}
