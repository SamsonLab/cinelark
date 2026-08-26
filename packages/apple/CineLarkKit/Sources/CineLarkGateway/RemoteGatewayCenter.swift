import CineLarkRemote
import Foundation
import OSLog

public actor RemoteGatewayCenter: RemoteGatewayTransport {
    private static let logger = Logger(
        subsystem: "com.samsonlab.cinelark",
        category: "RemoteGatewayCenter"
    )

    private let process: GatewayProcessShell
    private var readTask: Task<Void, Never>?
    private var subscribers: [UUID: AsyncStream<RemoteGatewayEvent>.Continuation] = [:]
    private var ready: RemoteGatewayReady?
    private var isStarting = false
    private var startupFailed = false

    init(process: GatewayProcessShell) {
        self.process = process
    }

    public func eventStream() -> AsyncStream<RemoteGatewayEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<RemoteGatewayEvent>.makeStream()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    public func start(
        configuration: RemoteGatewayConfiguration
    ) async throws -> RemoteGatewayReady {
        guard ready == nil, !isStarting else { throw RemoteGatewayError.invalidFrame }
        isStarting = true
        startupFailed = false
        defer { isStarting = false }
        await startReaderIfNeeded()
        do {
            try await process.send(
                center: "remote",
                payload: RemoteConfigureFrame(configuration: configuration)
            )
        } catch {
            throw RemoteGatewayError.helperUnavailable
        }
        for _ in 0..<50 {
            if let ready { return ready }
            if startupFailed { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try? await process.sendIfRunning(
            center: "remote",
            payload: GatewayKindFrame(kind: "shutdown")
        )
        if startupFailed { throw RemoteGatewayError.helperUnavailable }
        throw RemoteGatewayError.startupTimedOut
    }

    public func startPairing(secret: Data, expiresAt: Date) async throws {
        guard secret.count == 32 else { throw RemoteGatewayError.invalidSecret }
        try await sendFrame(
            RemoteStartPairingFrame(
                secret: secret.remoteBase64URLEncodedString(),
                expiresAtUnixMilliseconds: Int64(expiresAt.timeIntervalSince1970 * 1_000)
            )
        )
    }

    public func stopPairing() async throws {
        try await sendFrame(GatewayKindFrame(kind: "stopPairing"))
    }

    public func approvePairing(
        connectionID: UUID,
        device: RemoteDeviceRecord
    ) async throws {
        try await sendFrame(
            RemoteApprovePairingFrame(
                connectionID: connectionID.uuidString.lowercased(),
                deviceID: device.id.uuidString.lowercased(),
                credential: device.credential,
                capabilities: device.capabilities
            )
        )
    }

    public func rejectPairing(connectionID: UUID, code: String) async throws {
        try await sendFrame(
            RemoteRejectPairingFrame(
                connectionID: connectionID.uuidString.lowercased(),
                code: code
            )
        )
    }

    public func send(
        connectionID: UUID,
        type: String,
        replyTo: String?,
        revision: UInt64?,
        payload: [String: RemoteJSONValue]
    ) async throws {
        try await sendFrame(
            RemoteSendFrame(
                connectionID: connectionID.uuidString.lowercased(),
                type: type,
                replyTo: replyTo,
                revision: revision,
                payload: payload
            )
        )
    }

    public func broadcast(
        type: String,
        revision: UInt64?,
        payload: [String: RemoteJSONValue]
    ) async throws {
        try await sendFrame(
            RemoteBroadcastFrame(type: type, revision: revision, payload: payload)
        )
    }

    public func revokeDevice(_ deviceID: UUID) async throws {
        try await sendFrame(
            RemoteRevokeDeviceFrame(deviceID: deviceID.uuidString.lowercased())
        )
    }

    public func stop() async {
        try? await process.sendIfRunning(
            center: "remote",
            payload: GatewayKindFrame(kind: "shutdown")
        )
        ready = nil
    }

    private func sendFrame<Value: Encodable & Sendable>(_ frame: Value) async throws {
        guard ready != nil else { throw RemoteGatewayError.helperUnavailable }
        do {
            try await process.sendIfRunning(center: "remote", payload: frame)
        } catch {
            throw RemoteGatewayError.helperUnavailable
        }
    }

    private func startReaderIfNeeded() async {
        guard readTask == nil else { return }
        let stream = await process.eventStream(center: "remote")
        readTask = Task { [weak self] in
            for await event in stream {
                await self?.receive(event)
            }
        }
    }

    private func receive(_ event: GatewayProcessEvent) {
        switch event {
        case .output(let data):
            guard let frame = try? JSONDecoder().decode(RemoteOutputFrame.self, from: data),
                  let event = frame.event else {
                Self.logger.error("Remote center returned an invalid frame")
                return
            }
            if case .ready(let ready) = event {
                self.ready = ready
            } else if case .error = event, ready == nil {
                startupFailed = true
            }
            publish(event)
        case .terminated:
            let wasReady = ready != nil
            ready = nil
            startupFailed = true
            if wasReady { publish(.error(code: "gatewayUnavailable")) }
        }
    }

    private func publish(_ event: RemoteGatewayEvent) {
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }
}

private struct RemoteDeviceConfigurationFrame: Encodable, Sendable {
    let deviceID: String
    let credential: String
    let capabilities: [String]
}

private struct RemoteConfigureFrame: Encodable, Sendable {
    let kind = "configure"
    let serviceID: String
    let name: String
    let portStart: UInt16
    let portEnd: UInt16
    let identity: RemoteGatewayIdentity?
    let devices: [RemoteDeviceConfigurationFrame]

    init(configuration: RemoteGatewayConfiguration) {
        serviceID = configuration.serviceID.uuidString.lowercased()
        name = configuration.name
        portStart = configuration.portRange.lowerBound
        portEnd = configuration.portRange.upperBound
        identity = configuration.identity
        devices = configuration.devices.map {
            RemoteDeviceConfigurationFrame(
                deviceID: $0.id.uuidString.lowercased(),
                credential: $0.credential,
                capabilities: $0.capabilities
            )
        }
    }
}

private struct RemoteStartPairingFrame: Encodable, Sendable {
    let kind = "startPairing"
    let secret: String
    let expiresAtUnixMilliseconds: Int64
}

private struct RemoteApprovePairingFrame: Encodable, Sendable {
    let kind = "approvePairing"
    let connectionID: String
    let deviceID: String
    let credential: String
    let capabilities: [String]
}

private struct RemoteRejectPairingFrame: Encodable, Sendable {
    let kind = "rejectPairing"
    let connectionID: String
    let code: String
}

private struct RemoteSendFrame: Encodable, Sendable {
    let kind = "send"
    let connectionID: String
    let type: String
    let replyTo: String?
    let revision: UInt64?
    let payload: [String: RemoteJSONValue]
}

private struct RemoteBroadcastFrame: Encodable, Sendable {
    let kind = "broadcast"
    let type: String
    let revision: UInt64?
    let payload: [String: RemoteJSONValue]
}

private struct RemoteRevokeDeviceFrame: Encodable, Sendable {
    let kind = "revokeDevice"
    let deviceID: String
}

private struct RemoteOutputFrame: Decodable {
    let kind: String
    let identity: RemoteGatewayIdentity?
    let fingerprint: String?
    let protocolVersion: Int?
    let port: UInt16?
    let connectionID: String?
    let deviceID: String?
    let deviceName: String?
    let envelope: RemoteEnvelope?
    let reason: String?
    let code: String?

    var event: RemoteGatewayEvent? {
        switch kind {
        case "identityGenerated":
            guard let identity, let fingerprint else { return nil }
            return .identityGenerated(identity, fingerprint: fingerprint)
        case "ready":
            guard protocolVersion == RemoteEnvelope.protocolVersion,
                  let port, let fingerprint else { return nil }
            return .ready(RemoteGatewayReady(port: port, fingerprint: fingerprint))
        case "pairingRequested":
            guard let connectionID = connectionID.flatMap(UUID.init(uuidString:)),
                  let deviceID = deviceID.flatMap(UUID.init(uuidString:)),
                  let deviceName else { return nil }
            return .pairingRequested(
                RemotePairingRequest(
                    connectionID: connectionID,
                    deviceID: deviceID,
                    deviceName: deviceName
                )
            )
        case "connected":
            guard let connectionID = connectionID.flatMap(UUID.init(uuidString:)),
                  let deviceID = deviceID.flatMap(UUID.init(uuidString:)) else { return nil }
            return .connected(connectionID: connectionID, deviceID: deviceID)
        case "envelope":
            guard let connectionID = connectionID.flatMap(UUID.init(uuidString:)),
                  let deviceID = deviceID.flatMap(UUID.init(uuidString:)),
                  let envelope else { return nil }
            return .envelope(connectionID: connectionID, deviceID: deviceID, envelope)
        case "disconnected":
            guard let connectionID = connectionID.flatMap(UUID.init(uuidString:)),
                  let reason else { return nil }
            return .disconnected(
                connectionID: connectionID,
                deviceID: deviceID.flatMap(UUID.init(uuidString:)),
                reason: reason
            )
        case "error":
            guard let code else { return nil }
            return .error(code: code)
        default:
            return nil
        }
    }
}
