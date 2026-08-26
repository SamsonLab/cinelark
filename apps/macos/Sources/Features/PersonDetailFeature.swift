import ComposableArchitecture
import CineLarkDomain
import CineLarkPluginAPI

@Reducer
struct PersonDetailFeature {
    @ObservableState
    struct State: Equatable {
        let sourceID: SourceID
        let initialPerson: PersonCredit
        var detail: PersonDetail?
        var works: [MediaSummary] = []
        var isLoading = false
        var failure: MediaSourceFailure?
    }

    enum Action: Equatable {
        case view(View)
        case `internal`(Internal)

        enum View: Equatable { case appeared }
        enum Internal: Equatable {
            case response(Result<Response, MediaSourceFailure>)
        }
    }

    struct Response: Equatable {
        let detail: PersonDetail
        let works: [MediaSummary]
    }

    private enum CancelID { case load }
    @Dependency(\.mediaPlatform) private var mediaPlatform

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.appeared):
                guard !state.isLoading, state.detail == nil else { return .none }
                state.isLoading = true
                state.failure = nil
                let sourceID = state.sourceID
                let personID = state.initialPerson.id
                return .run { send in
                    do {
                        async let detail = mediaPlatform.person(sourceID, personID)
                        async let works = mediaPlatform.works(
                            personID,
                            MediaQuery(
                                scope: SourceScope(sourceID: sourceID),
                                kinds: [.movie, .series],
                                filters: [.provider(name: "cinelark.person", value: personID)],
                                limit: 120
                            )
                        )
                        let response = try await Response(
                            detail: detail,
                            works: works.items.map { $0.summary.replacingUserState(.empty) }
                        )
                        await send(.internal(.response(.success(response))))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.internal(.response(.failure(Self.normalize(error)))))
                    }
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .internal(.response(.success(response))):
                state.isLoading = false
                state.detail = response.detail
                state.works = response.works
                return .none

            case let .internal(.response(.failure(failure))):
                state.isLoading = false
                state.failure = failure
                return .none
            }
        }
    }

    private static func normalize(_ error: Error) -> MediaSourceFailure {
        if let failure = error as? MediaSourceFailure { return failure }
        return .transport(String(describing: error))
    }
}
