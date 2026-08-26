import ComposableArchitecture
import Foundation
import CineLarkDomain
import CineLarkPluginAPI

@Reducer
struct SearchFeature {
    @ObservableState
    struct State: Equatable {
        var sourceID: SourceID?
        var query = ""
        var resultIDs: [CatalogItemID] = []
        var results: [CatalogItemID: MediaSummary] = [:]
        var nextCursor: MediaCursor?
        var total: Int?
        var isSearching = false
        var isLoadingMore = false
        var failure: MediaSourceFailure?

        var orderedResults: [MediaSummary] {
            resultIDs.compactMap { results[$0] }
        }
    }

    enum Action: Equatable {
        case view(View)
        case `internal`(Internal)
        case delegate(Delegate)

        enum View: Equatable {
            case cacheWillClear
            case sourceChanged(SourceID?)
            case queryChanged(String)
            case submitted
            case loadMore
        }

        enum Internal: Equatable {
            case response(
                term: String,
                query: MediaQuery,
                appending: Bool,
                Result<MediaPage, MediaSourceFailure>
            )
        }

        enum Delegate: Equatable {
            case mediaSelected(MediaSummary)
        }
    }

    private enum CancelID { case search }
    @Dependency(\.mediaPlatform) private var mediaPlatform
    @Dependency(\.continuousClock) private var clock

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.cacheWillClear):
                clear(&state, keepingQuery: true)
                return .cancel(id: CancelID.search)

            case let .view(.sourceChanged(sourceID)):
                state.sourceID = sourceID
                clear(&state, keepingQuery: false)
                return .cancel(id: CancelID.search)

            case let .view(.queryChanged(query)):
                state.query = query
                let term = normalized(query)
                guard !term.isEmpty, let sourceID = state.sourceID else {
                    clear(&state, keepingQuery: true)
                    return .cancel(id: CancelID.search)
                }
                state.isSearching = true
                state.isLoadingMore = false
                state.failure = nil
                let mediaQuery = MediaQuery(
                    scope: SourceScope(sourceID: sourceID),
                    limit: 60
                )
                return request(term: term, query: mediaQuery, appending: false, debounce: true)

            case .view(.submitted):
                let term = normalized(state.query)
                guard !term.isEmpty, let sourceID = state.sourceID else { return .none }
                state.isSearching = true
                state.failure = nil
                return request(
                    term: term,
                    query: MediaQuery(scope: SourceScope(sourceID: sourceID), limit: 60),
                    appending: false,
                    debounce: false
                )

            case .view(.loadMore):
                guard
                    !state.isLoadingMore,
                    let sourceID = state.sourceID,
                    let cursor = state.nextCursor
                else { return .none }
                let term = normalized(state.query)
                guard !term.isEmpty else { return .none }
                state.isLoadingMore = true
                return request(
                    term: term,
                    query: MediaQuery(
                        scope: SourceScope(sourceID: sourceID),
                        cursor: cursor,
                        limit: 60
                    ),
                    appending: true,
                    debounce: false
                )

            case let .internal(.response(term, query, appending, .success(page))):
                guard normalized(state.query) == term, state.sourceID == query.scope.sourceIDs.first else {
                    return .none
                }
                state.isSearching = false
                state.isLoadingMore = false
                state.failure = nil
                let values = page.items.compactMap { item -> (CatalogItemID, MediaSummary)? in
                    guard let id = item.catalogID else { return nil }
                    return (id, item.summary.replacingUserState(.empty))
                }
                if !appending {
                    state.resultIDs = []
                    state.results = [:]
                }
                for (id, summary) in values where state.results[id] == nil {
                    state.resultIDs.append(id)
                    state.results[id] = summary
                }
                state.nextCursor = page.nextCursor
                state.total = page.total
                return .none

            case let .internal(.response(term, query, _, .failure(failure))):
                guard normalized(state.query) == term, state.sourceID == query.scope.sourceIDs.first else {
                    return .none
                }
                state.isSearching = false
                state.isLoadingMore = false
                state.failure = failure
                return .none

            case .delegate:
                return .none
            }
        }
    }

    private func request(
        term: String,
        query: MediaQuery,
        appending: Bool,
        debounce: Bool
    ) -> Effect<Action> {
        .run { send in
            do {
                if debounce { try await clock.sleep(for: .milliseconds(350)) }
                let page = try await mediaPlatform.search(term, query)
                await send(.internal(.response(
                    term: term,
                    query: query,
                    appending: appending,
                    .success(page)
                )))
            } catch is CancellationError {
                return
            } catch {
                await send(.internal(.response(
                    term: term,
                    query: query,
                    appending: appending,
                    .failure(Self.normalize(error))
                )))
            }
        }
        .cancellable(id: CancelID.search, cancelInFlight: !appending)
    }

    private func clear(_ state: inout State, keepingQuery: Bool) {
        if !keepingQuery { state.query = "" }
        state.resultIDs = []
        state.results = [:]
        state.nextCursor = nil
        state.total = nil
        state.isSearching = false
        state.isLoadingMore = false
        state.failure = nil
    }

    private func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalize(_ error: Error) -> MediaSourceFailure {
        if let failure = error as? MediaSourceFailure { return failure }
        return .transport(String(describing: error))
    }
}
