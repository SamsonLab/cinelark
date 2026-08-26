import ComposableArchitecture
import Foundation
import CineLarkRemote

@Reducer
struct RemoteFeature {
    @ObservableState
    struct State: Equatable {
        var status: RemoteCoordinator.Status = .stopped
        var pairingDisplay: RemoteCoordinator.PairingDisplay?
        var pendingPairings: [RemotePairingRequest] = []
        var pairedDevices: [RemoteDeviceRecord] = []
        var connectedDeviceIDs: Set<UUID> = []
        var errorCode: String?
    }

    enum Action: Equatable {
        case view(View)
        case `internal`(Internal)

        enum View: Equatable {
            case appAppeared
            case settingsAppeared
            case settingsDisappeared
            case retry
            case generateCode
            case approve(RemotePairingRequest)
            case reject(RemotePairingRequest)
            case revoke(RemoteDeviceRecord)
        }

        enum Internal: Equatable {
            case snapshot(RemoteCoordinator.StateSnapshot)
        }
    }

    private enum CancelID { case snapshots }
    @Dependency(\.remote) private var remote

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.appAppeared):
                return .merge(subscribe(), .run { _ in await remote.start() })

            case .view(.settingsAppeared):
                guard state.pairingDisplay == nil else { return .none }
                return .run { _ in await remote.beginPairing() }

            case .view(.settingsDisappeared):
                return .run { _ in await remote.endPairing() }

            case .view(.retry):
                return .run { _ in
                    await remote.start()
                    await remote.beginPairing()
                }

            case .view(.generateCode):
                return .run { _ in await remote.beginPairing() }

            case let .view(.approve(request)):
                return .run { _ in await remote.approve(request) }

            case let .view(.reject(request)):
                return .run { _ in await remote.reject(request) }

            case let .view(.revoke(device)):
                return .run { _ in await remote.revoke(device) }

            case let .internal(.snapshot(snapshot)):
                state.status = snapshot.status
                state.pairingDisplay = snapshot.pairingDisplay
                state.pendingPairings = snapshot.pendingPairings
                state.pairedDevices = snapshot.pairedDevices
                state.connectedDeviceIDs = snapshot.connectedDeviceIDs
                state.errorCode = snapshot.errorCode
                return .none
            }
        }
    }

    private func subscribe() -> Effect<Action> {
        .run { send in
            for await snapshot in await remote.snapshots() {
                await send(.internal(.snapshot(snapshot)))
            }
        }
        .cancellable(id: CancelID.snapshots, cancelInFlight: true)
    }
}
