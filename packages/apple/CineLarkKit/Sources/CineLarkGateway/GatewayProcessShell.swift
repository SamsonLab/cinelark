import Foundation
import OSLog

enum GatewayProcessEvent: Sendable {
    case output(Data)
    case terminated
}

actor GatewayProcessShell {
    private static let maximumFrameBytes = 1_048_576
    private static let logger = Logger(
        subsystem: "com.samsonlab.cinelark",
        category: "NativeGatewayProcess"
    )

    private let executableURL: URL
    private var process: Process?
    private var generation: UUID?
    private var inputHandle: FileHandle?
    private var readTask: Task<Void, Never>?
    private var isStopping = false
    private var subscribers: [String: [UUID: AsyncStream<GatewayProcessEvent>.Continuation]] = [:]

    init(executableURL: URL) {
        self.executableURL = executableURL
    }

    func eventStream(center: String) -> AsyncStream<GatewayProcessEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<GatewayProcessEvent>.makeStream()
        subscribers[center, default: [:]][id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id, center: center) }
        }
        return stream
    }

    func send<Payload: Encodable & Sendable>(center: String, payload: Payload) throws {
        try startIfNeeded()
        try writeFrame(GatewayInputFrame(center: center, payload: payload))
    }

    func sendIfRunning<Payload: Encodable & Sendable>(center: String, payload: Payload) throws {
        guard process?.isRunning == true else { throw GatewayProcessError.unavailable }
        try writeFrame(GatewayInputFrame(center: center, payload: payload))
    }

    func shutdown() async {
        isStopping = true
        defer { isStopping = false }
        if let process, process.isRunning {
            try? writeFrame(
                GatewayInputFrame(
                    center: "process",
                    payload: GatewayKindFrame(kind: "shutdown")
                )
            )
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

    private func startIfNeeded() throws {
        if process?.isRunning == true { return }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw GatewayProcessError.unavailable
        }

        let process = Process()
        let generation = UUID()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = executableURL
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.standardError
        process.terminationHandler = { [weak self] process in
            Task {
                await self?.processDidTerminate(
                    generation: generation,
                    status: process.terminationStatus
                )
            }
        }
        do {
            try process.run()
        } catch {
            throw GatewayProcessError.unavailable
        }
        self.process = process
        self.generation = generation
        inputHandle = inputPipe.fileHandleForWriting
        startReader(outputPipe.fileHandleForReading, generation: generation)
        Self.logger.info("Started the native gateway process")
    }

    private func startReader(_ handle: FileHandle, generation: UUID) {
        readTask?.cancel()
        readTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                while !Task.isCancelled,
                      let frame = try Self.readFrameData(from: handle) {
                    await self?.receive(frame, generation: generation)
                }
                await self?.readerDidEnd(generation: generation, invalidFrame: false)
            } catch {
                await self?.readerDidEnd(generation: generation, invalidFrame: true)
            }
        }
    }

    private func receive(_ frame: Data, generation: UUID) {
        guard self.generation == generation else { return }
        guard let object = try? JSONSerialization.jsonObject(with: frame) as? [String: Any],
              let center = object["center"] as? String,
              let payload = object["payload"],
              JSONSerialization.isValidJSONObject(payload),
              let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            Self.logger.error("Native gateway returned an invalid routed frame")
            return
        }
        publish(.output(payloadData), center: center)
    }

    private func readerDidEnd(generation: UUID, invalidFrame: Bool) {
        guard self.generation == generation else { return }
        if invalidFrame {
            Self.logger.error("Native gateway output ended with an invalid frame")
        }
        let shouldNotify = !isStopping
        resetProcess()
        if shouldNotify { publishTermination() }
    }

    private func processDidTerminate(generation: UUID, status: Int32) {
        guard self.generation == generation else { return }
        Self.logger.notice("Native gateway terminated with status \(status)")
        let shouldNotify = !isStopping
        resetProcess()
        if shouldNotify { publishTermination() }
    }

    private func resetProcess() {
        readTask?.cancel()
        readTask = nil
        try? inputHandle?.close()
        inputHandle = nil
        process = nil
        generation = nil
    }

    private func publish(_ event: GatewayProcessEvent, center: String) {
        for continuation in subscribers[center]?.values ?? [:].values {
            continuation.yield(event)
        }
    }

    private func publishTermination() {
        for center in subscribers.keys {
            publish(.terminated, center: center)
        }
    }

    private func removeSubscriber(_ id: UUID, center: String) {
        subscribers[center]?.removeValue(forKey: id)
    }

    private func writeFrame<Value: Encodable>(_ value: Value) throws {
        guard process?.isRunning == true, let inputHandle else {
            throw GatewayProcessError.unavailable
        }
        let payload = try JSONEncoder().encode(value)
        guard !payload.isEmpty, payload.count <= Self.maximumFrameBytes else {
            throw GatewayProcessError.invalidFrame
        }
        var length = UInt32(payload.count).bigEndian
        let prefix = withUnsafeBytes(of: &length) { Data($0) }
        do {
            try inputHandle.write(contentsOf: prefix)
            try inputHandle.write(contentsOf: payload)
        } catch {
            throw GatewayProcessError.unavailable
        }
    }

    nonisolated private static func readFrameData(from handle: FileHandle) throws -> Data? {
        guard let prefix = try readExactly(4, from: handle) else { return nil }
        let length = prefix.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= maximumFrameBytes else {
            throw GatewayProcessError.invalidFrame
        }
        guard let payload = try readExactly(Int(length), from: handle) else {
            throw GatewayProcessError.invalidFrame
        }
        return payload
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

private struct GatewayInputFrame<Payload: Encodable & Sendable>: Encodable, Sendable {
    let center: String
    let payload: Payload
}

struct GatewayKindFrame: Encodable, Sendable {
    let kind: String
}

enum GatewayProcessError: Error {
    case unavailable
    case invalidFrame
}
