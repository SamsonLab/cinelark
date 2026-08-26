import ComposableArchitecture
import Foundation
import Testing

@testable import CineLark

@MainActor
struct RemoteFeatureTests {
    @Test("Restarting the app-scoped snapshot subscription cancels the previous stream")
    func replacesSnapshotSubscription() async {
        let subscriptions = LockIsolated(0)
        let terminations = LockIsolated(0)
        let snapshot = RemoteCoordinator.StateSnapshot(
            status: .starting,
            pairingDisplay: nil,
            pendingPairings: [],
            pairedDevices: [],
            connectedDeviceIDs: [],
            errorCode: nil
        )
        let store = TestStore(initialState: RemoteFeature.State()) {
            RemoteFeature()
        } withDependencies: {
            $0.remote = RemoteClient(
                snapshots: {
                    let index = subscriptions.withValue { value in
                        defer { value += 1 }
                        return value
                    }
                    return AsyncStream { continuation in
                        if index == 0 {
                            continuation.onTermination = { _ in
                                terminations.withValue { $0 += 1 }
                            }
                            continuation.yield(snapshot)
                        } else {
                            continuation.finish()
                        }
                    }
                },
                start: {},
                stop: {},
                beginPairing: {},
                endPairing: {},
                approve: { _ in },
                reject: { _ in },
                revoke: { _ in }
            )
        }

        await store.send(.view(.appAppeared))
        await store.receive(.internal(.snapshot(snapshot))) {
            $0.status = .starting
        }
        await store.send(.view(.appAppeared))
        await store.finish()

        #expect(subscriptions.value == 2)
        #expect(terminations.value == 1)
    }

    @Test("Remote snapshots are projected into feature state")
    func projectsSnapshot() async {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = RemoteCoordinator.StateSnapshot(
            status: .ready(port: 8421),
            pairingDisplay: RemoteCoordinator.PairingDisplay(
                payload: "pairing-payload",
                expiresAt: expiry
            ),
            pendingPairings: [],
            pairedDevices: [],
            connectedDeviceIDs: [],
            errorCode: nil
        )
        let store = TestStore(initialState: RemoteFeature.State()) {
            RemoteFeature()
        }

        await store.send(.internal(.snapshot(snapshot))) {
            $0.status = .ready(port: 8421)
            $0.pairingDisplay = RemoteCoordinator.PairingDisplay(
                payload: "pairing-payload",
                expiresAt: expiry
            )
        }
    }

    @Test("Pairing lifecycle is routed through the dependency client")
    func routesPairingLifecycle() async {
        let calls = LockIsolated<[String]>([])
        let store = TestStore(initialState: RemoteFeature.State()) {
            RemoteFeature()
        } withDependencies: {
            $0.remote = RemoteClient(
                snapshots: { AsyncStream { $0.finish() } },
                start: {},
                stop: {},
                beginPairing: { calls.withValue { $0.append("begin") } },
                endPairing: { calls.withValue { $0.append("end") } },
                approve: { _ in },
                reject: { _ in },
                revoke: { _ in }
            )
        }

        await store.send(.view(.settingsAppeared))
        await store.send(.view(.settingsDisappeared))
        await store.finish()

        #expect(calls.value == ["begin", "end"])
    }
}
