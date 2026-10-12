import Foundation
import LocalAuthentication
import Security

enum WallhavenCredentials {
    private static func query(service: String, keychain: SecKeychain?) -> [String: Any] {
        var request: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "api-key",
        ]
        if let keychain { request[kSecMatchSearchList as String] = [keychain] }
        return request
    }

    static func isStored(service: String = "MWall.Wallhaven", keychain: SecKeychain? = nil) -> Bool
    {
        var request = query(service: service, keychain: keychain)
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        request[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(request as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func load(service: String = "MWall.Wallhaven", keychain: SecKeychain? = nil) throws
        -> String
    {
        var request = query(service: service, keychain: keychain)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        try check(status)
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw WallhavenError.invalidAPIKey
        }
        return key
    }

    static func save(
        _ value: String, service: String = "MWall.Wallhaven", keychain: SecKeychain? = nil
    ) throws {
        let key = try WallhavenService.normalizedAPIKey(value)
        guard !key.isEmpty else { throw WallhavenError.invalidAPIKey }
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let query = query(service: service, keychain: keychain)
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(attributes) { _, new in new }
            item.removeValue(forKey: kSecMatchSearchList as String)
            if let keychain { item[kSecUseKeychain as String] = keychain }
            item[kSecAttrLabel as String] = "MWall Wallhaven API Key"
            try check(SecItemAdd(item as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    static func remove(service: String = "MWall.Wallhaven", keychain: SecKeychain? = nil) throws {
        let status = SecItemDelete(query(service: service, keychain: keychain) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private static func check(_ status: OSStatus) throws {
        guard status != errSecSuccess else { return }
        throw NSError(
            domain: "MWall.Keychain", code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: "无法访问 Wallhaven 钥匙串项目（\(status)）。"])
    }
}
