import Foundation

@Observable
final class SettingsManager {
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let apiToken = "apiToken"
        static let lastPresetUuid = "lastPresetUuid"
        static let lastManualSettings = "lastManualSettings"
        static let audioOutputDevice = "audioOutputDevice"
        static let perChannelMode = "perChannelMode"
        static let deleteProductionsAfterDownload = "deleteProductionsAfterDownload"
    }

    var apiToken: String {
        get { defaults.string(forKey: Keys.apiToken) ?? "" }
        set { defaults.set(newValue, forKey: Keys.apiToken) }
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
