import Foundation

public protocol IINABridgeTransport: Actor {
    func eventStream() -> AsyncStream<BridgeEnvelope>
    func isReady() -> Bool
    func start(secret: Data) async throws
    func send(_ envelope: BridgeEnvelope) async throws
    func stop() async
}
