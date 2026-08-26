import Foundation
import Security

public actor KeychainSecretStore {
    private let service: String

    public init(service: String) {
        self.service = service
    }

    public func load(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else {
            throw KeychainSecretError(status: status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ secret: String, account: String) throws {
        let data = Data(secret.utf8)
        let query = baseQuery(account: account)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update = SecItemUpdate(
                query as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard update == errSecSuccess else { throw KeychainSecretError(status: update) }
        } else if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            let add = SecItemAdd(item as CFDictionary, nil)
            guard add == errSecSuccess else { throw KeychainSecretError(status: add) }
        } else {
            throw KeychainSecretError(status: status)
        }
    }

    public func remove(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretError(status: status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private struct KeychainSecretError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain operation failed."
    }
}
