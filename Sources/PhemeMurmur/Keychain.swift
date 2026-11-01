import Foundation
import PhemeMurmurCore
import Security

/// Stores provider API keys as generic passwords in the login keychain,
/// one item per provider name (the account) under the app's service name.
enum Keychain {
    private static let service = "com.purefuncinc.PhemeMurmur"

    /// The stored API key for `provider`, or nil if none is saved.
    static func apiKey(for provider: String) -> String? {
        var query = itemQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                ErrorLog.append(context: "keychain-read", message: "\(provider): \(message(for: status))")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Creates or replaces the API key for `provider`. Returns the Security framework status.
    @discardableResult
    static func saveAPIKey(_ apiKey: String, for provider: String) -> OSStatus {
        let query = itemQuery(for: provider)
        let value = [kSecValueData as String: Data(apiKey.utf8)]
        let status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        guard status == errSecItemNotFound else { return status }
        return SecItemAdd(query.merging(value) { $1 } as CFDictionary, nil)
    }

    static func message(for status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
    }

    private static func itemQuery(for provider: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
        ]
    }
}
