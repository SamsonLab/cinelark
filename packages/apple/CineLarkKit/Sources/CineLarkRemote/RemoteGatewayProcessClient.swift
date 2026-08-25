import Foundation
import OSLog

public actor RemoteGatewayProcessClient {
    private static let maximumFrameBytes = 1_048_576
    private static let logger = Logger(
        subsystem: "com.samsonlab.cinelark",
        category: "RemoteGatewayProcess"
    )

    private let executableURL: URL
    private var process: Process?
    private var processGeneration: UUID?
    private var inputHandle: FileHandle?
    private var readTask: Task<Void, Never>?
    private var startupTimeoutTask: Task<Void, Never>?
    private var readyContinuation: CheckedContinuation<RemoteGatewayReady, Error>?
    private var subscribers: [UUID: AsyncStream<RemoteGatewayEvent>.Continuation] = [:]
    private var didBecomeReady = false
    private var isStopping = false

    public init(executableURL: URL) {
        self.executableURL = executableURL
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

    public func start(configuration: RemoteGatewayConfiguration) async throws -> RemoteGatewayReady {
        if process?.isRunning == true {
            throw RemoteGatewayError.invalidFrame
        }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw RemoteGatewayError.helperUnavailable
        }
        didBecomeReady = false
        isStopping = false

        let process = Process()
        let generation = UUID()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = executableURL
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        // The helper writes sanitized transport diagnostics to stderr. Keep it
        // attached so command-line launches can observe the complete pairing path.
        process.standardError = FileHandle.standardError
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task {
                await self?.processDidTerminate(
                    generation: generation,
                    status: status
                )
            }
        }

        do {
            try process.run()
        } catch {
            throw RemoteGatewayError.helperUnavailable
        }
        self.process = process
        processGeneration = generation
        inputHandle = inputPipe.fileHandleForWriting
        startReader(outputPipe.fileHandleForReading, generation: generation)

        return try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            startupTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await self?.startupTimedOut(generation: generation)
            }
            do {
                try writeFrame(RemoteConfigureFrame(configuration: configuration))
            } catch {
                startupTimeoutTask?.cancel()
                startupTimeoutTask = nil
                readyContinuation = nil
                continuation.resume(throwing: error)
                process.terminate()
                resetProcess()
            }
        }
    }

    public func startPairing(secret: Data, expiresAt: Date) throws {
        guard secret.count == 32 else { throw RemoteGatewayError.invalidSecret }
        try writeFrame(
            RemoteStartPairingFrame(
                secret: secret.remoteBase64URLEncodedString(),
                expiresAtUnixMilliseconds: Int64(expiresAt.timeIntervalSince1970 * 1_000)
            )
        )
    }

    public func stopPairing() throws {
        try writeFrame(RemoteKindFrame(kind: "stopPairing"))
    }

    public func approvePairing(
        connectionID: UUID,
        device: RemoteDeviceRecord
    ) throws {
        try writeFrame(
            RemoteApprovePairingFrame(
                connectionID: connectionID.uuidString.lowercased(),
                deviceID: device.id.uuidString.lowercased(),
                credential: device.credential,
                capabilities: device.capabilities
            )
        )
    }

    public func rejectPairing(connectionID: UUID, code: String = "pairingRejected") throws {
        try writeFrame(
            RemoteRejectPairingFrame(
                connectionID: connectionID.uuidString.lowercased(),
                code: code
            )
        )
    }

    public func send(
        connectionID: UUID,
        type: String,
        replyTo: String? = nil,
        revision: UInt64? = nil,
        payload: [String: RemoteJSONValue] = [:]
    ) throws {
        try writeFrame(
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
        revision: UInt64? = nil,
        payload: [String: RemoteJSONValue] = [:]
    ) throws {
        try writeFrame(
            RemoteBroadcastFrame(type: type, revision: revision, payload: payload)
        )
    }

    public func revokeDevice(_ deviceID: UUID) throws {
        try writeFrame(
            RemoteRevokeDeviceFrame(deviceID: deviceID.uuidString.lowercased())
        )
    }

    public func stop() async {
        isStopping = true
        defer { isStopping = false }
        if let process, process.isRunning {
            try? writeFrame(RemoteKindFrame(kind: "shutdown"))
            for _ in 0..<50 {
                guard process.isRunning else { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            if process.isRunning {
                process.terminate()
            }
        }
        resetProcess()
    }

    private func startReader(_ handle: FileHandle, generation: UUID) {
        readTask?.cancel()
        readTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                while !Task.isCancelled,
                      let frame: RemoteOutputFrame = try Self.readFrame(from: handle) {
                    await self?.receive(frame, generation: generation)
                }
                await self?.readerDidEnd(generation: generation, error: nil)
            } catch {
                await self?.readerDidEnd(generation: generation, error: error)
            }
        }
    }

    private func receive(_ frame: RemoteOutputFrame, generation: UUID) {
        guard processGeneration == generation else { return }
        guard let event = frame.event else {
            Self.logger.error("Remote gateway returned an invalid output frame")
            return
        }
        if case .ready(let ready) = event {
            startupTimeoutTask?.cancel()
            startupTimeoutTask = nil
            didBecomeReady = true
            readyContinuation?.resume(returning: ready)
            readyContinuation = nil
        }
        publish(event)
    }

    private func startupTimedOut(generation: UUID) {
        guard processGeneration == generation else { return }
        readyContinuation?.resume(throwing: RemoteGatewayError.startupTimedOut)
        readyContinuation = nil
        process?.terminate()
        resetProcess()
    }

    private func readerDidEnd(generation: UUID, error: Error?) {
        guard processGeneration == generation else { return }
        let shouldNotify = didBecomeReady && !isStopping
        if error != nil {
            Self.logger.error("Remote gateway output ended with an invalid frame")
        }
        if readyContinuation != nil {
            readyContinuation?.resume(throwing: RemoteGatewayError.helperUnavailable)
            readyContinuation = nil
        }
        resetProcess()
        if shouldNotify {
            publish(.error(code: "gatewayUnavailable"))
        }
    }

    private func processDidTerminate(generation: UUID, status: Int32) {
        guard processGeneration == generation else { return }
        let shouldNotify = didBecomeReady && !isStopping
        Self.logger.notice("Remote gateway terminated with status \(status)")
        if readyContinuation != nil {
            readyContinuation?.resume(throwing: RemoteGatewayError.helperUnavailable)
            readyContinuation = nil
        }
        resetProcess()
        if shouldNotify {
            publish(.error(code: "gatewayUnavailable"))
        }
    }

    private func resetProcess() {
        readTask?.cancel()
        readTask = nil
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        try? inputHandle?.close()
        inputHandle = nil
        process = nil
        processGeneration = nil
        didBecomeReady = false
    }

    private func publish(_ event: RemoteGatewayEvent) {
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    private func writeFrame<Value: Encodable>(_ value: Value) throws {
        guard process?.isRunning == true, let inputHandle else {
            throw RemoteGatewayError.helperUnavailable
        }
        let payload = try JSONEncoder().encode(value)
        guard !payload.isEmpty, payload.count <= Self.maximumFrameBytes else {
            throw RemoteGatewayError.invalidFrame
        }
        var length = UInt32(payload.count).bigEndian
        let prefix = withUnsafeBytes(of: &length) { Data($0) }
        do {
            try inputHandle.write(contentsOf: prefix)
            try inputHandle.write(contentsOf: payload)
        } catch {
            throw RemoteGatewayError.helperUnavailable
        }
    }

    nonisolated private static func readFrame<Value: Decodable>(
        from handle: FileHandle
    ) throws -> Value? {
        guard let prefix = try readExactly(4, from: handle) else { return nil }
        let length = prefix.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= maximumFrameBytes else {
            throw RemoteGatewayError.invalidFrame
        }
        guard let payload = try readExactly(Int(length), from: handle) else {
            throw RemoteGatewayError.invalidFrame
        }
        return try JSONDecoder().decode(Value.self, from: payload)
    }

    nonisolated private static func readExactly(
        _ count: Int,
        from handle: FileHandle
    ) throws -> Data? {
        var result = Data()
        while result.count < count {
            let chunk = try handle.read(upToCount: count - result.count)
            guard let chunk, !chunk.isEmpty else { return nil }
            result.append(chunk)
        }
        return result
    }
}

private struct RemoteDeviceConfigurationFrame: Encodable {
    let deviceID: String
    let credential: String
    let capabilities: [String]
}

private struct RemoteConfigureFrame: Encodable {
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

private struct RemoteKindFrame: Encodable { let kind: String }

private struct RemoteStartPairingFrame: Encodable {
    let kind = "startPairing"
    let secret: String
    let expiresAtUnixMilliseconds: Int64
}

private struct RemoteApprovePairingFrame: Encodable {
    let kind = "approvePairing"
    let connectionID: String
    let deviceID: String
    let credential: String
    let capabilities: [String]
}

private struct RemoteRejectPairingFrame: Encodable {
    let kind = "rejectPairing"
    let connectionID: String
    let code: String
}

private struct RemoteSendFrame: Encodable {
    let kind = "send"
    let connectionID: String
    let type: String
    let replyTo: String?
    let revision: UInt64?
    let payload: [String: RemoteJSONValue]
}

private struct RemoteBroadcastFrame: Encodable {
    let kind = "broadcast"
    let type: String
    let revision: UInt64?
    let payload: [String: RemoteJSONValue]
}

private struct RemoteRevokeDeviceFrame: Encodable {
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
