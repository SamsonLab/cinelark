import Foundation
import Security

public struct RemoteGatewayStoredState: Codable, Sendable, Equatable {
    public var serviceID: UUID
    public var identity: RemoteGatewayIdentity?
    public var devices: [RemoteDeviceRecord]

    public init(
        serviceID: UUID = UUID(),
        identity: RemoteGatewayIdentity? = nil,
        devices: [RemoteDeviceRecord] = []
    ) {
        self.serviceID = serviceID
        self.identity = identity
        self.devices = devices
    }
}

public actor RemoteCredentialStore {
    private let service: String
    private let account: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        service: String = "com.samsonlab.cinelark.remote",
        account: String = "gateway-state"
    ) {
        self.service = service
        self.account = account
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadOrCreate() throws -> RemoteGatewayStoredState {
        if let state = try load() { return state }
        let state = RemoteGatewayStoredState()
        try save(state)
        return state
    }

    public func load() throws -> RemoteGatewayStoredState? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw RemoteGatewayError.keychain(status)
        }
        return try decoder.decode(RemoteGatewayStoredState.self, from: data)
    }

    public func save(_ state: RemoteGatewayStoredState) throws {
        let data = try encoder.encode(state)
        let status = SecItemCopyMatching(baseQuery as CFDictionary, nil)
        if status == errSecSuccess {
            let updateStatus = SecItemUpdate(
                baseQuery as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw RemoteGatewayError.keychain(updateStatus)
            }
        } else if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecAttrLabel as String] = "CineLark Remote Gateway State"
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw RemoteGatewayError.keychain(addStatus)
            }
        } else {
            throw RemoteGatewayError.keychain(status)
        }
    }

    public func saveIdentity(_ identity: RemoteGatewayIdentity) throws {
        var state = try loadOrCreate()
        state.identity = identity
        try save(state)
    }

    public func upsertDevice(_ device: RemoteDeviceRecord) throws {
        var state = try loadOrCreate()
        state.devices.removeAll { $0.id == device.id }
        state.devices.append(device)
        try save(state)
    }

    public func removeDevice(_ deviceID: UUID) throws {
        var state = try loadOrCreate()
        state.devices.removeAll { $0.id == deviceID }
        try save(state)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
