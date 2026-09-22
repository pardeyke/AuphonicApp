import Foundation

@Observable
final class SettingsManager {
    private let defaults: UserDefaults
    private let tokenStore: any TokenStore
    /// Keychain reads are not free; the token is read once per session
    private var cachedToken: String?

    /// The app uses the standard defaults and the Keychain; tests pass a
    /// throwaway suite and an in-memory store so they never touch the
    /// user's real settings.
    init(defaults: UserDefaults = .standard, tokenStore: (any TokenStore)? = nil) {
        self.defaults = defaults
        self.tokenStore = tokenStore ?? KeychainTokenStore()
    }

    private enum Keys {
        static let apiToken = "apiToken"
        static let lastPresetUuid = "lastPresetUuid"
        static let lastManualSettings = "lastManualSettings"
        static let audioOutputDevice = "audioOutputDevice"
        static let perChannelMode = "perChannelMode"
        static let deleteProductionsAfterDownload = "deleteProductionsAfterDownload"
        static let appMode = "appMode"
    }

    /// Last used working mode (Standard or Mix Preparation)
    var appMode: AppMode {
        get {
            let stored = defaults.string(forKey: Keys.appMode) ?? ""
            if stored == "api" { return .standard }    // renamed in 2.0
            return AppMode(rawValue: stored) ?? .standard
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.appMode) }
    }

    /// Stored in the Keychain. Versions up to 2.0 kept it as plain text in
    /// the preferences; such a token is moved into the Keychain on first read
    /// and removed from the preferences.
    var apiToken: String {
        get {
            if let cachedToken { return cachedToken }
            var token = tokenStore.readToken() ?? ""
            if token.isEmpty, let legacy = defaults.string(forKey: Keys.apiToken), !legacy.isEmpty {
                token = legacy
                tokenStore.writeToken(legacy)
                defaults.removeObject(forKey: Keys.apiToken)
            }
            cachedToken = token
            return token
        }
        set {
            cachedToken = newValue
            tokenStore.writeToken(newValue.isEmpty ? nil : newValue)
            defaults.removeObject(forKey: Keys.apiToken)
        }
    }

    var hasApiToken: Bool { !apiToken.isEmpty }

    var lastPresetUuid: String {
        get { defaults.string(forKey: Keys.lastPresetUuid) ?? "" }
        set { defaults.set(newValue, forKey: Keys.lastPresetUuid) }
    }

    var lastManualSettings: String {
        get { defaults.string(forKey: Keys.lastManualSettings) ?? "" }
        set { defaults.set(newValue, forKey: Keys.lastManualSettings) }
    }

    var audioOutputDevice: String {
        get { defaults.string(forKey: Keys.audioOutputDevice) ?? "" }
        set { defaults.set(newValue, forKey: Keys.audioOutputDevice) }
    }

    var perChannelMode: Bool {
        get { defaults.bool(forKey: Keys.perChannelMode) }
        set { defaults.set(newValue, forKey: Keys.perChannelMode) }
    }

    /// Housekeeping: delete productions on Auphonic once their output has been
    /// downloaded and written into the local output file
    var deleteProductionsAfterDownload: Bool {
        get { defaults.bool(forKey: Keys.deleteProductionsAfterDownload) }
        set { defaults.set(newValue, forKey: Keys.deleteProductionsAfterDownload) }
    }

}
