import Foundation
import Security

struct KeychainStore {
    var service = "com.screentranslate.app.api-keys"

    func read(provider: AIProvider) throws -> String {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw TranslationError.credentialUnavailable
        }
        return value
    }

    func write(_ key: String, provider: AIProvider) throws {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.contains("\n"), !clean.contains("\r") else {
            throw TranslationError.credentialUnavailable
        }
        let query = baseQuery(provider)
        if clean.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw TranslationError.credentialUnavailable
            }
            return
        }
        let values: [String: Any] = [kSecValueData as String: Data(clean.utf8)]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(clean.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw TranslationError.credentialUnavailable
            }
        } else if status != errSecSuccess { throw TranslationError.credentialUnavailable }
    }

    private func baseQuery(_ provider: AIProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue]
    }
}
