import Testing
import Foundation
@testable import AuphonicApp

/// Every test gets its own UserDefaults suite, removed again afterwards. The
/// test host is the sandboxed app itself, so writing to `.standard` here
/// would overwrite the user's real settings — an earlier version of these
/// tests wiped the API token that way.
struct SettingsManagerTests {

    private struct Sandbox {
        let manager: SettingsManager
        let defaults: UserDefaults
        let suiteName: String

        init() {
            suiteName = "AuphonicAppTests.\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suiteName)!
            manager = SettingsManager(defaults: defaults)
        }

        func tearDown() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    @Test func apiTokenPersistence() {
        let box = Sandbox()
        defer { box.tearDown() }

        #expect(!box.manager.hasApiToken)
        let token = "test-token-\(UUID().uuidString)"
        box.manager.apiToken = token
        #expect(box.manager.apiToken == token)
        #expect(box.manager.hasApiToken)
        #expect(box.defaults.string(forKey: "apiToken") == token)
    }

    @Test func hasApiTokenEmptyString() {
        let box = Sandbox()
        defer { box.tearDown() }

        box.manager.apiToken = "x"
        box.manager.apiToken = ""
        #expect(!box.manager.hasApiToken)
    }

    @Test func lastPresetUuidPersistence() {
        let box = Sandbox()
        defer { box.tearDown() }

        let uuid = "preset-\(UUID().uuidString)"
        box.manager.lastPresetUuid = uuid
        #expect(box.manager.lastPresetUuid == uuid)
    }

    @Test func perChannelModePersistence() {
        let box = Sandbox()
        defer { box.tearDown() }

        #expect(box.manager.perChannelMode == false)
        box.manager.perChannelMode = true
        #expect(box.manager.perChannelMode == true)
        box.manager.perChannelMode = false
        #expect(box.manager.perChannelMode == false)
    }

    @Test func audioOutputDevicePersistence() {
        let box = Sandbox()
        defer { box.tearDown() }

        let device = "device-\(UUID().uuidString)"
        box.manager.audioOutputDevice = device
        #expect(box.manager.audioOutputDevice == device)
    }

    @Test func lastManualSettingsPersistence() {
        let box = Sandbox()
        defer { box.tearDown() }

        let json = "{\"levelerEnabled\":true}"
        box.manager.lastManualSettings = json
        #expect(box.manager.lastManualSettings == json)
    }

    @Test func deleteProductionsPersistence() {
        let box = Sandbox()
        defer { box.tearDown() }

        #expect(box.manager.deleteProductionsAfterDownload == false)
        box.manager.deleteProductionsAfterDownload = true
        #expect(box.manager.deleteProductionsAfterDownload == true)
    }

    @Test func defaultValuesAreEmpty() {
        let box = Sandbox()
        defer { box.tearDown() }

        #expect(box.manager.apiToken == "")
        #expect(box.manager.audioOutputDevice == "")
        #expect(box.manager.lastPresetUuid == "")
        #expect(box.manager.lastManualSettings == "")
        #expect(box.manager.appMode == .standard)
    }

    @Test func appModePersistsAndMigratesOldValue() {
        let box = Sandbox()
        defer { box.tearDown() }

        box.manager.appMode = .mixPreparation
        #expect(box.manager.appMode == .mixPreparation)
        #expect(box.defaults.string(forKey: "appMode") == AppMode.mixPreparation.rawValue)

        // 1.x stored "api" for what is now Standard mode
        box.defaults.set("api", forKey: "appMode")
        #expect(box.manager.appMode == .standard)
    }
}
