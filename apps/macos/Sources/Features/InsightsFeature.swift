import ComposableArchitecture
import Foundation
import CineLarkInsights
import CineLarkPluginAPI
import CineLarkProfile

@Reducer
struct InsightsFeature {
    enum Failure: Error, Equatable {
        case unavailable(String)

        var message: String {
            switch self {
            case let .unavailable(message): message
            }
        }
    }

    @ObservableState
    struct State: Equatable {
        var activeProfileID: ProfileID?
        var activeSourceID: SourceID?
        var selectedPeriod: ViewingInsightPeriod = .month
        var snapshot: ViewingInsightsSnapshot?
        var requestID: UUID?
        var isPresented = false
        var isLoading = false
        var failure: Failure?
    }

    enum Action: Equatable {
        case view(View)
        case `internal`(Internal)

        enum View: Equatable {
            case appeared
            case disappeared
            case contextChanged(profileID: ProfileID?, sourceID: SourceID?)
            case periodSelected(ViewingInsightPeriod)
            case reload
        }

        enum Internal: Equatable {
            case loaded(
                requestID: UUID,
                profileID: ProfileID,
                sourceID: SourceID?,
                period: ViewingInsightPeriod,
                Result<ViewingInsightsSnapshot, Failure>
            )
        }
    }

    private enum CancelID {
        case load
    }

    @Dependency(\.insights) private var insights
    @Dependency(\.date.now) private var now
    @Dependency(\.uuid) private var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.appeared):
                state.isPresented = true
                return load(&state)

            case .view(.disappeared):
                state.isPresented = false
                state.isLoading = false
                state.requestID = nil
                return .cancel(id: CancelID.load)

            case let .view(.contextChanged(profileID, sourceID)):
                guard
                    state.activeProfileID != profileID || state.activeSourceID != sourceID
                else { return .none }
                state.activeProfileID = profileID
                state.activeSourceID = sourceID
                state.snapshot = nil
                state.failure = nil
                guard state.isPresented else {
                    state.isLoading = false
                    state.requestID = nil
                    return .cancel(id: CancelID.load)
                }
                return load(&state)

            case let .view(.periodSelected(period)):
                guard state.selectedPeriod != period else { return .none }
                state.selectedPeriod = period
                return load(&state)

            case .view(.reload):
                return load(&state)

            case let .internal(.loaded(
                requestID,
                profileID,
                sourceID,
                period,
                .success(snapshot)
            )):
                guard
                    state.requestID == requestID,
                    state.activeProfileID == profileID,
                    state.activeSourceID == sourceID,
                    state.selectedPeriod == period
                else { return .none }
                state.requestID = nil
                state.isLoading = false
                state.failure = nil
                state.snapshot = snapshot
                return .none

            case let .internal(.loaded(
                requestID,
                profileID,
                sourceID,
                period,
                .failure(failure)
            )):
                guard
                    state.requestID == requestID,
                    state.activeProfileID == profileID,
                    state.activeSourceID == sourceID,
                    state.selectedPeriod == period
                else { return .none }
                state.requestID = nil
                state.isLoading = false
                state.failure = failure
                return .none
            }
        }
    }

    private func load(_ state: inout State) -> Effect<Action> {
        guard state.isPresented, let profileID = state.activeProfileID else {
            state.isLoading = false
            state.requestID = nil
            return .cancel(id: CancelID.load)
        }
        let requestID = uuid()
        let sourceID = state.activeSourceID
        let period = state.selectedPeriod
        let referenceDate = now
        state.requestID = requestID
        state.isLoading = true
        state.failure = nil
        return .run { send in
            do {
                await send(.internal(.loaded(
                    requestID: requestID,
                    profileID: profileID,
                    sourceID: sourceID,
                    period: period,
                    .success(try await insights.load(
                        profileID,
                        sourceID,
                        period,
                        referenceDate
                    ))
                )))
            } catch {
                await send(.internal(.loaded(
                    requestID: requestID,
                    profileID: profileID,
                    sourceID: sourceID,
                    period: period,
                    .failure(Self.normalize(error))
                )))
            }
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }

    private static func normalize(_ error: Error) -> Failure {
        if let failure = error as? Failure { return failure }
        return .unavailable(String(describing: error))
    }
}
