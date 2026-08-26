import Foundation

public protocol RemoteGatewayTransport: Actor {
    func eventStream() -> AsyncStream<RemoteGatewayEvent>
    func start(configuration: RemoteGatewayConfiguration) async throws -> RemoteGatewayReady
    func startPairing(secret: Data, expiresAt: Date) async throws
    func stopPairing() async throws
    func approvePairing(connectionID: UUID, device: RemoteDeviceRecord) async throws
    func rejectPairing(connectionID: UUID, code: String) async throws
    func send(
        connectionID: UUID,
        type: String,
        replyTo: String?,
        revision: UInt64?,
        payload: [String: RemoteJSONValue]
    ) async throws
    func broadcast(
        type: String,
        revision: UInt64?,
        payload: [String: RemoteJSONValue]
    ) async throws
    func revokeDevice(_ deviceID: UUID) async throws
    func stop() async
}

public extension RemoteGatewayTransport {
    func rejectPairing(connectionID: UUID) async throws {
        try await rejectPairing(connectionID: connectionID, code: "pairingRejected")
    }

    func send(
        connectionID: UUID,
        type: String,
        payload: [String: RemoteJSONValue]
    ) async throws {
        try await send(
            connectionID: connectionID,
            type: type,
            replyTo: nil,
            revision: nil,
            payload: payload
        )
    }

    func send(
        connectionID: UUID,
        type: String,
        replyTo: String,
        payload: [String: RemoteJSONValue]
    ) async throws {
        try await send(
            connectionID: connectionID,
            type: type,
            replyTo: replyTo,
            revision: nil,
            payload: payload
        )
    }

    func send(
        connectionID: UUID,
        type: String,
        revision: UInt64,
        payload: [String: RemoteJSONValue]
    ) async throws {
        try await send(
            connectionID: connectionID,
            type: type,
            replyTo: nil,
            revision: revision,
            payload: payload
        )
    }

    func broadcast(
        type: String,
        payload: [String: RemoteJSONValue]
    ) async throws {
        try await broadcast(type: type, revision: nil, payload: payload)
    }
}
