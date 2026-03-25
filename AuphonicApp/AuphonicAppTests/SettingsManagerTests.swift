import Testing
import Foundation
@testable import AuphonicApp

struct SettingsManagerTests {

    /// Use a fresh UserDefaults suite per test to avoid cross-contamination
    private func makeManager(suiteName: String = UUID().uuidString) -> (SettingsManager, UserDefaults) {
        let defaults = UserDefaults(suiteName: suiteName)!
        // SettingsManager uses UserDefaults.standard directly,
        // so we test its behavior through the public API
        let manager = SettingsManager()
        return (manager, defaults)
    }

    // Note: These tests interact with UserDefaults.standard.
    // They clean up after themselves but are best run in isolation.

    @Test func apiTokenPersistence() {
        let manager = SettingsManager()
        let token = "test-token-\(UUID().uuidString)"
        manager.apiToken = token
        #expect(manager.apiToken == token)
        #expect(manager.hasApiToken)

        // Cleanup
        manager.apiToken = ""
    }

    @Test func hasApiTokenEmptyString() {
        let manager = SettingsManager()
        let original = manager.apiToken
        manager.apiToken = ""
        #expect(!manager.hasApiToken)
        manager.apiToken = original
    }

    @Test func lastPresetUuidPersistence() {
        let manager = SettingsManager()
        let uuid = "preset-\(UUID().uuidString)"
        manager.lastPresetUuid = uuid
        #expect(manager.lastPresetUuid == uuid)
        manager.lastPresetUuid = ""
    }

    @Test func perChannelModePersistence() {
        let manager = SettingsManager()
        let original = manager.perChannelMode
        manager.perChannelMode = true
        #expect(manager.perChannelMode == true)
        manager.perChannelMode = false
        #expect(manager.perChannelMode == false)
        manager.perChannelMode = original
    }

    @Test func audioOutputDevicePersistence() {
        let manager = SettingsManager()
        let device = "device-\(UUID().uuidString)"
        manager.audioOutputDevice = device
        #expect(manager.audioOutputDevice == device)
        manager.audioOutputDevice = ""
    }

    @Test func lastManualSettingsPersistence() {
        let manager = SettingsManager()
        let json = "{\"levelerEnabled\":true}"
        manager.lastManualSettings = json
        #expect(manager.lastManualSettings == json)
        manager.lastManualSettings = ""
    }

    @Test func defaultValuesAreEmpty() {
        // Remove all keys to test defaults
        let key = "audioOutputDevice"
        let originalValue = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)

        let manager = SettingsManager()
        #expect(manager.audioOutputDevice == "")

        // Restore
        if let original = originalValue {
            UserDefaults.standard.set(original, forKey: key)
        }
    }
}
