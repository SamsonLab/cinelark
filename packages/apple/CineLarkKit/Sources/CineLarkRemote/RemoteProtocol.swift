import CryptoKit
import Foundation
import Security

public enum RemoteJSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([RemoteJSONValue])
    case object([String: RemoteJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([RemoteJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: RemoteJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    public var doubleValue: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .number(let value): value
        default: nil
        }
    }

    public var intValue: Int? {
        switch self {
        case .integer(let value): Int(exactly: value)
        case .number(let value) where value.rounded() == value: Int(exactly: value)
        default: nil
        }
    }

    public var arrayValue: [RemoteJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    public var objectValue: [String: RemoteJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}

public struct RemoteEnvelope: Codable, Sendable, Equatable {
    public static let protocolVersion = 1

    public let protocolVersion: Int
    public let id: String
    public let type: String
    public let sentAt: String
    public let replyTo: String?
    public let sequence: UInt64
    public let revision: UInt64?
    public let payload: [String: RemoteJSONValue]

    public init(
        id: UUID = UUID(),
        type: String,
        sequence: UInt64,
        revision: UInt64? = nil,
        payload: [String: RemoteJSONValue] = [:],
        sentAt: Date = Date()
    ) {
        self.protocolVersion = Self.protocolVersion
        self.id = id.uuidString.lowercased()
        self.type = type
        self.sentAt = sentAt.ISO8601Format()
        self.replyTo = nil
        self.sequence = sequence
        self.revision = revision
        self.payload = payload
    }
}

public struct RemoteGatewayIdentity: Codable, Sendable, Equatable {
    public let certificatePEM: String
    public let privateKeyPEM: String

    private enum CodingKeys: String, CodingKey {
        case certificatePEM = "certificatePem"
        case privateKeyPEM = "privateKeyPem"
    }

    public init(certificatePEM: String, privateKeyPEM: String) {
        self.certificatePEM = certificatePEM
        self.privateKeyPEM = privateKeyPEM
    }
}

public struct RemoteDeviceRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public let credential: String
    public var capabilities: [String]
    public let pairedAt: Date

    public init(
        id: UUID,
        name: String,
        credential: String,
        capabilities: [String],
        pairedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.credential = credential
        self.capabilities = capabilities
        self.pairedAt = pairedAt
    }
}

public struct RemoteGatewayConfiguration: Sendable, Equatable {
    public let serviceID: UUID
    public let name: String
    public let identity: RemoteGatewayIdentity?
    public let devices: [RemoteDeviceRecord]
    public let portRange: ClosedRange<UInt16>

    public init(
        serviceID: UUID,
        name: String,
        identity: RemoteGatewayIdentity?,
        devices: [RemoteDeviceRecord],
        portRange: ClosedRange<UInt16> = 43_201...43_210
    ) {
        self.serviceID = serviceID
        self.name = name
        self.identity = identity
        self.devices = devices
        self.portRange = portRange
    }
}

public struct RemoteGatewayReady: Sendable, Equatable {
    public let port: UInt16
    public let fingerprint: String

    public init(port: UInt16, fingerprint: String) {
        self.port = port
        self.fingerprint = fingerprint
    }
}

public struct RemotePairingRequest: Sendable, Equatable, Identifiable {
    public let connectionID: UUID
    public let deviceID: UUID
    public let deviceName: String

    public var id: UUID { connectionID }

    public init(connectionID: UUID, deviceID: UUID, deviceName: String) {
        self.connectionID = connectionID
        self.deviceID = deviceID
        self.deviceName = deviceName
    }
}

public enum RemoteGatewayEvent: Sendable, Equatable {
    case identityGenerated(RemoteGatewayIdentity, fingerprint: String)
    case ready(RemoteGatewayReady)
    case pairingRequested(RemotePairingRequest)
    case connected(connectionID: UUID, deviceID: UUID)
    case envelope(connectionID: UUID, deviceID: UUID, RemoteEnvelope)
    case disconnected(connectionID: UUID, deviceID: UUID?, reason: String)
    case error(code: String)
}

public enum RemoteGatewayError: Error, LocalizedError, Sendable {
    case helperUnavailable
    case invalidFrame
    case startupTimedOut
    case keychain(OSStatus)
    case invalidSecret

    public var errorDescription: String? {
        switch self {
        case .helperUnavailable: "The bundled CineLark Remote gateway is unavailable."
        case .invalidFrame: "The CineLark Remote gateway returned an invalid frame."
        case .startupTimedOut: "The CineLark Remote gateway did not start in time."
        case .keychain(let status):
            SecCopyErrorMessageString(status, nil) as String? ?? "Remote Keychain access failed."
        case .invalidSecret: "Remote credentials must contain 256 bits."
        }
    }
}

public enum RemoteAuthentication {
    public static func proof(
        credential: Data,
        serviceID: String,
        connectionID: String,
        nonce: String
    ) -> String {
        let input = Data("\(serviceID)\n\(connectionID)\n\(nonce)".utf8)
        let code = HMAC<SHA256>.authenticationCode(
            for: input,
            using: SymmetricKey(data: credential)
        )
        return Data(code).remoteBase64URLEncodedString()
    }
}

public enum RemoteSecret {
    public static func generate() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw RemoteGatewayError.invalidSecret
        }
        return Data(bytes)
    }
}

public extension Data {
    init?(remoteBase64URLEncoded value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: base64)
    }

    func remoteBase64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
