import Foundation

actor BridgeProcessClient {
    private static let maximumFrameBytes = 1_048_576

    private let executableURL: URL
    private var process: Process?
    private var inputHandle: FileHandle?
    private var readTask: Task<Void, Never>?
    private var startupTimeoutTask: Task<Void, Never>?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var subscribers: [UUID: AsyncStream<BridgeEnvelope>.Continuation] = [:]
    private(set) var port: Int?

    init(executableURL: URL) {
        self.executableURL = executableURL
    }

    func eventStream() -> AsyncStream<BridgeEnvelope> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<BridgeEnvelope>.makeStream()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    func isReady() -> Bool {
        process?.isRunning == true && port != nil
    }

    func start(secret: Data) async throws {
        if process?.isRunning == true, port != nil {
            return
        }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw PlaybackLaunchError.helperUnavailable
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = executableURL
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            Task { await self?.processDidTerminate(status: process.terminationStatus) }
        }

        do {
            try process.run()
        } catch {
            throw PlaybackLaunchError.helperUnavailable
        }

        self.process = process
        self.inputHandle = inputPipe.fileHandleForWriting
        self.port = nil
        startReader(outputPipe.fileHandleForReading)

        try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            startupTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await self?.startupTimedOut()
            }
            do {
                try writeFrame(
                    BridgeConfigureFrame(secret: secret.base64URLEncodedString())
                )
            } catch {
                readyContinuation = nil
                continuation.resume(throwing: error)
            }
        }
    }

    func send(_ envelope: BridgeEnvelope) throws {
        guard process?.isRunning == true, port != nil else {
            throw PlaybackLaunchError.bridgeUnavailable
        }
        try writeFrame(BridgeCommandFrame(envelope: envelope))
    }

    func stop() {
        if process?.isRunning == true {
            try? writeFrame(BridgeShutdownFrame())
            process?.terminate()
        }
        resetProcess()
    }

    private func startReader(_ handle: FileHandle) {
        readTask?.cancel()
        readTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                while !Task.isCancelled,
                      let frame: BridgeOutputFrame = try Self.readFrame(from: handle) {
                    await self?.receive(frame)
                }
                await self?.readerDidEnd(error: nil)
            } catch {
                await self?.readerDidEnd(error: error)
            }
        }
    }

    private func receive(_ frame: BridgeOutputFrame) {
        switch frame.kind {
        case "ready":
            guard frame.protocolVersion == BridgeEnvelope.currentProtocolVersion,
                  let port = frame.port else {
                readyContinuation?.resume(throwing: PlaybackLaunchError.bridgeUnavailable)
                readyContinuation = nil
                return
            }
            self.port = port
            startupTimeoutTask?.cancel()
            startupTimeoutTask = nil
            readyContinuation?.resume()
            readyContinuation = nil
        case "event":
            guard let envelope = frame.envelope else { return }
            for continuation in subscribers.values {
                continuation.yield(envelope)
            }
        case "error":
            if readyContinuation != nil {
                readyContinuation?.resume(throwing: PlaybackLaunchError.bridgeUnavailable)
                readyContinuation = nil
            }
        default:
            break
        }
    }

    private func startupTimedOut() {
        readyContinuation?.resume(throwing: PlaybackLaunchError.helperUnavailable)
        readyContinuation = nil
        process?.terminate()
        resetProcess()
    }

    private func readerDidEnd(error: Error?) {
        if readyContinuation != nil {
            readyContinuation?.resume(throwing: PlaybackLaunchError.helperUnavailable)
            readyContinuation = nil
        }
        resetProcess()
    }

    private func processDidTerminate(status: Int32) {
        if readyContinuation != nil {
            readyContinuation?.resume(throwing: PlaybackLaunchError.helperUnavailable)
            readyContinuation = nil
        }
        resetProcess()
    }

    private func resetProcess() {
        readTask?.cancel()
        readTask = nil
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        try? inputHandle?.close()
        inputHandle = nil
        process = nil
        port = nil
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    private func writeFrame<Value: Encodable>(_ value: Value) throws {
        guard let inputHandle else {
            throw PlaybackLaunchError.bridgeUnavailable
        }
        let payload = try JSONEncoder().encode(value)
        guard !payload.isEmpty, payload.count <= Self.maximumFrameBytes else {
            throw PlaybackLaunchError.bridgeUnavailable
        }
        var length = UInt32(payload.count).bigEndian
        let prefix = withUnsafeBytes(of: &length) { Data($0) }
        do {
            try inputHandle.write(contentsOf: prefix)
            try inputHandle.write(contentsOf: payload)
        } catch {
            throw PlaybackLaunchError.bridgeUnavailable
        }
    }

    nonisolated private static func readFrame<Value: Decodable>(
        from handle: FileHandle
    ) throws -> Value? {
        guard let prefix = try readExactly(4, from: handle) else { return nil }
        let length = prefix.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= maximumFrameBytes else {
            throw PlaybackLaunchError.bridgeUnavailable
        }
        guard let payload = try readExactly(Int(length), from: handle) else {
            throw PlaybackLaunchError.bridgeUnavailable
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
            guard let chunk, !chunk.isEmpty else {
                return nil
            }
            result.append(chunk)
        }
        return result
    }
}
