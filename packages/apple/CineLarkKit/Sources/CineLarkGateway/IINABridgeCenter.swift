import CineLarkPlayback
import Foundation
import OSLog

public actor IINABridgeCenter: IINABridgeTransport {
    private static let logger = Logger(
        subsystem: "com.samsonlab.cinelark",
        category: "IINABridgeCenter"
    )

    private let process: GatewayProcessShell
    private var readTask: Task<Void, Never>?
    private var subscribers: [UUID: AsyncStream<BridgeEnvelope>.Continuation] = [:]
    private var port: Int?
    private var isStarting = false
    private var startupFailed = false

    init(process: GatewayProcessShell) {
        self.process = process
    }

    public func eventStream() -> AsyncStream<BridgeEnvelope> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<BridgeEnvelope>.makeStream()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    public func isReady() -> Bool {
        port != nil
    }

    public func start(secret: Data) async throws {
        if port != nil { return }
        guard !isStarting else { throw PlaybackLaunchError.bridgeUnavailable }
        isStarting = true
        startupFailed = false
        defer { isStarting = false }
        await startReaderIfNeeded()
        do {
            try await process.send(
                center: "iina",
                payload: IINAConfigureFrame(secret: secret.gatewayBase64URLEncodedString())
            )
        } catch {
            throw PlaybackLaunchError.helperUnavailable
        }
        for _ in 0..<50 {
            if port != nil { return }
            if startupFailed { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try? await process.sendIfRunning(
            center: "iina",
            payload: GatewayKindFrame(kind: "shutdown")
        )
        throw PlaybackLaunchError.helperUnavailable
    }

    public func send(_ envelope: BridgeEnvelope) async throws {
        guard port != nil else { throw PlaybackLaunchError.bridgeUnavailable }
        do {
            try await process.sendIfRunning(
                center: "iina",
                payload: IINACommandFrame(envelope: envelope)
            )
        } catch {
            throw PlaybackLaunchError.bridgeUnavailable
        }
    }

    public func stop() async {
        try? await process.sendIfRunning(
            center: "iina",
            payload: GatewayKindFrame(kind: "shutdown")
        )
        port = nil
    }

    private func startReaderIfNeeded() async {
        guard readTask == nil else { return }
        let stream = await process.eventStream(center: "iina")
        readTask = Task { [weak self] in
            for await event in stream {
                await self?.receive(event)
            }
        }
    }

    private func receive(_ event: GatewayProcessEvent) {
        switch event {
        case .output(let data):
            guard let frame = try? JSONDecoder().decode(IINAOutputFrame.self, from: data) else {
                Self.logger.error("IINA center returned an invalid frame")
                return
            }
            switch frame.kind {
            case "ready":
                guard frame.protocolVersion == BridgeEnvelope.currentProtocolVersion,
                      let port = frame.port else { return }
                self.port = port
            case "event":
                guard let envelope = frame.envelope else { return }
                for continuation in subscribers.values {
                    continuation.yield(envelope)
                }
            case "error":
                if port == nil { startupFailed = true }
                Self.logger.error(
                    "IINA center rejected a command code=\(frame.code ?? "unknown", privacy: .public)"
                )
            default:
                break
            }
        case .terminated:
            port = nil
            startupFailed = true
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }
}

private struct IINAConfigureFrame: Encodable, Sendable {
    let kind = "configure"
    let secret: String
    let portStart = 43_191
    let portEnd = 43_200
}

private struct IINACommandFrame: Encodable, Sendable {
    let kind = "command"
    let envelope: BridgeEnvelope
}

private struct IINAOutputFrame: Decodable {
    let kind: String
    let protocolVersion: Int?
    let port: Int?
    let envelope: BridgeEnvelope?
    let code: String?
}

private extension Data {
    func gatewayBase64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
