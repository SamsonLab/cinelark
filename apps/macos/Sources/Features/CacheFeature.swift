import ComposableArchitecture

@Reducer
struct CacheFeature {
    @ObservableState
    struct State: Equatable {
        var usage = CacheUsage.zero
        var isLoading = false
        var isClearing = false
        var showsClearConfirmation = false
        var failure: CacheClientFailure?
    }

    enum Action: Equatable {
        case view(View)
        case `internal`(Internal)
        case delegate(Delegate)

        enum View: Equatable {
            case appeared
            case refresh
            case clearButtonTapped
            case clearConfirmed
            case clearCancelled
        }

        enum Internal: Equatable {
            case usageLoaded(Result<CacheUsage, CacheClientFailure>)
            case clearFinished(ClearResult)
        }

        enum Delegate: Equatable {
            case willClear
            case didClear
        }
    }

    enum ClearResult: Equatable {
        case success
        case failure(CacheClientFailure)
    }

    private enum CancelID { case usage, clear }
    @Dependency(\.cache) private var cache

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.appeared), .view(.refresh):
                state.isLoading = true
                state.failure = nil
                return loadUsage()

            case .view(.clearButtonTapped):
                guard !state.isClearing else { return .none }
                state.showsClearConfirmation = true
                return .none

            case .view(.clearCancelled):
                state.showsClearConfirmation = false
                return .none

            case .view(.clearConfirmed):
                guard !state.isClearing else { return .none }
                state.showsClearConfirmation = false
                state.isClearing = true
                state.failure = nil
                return .concatenate(
                    .cancel(id: CancelID.usage),
                    .send(.delegate(.willClear)),
                    .run { send in
                        do {
                            try await cache.clearAll()
                            await send(.internal(.clearFinished(.success)))
                        } catch is CancellationError {
                            return
                        } catch {
                            await send(.internal(.clearFinished(.failure(Self.normalize(error)))))
                        }
                    }
                    .cancellable(id: CancelID.clear, cancelInFlight: true)
                )

            case let .internal(.usageLoaded(.success(usage))):
                state.isLoading = false
                state.usage = usage
                return .none

            case let .internal(.usageLoaded(.failure(failure))):
                state.isLoading = false
                state.failure = failure
                return .none

            case .internal(.clearFinished(.success)):
                state.isClearing = false
                state.usage = .zero
                return .concatenate(
                    .send(.delegate(.didClear)),
                    .send(.view(.refresh))
                )

            case let .internal(.clearFinished(.failure(failure))):
                state.isClearing = false
                state.failure = failure
                return .none

            case .delegate:
                return .none
            }
        }
    }

    private func loadUsage() -> Effect<Action> {
        .run { send in
            do {
                await send(.internal(.usageLoaded(.success(try await cache.usage()))))
            } catch is CancellationError {
                return
            } catch {
                await send(.internal(.usageLoaded(.failure(Self.normalize(error)))))
            }
        }
        .cancellable(id: CancelID.usage, cancelInFlight: true)
    }

    private static func normalize(_ error: Error) -> CacheClientFailure {
        if let failure = error as? CacheClientFailure { return failure }
        return .unavailable(String(describing: error))
    }
}
