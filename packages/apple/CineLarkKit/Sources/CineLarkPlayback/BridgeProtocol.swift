import CryptoKit
import Foundation

struct BridgeEnvelope: Codable, Sendable, Equatable {
    static let currentProtocolVersion = 1

    let protocolVersion: Int
    let id: String
    let type: String
    let sentAt: String
    let sessionID: String?
    let replyTo: String?
    let sequence: UInt64
    let payload: [String: JSONValue]
    var mac: String

    init(
        id: UUID = UUID(),
        type: String,
        sessionID: UUID? = nil,
        replyTo: UUID? = nil,
        sequence: UInt64,
        payload: [String: JSONValue],
        secret: Data,
        date: Date = Date()
    ) {
        self.protocolVersion = Self.currentProtocolVersion
        self.id = id.uuidString.lowercased()
        self.type = type
        self.sentAt = date.ISO8601Format()
        self.sessionID = sessionID?.uuidString.lowercased()
        self.replyTo = replyTo?.uuidString.lowercased()
        self.sequence = sequence
        self.payload = payload
        self.mac = ""
        self.mac = authenticationCode(secret: secret)
    }

    func isAuthenticated(with secret: Data) -> Bool {
        guard protocolVersion == Self.currentProtocolVersion,
              let supplied = Data(base64URLEncoded: mac) else {
            return false
        }
        let expected = HMAC<SHA256>.authenticationCode(
            for: signingInput,
            using: SymmetricKey(data: secret)
        )
        return Data(expected) == supplied
    }

    private var signingInput: Data {
        let value = [
            String(protocolVersion),
            id,
            type,
            sentAt,
            sessionID ?? "",
            replyTo ?? "",
            String(sequence),
            JSONValue.object(payload).canonicalJSON
        ].joined(separator: "\n")
        return Data(value.utf8)
    }

    private func authenticationCode(secret: Data) -> String {
        let code = HMAC<SHA256>.authenticationCode(
            for: signingInput,
            using: SymmetricKey(data: secret)
        )
        return Data(code).base64URLEncodedString()
    }
}

enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
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
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    var canonicalJSON: String {
        switch self {
        case .null:
            "null"
        case .bool(let value):
            value ? "true" : "false"
        case .integer(let value):
            String(value)
        case .number(let value):
            Self.numberString(value)
        case .string(let value):
            Self.encodedJSONString(value)
        case .array(let values):
            "[" + values.map(\.canonicalJSON).joined(separator: ",") + "]"
        case .object(let values):
            "{" + values.keys.sorted().map { key in
                Self.encodedJSONString(key) + ":" + values[key]!.canonicalJSON
            }.joined(separator: ",") + "}"
        }
    }

    var doubleValue: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .number(let value): value
        default: nil
        }
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    private static func encodedJSONString(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return String(data: try! encoder.encode(value), encoding: .utf8)!
    }

    private static func numberString(_ value: Double) -> String {
        guard value.isFinite else { return "null" }
        if value.rounded() == value,
           value >= Double(Int64.min),
           value <= Double(Int64.max) {
            return String(Int64(value))
        }
        let representation = String(value).replacingOccurrences(of: "E", with: "e")
        guard let exponentIndex = representation.firstIndex(of: "e") else {
            return representation
        }
        let mantissa = representation[..<exponentIndex]
        let exponent = Int(representation[representation.index(after: exponentIndex)...]) ?? 0
        return "\(mantissa)e\(exponent)"
    }
}

struct BridgeConfigureFrame: Encodable {
    let kind = "configure"
    let secret: String
    let portStart = 43_191
    let portEnd = 43_200
}

struct BridgeCommandFrame: Encodable {
    let kind = "command"
    let envelope: BridgeEnvelope
}

struct BridgeShutdownFrame: Encodable {
    let kind = "shutdown"
}

struct BridgeOutputFrame: Decodable {
    let kind: String
    let protocolVersion: Int?
    let port: Int?
    let envelope: BridgeEnvelope?
    let code: String?
    let message: String?
}

extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
