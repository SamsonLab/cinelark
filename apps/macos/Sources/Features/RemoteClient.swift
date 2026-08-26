import ComposableArchitecture
import Observation
import CineLarkRemote

struct RemoteClient: Sendable {
    var snapshots: @Sendable () async -> AsyncStream<RemoteCoordinator.StateSnapshot>
    var start: @Sendable () async -> Void
    var stop: @Sendable () async -> Void
    var beginPairing: @Sendable () async -> Void
    var endPairing: @Sendable () async -> Void
    var approve: @Sendable (RemotePairingRequest) async -> Void
    var reject: @Sendable (RemotePairingRequest) async -> Void
    var revoke: @Sendable (RemoteDeviceRecord) async -> Void
}

extension RemoteClient: DependencyKey {
    static let liveValue = Self(
        snapshots: { AsyncStream { $0.finish() } },
        start: {},
        stop: {},
        beginPairing: {},
        endPairing: {},
        approve: { _ in },
        reject: { _ in },
        revoke: { _ in }
    )

    static let testValue = liveValue
}

extension DependencyValues {
    var remote: RemoteClient {
        get { self[RemoteClient.self] }
        set { self[RemoteClient.self] = newValue }
    }
}

extension RemoteClient {
    @MainActor
    static func live(coordinator: RemoteCoordinator) -> Self {
        Self(
            snapshots: {
                AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
                    let task = Task { @MainActor in
                        let observations = Observations { coordinator.stateSnapshot }
                        for await snapshot in observations {
                            continuation.yield(snapshot)
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            start: { await coordinator.start() },
            stop: { await coordinator.stop() },
            beginPairing: { await coordinator.beginPairing() },
            endPairing: { await coordinator.endPairing() },
            approve: { await coordinator.approve($0) },
            reject: { await coordinator.reject($0) },
            revoke: { await coordinator.revoke($0) }
        )
    }
}
