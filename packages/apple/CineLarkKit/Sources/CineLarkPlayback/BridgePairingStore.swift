import Foundation
import Security

struct BridgePairingStore: Sendable {
    static let pluginIdentifier = "com.samsonlab.cinelark.iina"
    static let keychainService = "\(pluginIdentifier) - bridge"
    static let keychainAccount = "pairing-key"

    func loadOrCreateSecret() throws -> Data {
        if let existing = try loadSecret() {
            guard existing.count == 32 else {
                throw PlaybackLaunchError.bridgeAuthenticationFailed
            }
            return existing
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw PlaybackLaunchError.bridgeAuthenticationFailed
        }
        let secret = Data(bytes)
        let status = SecItemAdd(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.keychainService,
                kSecAttrAccount as String: Self.keychainAccount,
                kSecAttrLabel as String: "CineLark IINA Bridge Pairing Key",
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                kSecValueData as String: Data(secret.base64URLEncodedString().utf8)
            ] as CFDictionary,
            nil
        )
        if status == errSecDuplicateItem, let existing = try loadSecret() {
            return existing
        }
        guard status == errSecSuccess else {
            throw PlaybackLaunchError.bridgeAuthenticationFailed
        }
        return secret
    }

    func rotateSecret() throws -> Data {
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ] as CFDictionary
        let status = SecItemDelete(query)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PlaybackLaunchError.bridgeAuthenticationFailed
        }
        return try loadOrCreateSecret()
    }

    private func loadSecret() throws -> Data? {
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ] as CFDictionary
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let encoded = String(data: data, encoding: .utf8),
              let secret = Data(base64URLEncoded: encoded),
              secret.count == 32 else {
            throw PlaybackLaunchError.bridgeAuthenticationFailed
        }
        return secret
    }
}
