import Testing
import Foundation
@testable import AuphonicApp

/// Every test gets its own UserDefaults suite, removed again afterwards. The
/// test host is the sandboxed app itself, so writing to `.standard` here
/// would overwrite the user's real settings — an earlier version of these
/// tests wiped the API token that way.
/// Token store that never leaves the test process
final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private(set) var token: String?
    init(token: String? = nil) { self.token = token }
    func readToken() -> String? { token }
    func writeToken(_ token: String?) { self.token = token }
}

struct SettingsManagerTests {

    private struct Sandbox {
        let manager: SettingsManager
        let defaults: UserDefaults
        let tokenStore: InMemoryTokenStore
        let suiteName: String

        init(token: String? = nil) {
            suiteName = "AuphonicAppTests.\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suiteName)!
            tokenStore = InMemoryTokenStore(token: token)
            manager = SettingsManager(defaults: defaults, tokenStore: tokenStore)
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
        // Keychain, not preferences
        #expect(box.tokenStore.token == token)
        #expect(box.defaults.string(forKey: "apiToken") == nil)
    }

    @Test func clearingTheTokenRemovesItFromTheStore() {
        let box = Sandbox(token: "old")
        defer { box.tearDown() }

        #expect(box.manager.hasApiToken)
        box.manager.apiToken = ""
        #expect(box.tokenStore.token == nil)
        #expect(!box.manager.hasApiToken)
    }

    /// A 2.0 install keeps its token: the plaintext preference is moved
    /// into the Keychain the first time it is read
    @Test func legacyPlaintextTokenMigratesIntoTheStore() {
        let box = Sandbox()
        defer { box.tearDown() }
        box.defaults.set("legacy-token", forKey: "apiToken")

        #expect(box.manager.apiToken == "legacy-token")
        #expect(box.tokenStore.token == "legacy-token")
        #expect(box.defaults.string(forKey: "apiToken") == nil)
    }

    /// A Keychain token wins over a stale preference value
    @Test func storeTokenTakesPrecedenceOverPreference() {
        let box = Sandbox(token: "keychain-token")
        defer { box.tearDown() }
        box.defaults.set("stale", forKey: "apiToken")

        #expect(box.manager.apiToken == "keychain-token")
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


// MARK: - Keychain

/// Round trip through the real Keychain from inside the sandboxed test host,
/// under a service name that is unique to this run and removed afterwards.
struct KeychainTokenStoreTests {

    @Test func writeReadUpdateDelete() {
        let store = KeychainTokenStore(service: "com.kpgbr.AuphonicAppTests.\(UUID().uuidString)")
        defer { store.writeToken(nil) }

        #expect(store.readToken() == nil)

        store.writeToken("first")
        #expect(store.readToken() == "first")

        store.writeToken("second")
        #expect(store.readToken() == "second")

        store.writeToken(nil)
        #expect(store.readToken() == nil)
    }
}
