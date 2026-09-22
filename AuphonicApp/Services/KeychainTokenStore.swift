import Foundation
import Security

/// Where the Auphonic API token lives. The app uses the Keychain; tests use
/// an in-memory store so they never touch the user's real token.
protocol TokenStore: AnyObject, Sendable {
    func readToken() -> String?
    /// `nil` removes the token
    func writeToken(_ token: String?)
}

/// Generic-password Keychain item, private to this app's code signature.
/// Sandboxed apps may use the Keychain without any extra entitlement.
final class KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    init(service: String = "com.kpgbr.AuphonicApp.auphonic-api", account: String = "api-token") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func readToken() -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func writeToken(_ token: String?) {
        guard let token, !token.isEmpty, let data = token.data(using: .utf8) else {
            SecItemDelete(query as CFDictionary)
            return
        }

        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
