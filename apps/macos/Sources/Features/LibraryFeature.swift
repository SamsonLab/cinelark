import ComposableArchitecture
import Foundation
import CineLarkDomain
import CineLarkPluginAPI
import CineLarkProfile

@Reducer
struct LibraryFeature {
    enum Shelf: Equatable, Hashable, Sendable {
        case latest
        case collection(String)
    }

    struct ItemSnapshot: Equatable, Sendable, Identifiable {
        let id: CatalogItemID
        let locator: MediaLocatorID
        let summary: MediaSummary

        var title: String { summary.title }
        var kind: MediaKind { summary.kind }
        var posterURL: URL? { summary.posterURL }
    }

    struct FavoriteSnapshot: Equatable, Sendable, Identifiable {
        var id: ProfileMediaKey { key }
        let key: ProfileMediaKey
        let locator: MediaLocatorID
        let summary: MediaSummary
    }

    @ObservableState
    struct State: Equatable {
        var profileID: ProfileID?
        var sourceID: SourceID?
        var collections: [MediaCollection] = []
        var query: MediaQuery?
        var itemIDs: [CatalogItemID] = []
        var nextCursor: MediaCursor?
        var total: Int?
        var latestIDs: [CatalogItemID] = []
        var collectionItemIDs: [String: [CatalogItemID]] = [:]
        var resumeItems: [FavoriteSnapshot] = []
        var snapshots: [CatalogItemID: ItemSnapshot] = [:]
        var favorites: [FavoriteSnapshot] = []
        var localStates: [ProfileMediaKey: ProfileMediaState] = [:]
        var isLoadingOverview = false
        var isRefreshing = false
        var isLoadingMore = false
        var failure: MediaSourceFailure?

        var orderedItems: [ItemSnapshot] { itemIDs.compactMap { snapshots[$0] } }
        var latestItems: [ItemSnapshot] { latestIDs.compactMap { snapshots[$0] } }

        func items(in collection: MediaCollection) -> [ItemSnapshot] {
            collectionItemIDs[collection.id, default: []].compactMap { snapshots[$0] }
        }
    }

    enum Action: Equatable {
        case view(View)
        case `internal`(Internal)
        case delegate(Delegate)

        enum View: Equatable {
            case cacheWillClear
            case contextChanged(profileID: ProfileID?, sourceID: SourceID?)
            case loadOverview
            case loadCollection(MediaCollection, MediaSort)
            case load(MediaQuery)
            case loadMore
            case play(ItemSnapshot)
            case playResume(FavoriteSnapshot)
            case reload
        }

        enum Internal: Equatable {
            case collectionsLoaded(SourceID, Result<[MediaCollection], MediaSourceFailure>)
            case shelfCached(Shelf, MediaQuery, Result<MediaPage, MediaSourceFailure>)
            case shelfRefreshed(Shelf, MediaQuery, Result<MediaPage, MediaSourceFailure>)
            case profileStateLoaded(ProfileID, Result<ProfileStateSnapshot, ProfileClientFailure>)
            case cachedPageLoaded(MediaQuery, Result<MediaPage, MediaSourceFailure>)
            case refreshedPageLoaded(MediaQuery, Result<MediaPage, MediaSourceFailure>)
            case additionalPageLoaded(
                baseQuery: MediaQuery,
                requestQuery: MediaQuery,
                Result<MediaPage, MediaSourceFailure>
            )
        }

        enum Delegate: Equatable {
            case mediaSelected(ItemSnapshot)
            case play(
                locator: MediaLocatorID,
                title: String,
                kind: MediaKind,
                artworkURL: URL?,
                startPositionSeconds: Double
            )
        }
    }

    private enum CancelID { case overview, query, pagination }

    @Dependency(\.mediaPlatform) private var mediaPlatform
    @Dependency(\.profiles) private var profiles
    @Dependency(\.performance) private var performance

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.cacheWillClear):
                clearCachedPresentation(&state)
                return .merge(
                    .cancel(id: CancelID.overview),
                    .cancel(id: CancelID.query),
                    .cancel(id: CancelID.pagination)
                )

            case let .view(.contextChanged(profileID, sourceID)):
                guard state.profileID != profileID || state.sourceID != sourceID else {
                    return .none
                }
                state.profileID = profileID
                state.sourceID = sourceID
                reset(&state)
                return sourceID == nil
                    ? .merge(
                        .cancel(id: CancelID.overview),
                        .cancel(id: CancelID.query),
                        .cancel(id: CancelID.pagination)
                    )
                    : .send(.view(.loadOverview))

            case .view(.loadOverview):
                guard let sourceID = state.sourceID else { return .none }
                state.isLoadingOverview = true
                state.failure = nil
                return overview(sourceID: sourceID, profileID: state.profileID)

            case let .view(.loadCollection(collection, sort)):
                guard let sourceID = state.sourceID else { return .none }
                return .send(.view(.load(MediaQuery(
                    scope: SourceScope(sourceID: sourceID),
                    parent: MediaLocatorID(sourceID: sourceID, providerItemID: collection.id),
                    kinds: collection.mediaKind.map { Set([$0]) } ?? [],
                    sort: sort,
                    limit: 60
                ))))

            case let .view(.load(query)):
                state.query = query
                state.isRefreshing = true
                state.isLoadingMore = false
                state.failure = nil
                return .merge(.cancel(id: CancelID.pagination), load(query))

            case .view(.loadMore):
                guard
                    !state.isRefreshing,
                    !state.isLoadingMore,
                    let baseQuery = state.query,
                    let cursor = state.nextCursor
                else { return .none }
                let requestQuery = MediaQuery(
                    scope: baseQuery.scope,
                    parent: baseQuery.parent,
                    kinds: baseQuery.kinds,
                    filters: baseQuery.filters,
                    sort: baseQuery.sort,
                    cursor: cursor,
                    limit: baseQuery.limit
                )
                state.isLoadingMore = true
                return loadMore(baseQuery: baseQuery, requestQuery: requestQuery)

            case let .view(.playResume(item)):
                return .send(.delegate(.play(
                    locator: item.locator,
                    title: item.summary.title,
                    kind: item.summary.kind,
                    artworkURL: item.summary.backdropURL ?? item.summary.posterURL,
                    startPositionSeconds: item.summary.userState.played
                        ? 0
                        : item.summary.userState.positionSeconds
                )))

            case let .view(.play(item)):
                return .send(.delegate(.play(
                    locator: item.locator,
                    title: item.summary.title,
                    kind: item.summary.kind,
                    artworkURL: item.summary.backdropURL ?? item.summary.posterURL,
                    startPositionSeconds: item.summary.userState.played
                        ? 0
                        : item.summary.userState.positionSeconds
                )))

            case .view(.reload):
                return .merge(
                    state.sourceID == nil ? .none : .send(.view(.loadOverview)),
                    state.query.map { .send(.view(.load($0))) } ?? .none
                )

            case let .internal(.collectionsLoaded(sourceID, .success(collections))):
                guard state.sourceID == sourceID else { return .none }
                state.collections = collections
                state.collectionItemIDs = state.collectionItemIDs.filter { key, _ in
                    collections.contains { $0.id == key }
                }
                state.isLoadingOverview = false
                return .merge(
                    collections.prefix(8).map { collection in
                        shelf(
                            .collection(collection.id),
                            query: shelfQuery(collection, sourceID: sourceID)
                        )
                    }
                )

            case let .internal(.collectionsLoaded(sourceID, .failure(failure))):
                guard state.sourceID == sourceID else { return .none }
                state.isLoadingOverview = false
                state.failure = failure
                return .none

            case let .internal(.shelfCached(shelf, query, .success(page))):
                guard state.sourceID == query.scope.sourceIDs.first else { return .none }
                applyShelf(page, shelf: shelf, to: &state)
                return .none

            case .internal(.shelfCached(_, _, .failure)):
                return .none

            case let .internal(.shelfRefreshed(shelf, query, .success(page))):
                guard state.sourceID == query.scope.sourceIDs.first else { return .none }
                applyShelf(page, shelf: shelf, to: &state)
                return .none

            case let .internal(.shelfRefreshed(_, query, .failure(failure))):
                guard state.sourceID == query.scope.sourceIDs.first else { return .none }
                state.failure = failure
                return .none

            case let .internal(.profileStateLoaded(profileID, .success(result))):
                guard state.profileID == profileID, let sourceID = state.sourceID else { return .none }
                let sourceKeys = Set(result.snapshots.compactMap { key, snapshot in
                    snapshot.locator.sourceID == sourceID ? key : nil
                })
                let localStates = result.states.filter { sourceKeys.contains($0.key) }
                state.localStates = localStates
                state.snapshots = state.snapshots.mapValues { value in
                    ItemSnapshot(
                        id: value.id,
                        locator: value.locator,
                        summary: applyingLocalState(
                            to: value.summary,
                            locator: value.locator,
                            states: localStates
                        )
                    )
                }
                state.favorites = localStates.compactMap { key, value in
                    guard value.isFavorite, let snapshot = result.snapshots[key] else { return nil }
                    return localSnapshot(snapshot, state: value)
                }
                    .sorted { $0.summary.title.localizedStandardCompare($1.summary.title) == .orderedAscending }
                state.resumeItems = localStates.compactMap { key, value in
                    guard
                        !value.playback.played,
                        value.playback.positionSeconds > 0,
                        let snapshot = result.snapshots[key]
                    else { return nil }
                    return localSnapshot(snapshot, state: value)
                }
                .sorted {
                    ($0.summary.userState.lastPlayedAt ?? .distantPast)
                        > ($1.summary.userState.lastPlayedAt ?? .distantPast)
                }
                return .none

            case let .internal(.profileStateLoaded(profileID, .failure(failure))):
                guard state.profileID == profileID else { return .none }
                state.failure = .transport(String(describing: failure))
                return .none

            case let .internal(.cachedPageLoaded(query, .success(page))):
                guard state.query == query else { return .none }
                apply(page, to: &state)
                return .none

            case let .internal(.cachedPageLoaded(query, .failure)):
                guard state.query == query else { return .none }
                return .none

            case let .internal(.refreshedPageLoaded(query, .success(page))):
                guard state.query == query else { return .none }
                state.isRefreshing = false
                apply(page, to: &state)
                return .none

            case let .internal(.refreshedPageLoaded(query, .failure(failure))):
                guard state.query == query else { return .none }
                state.isRefreshing = false
                state.failure = failure
                return .none

            case let .internal(.additionalPageLoaded(baseQuery, requestQuery, .success(page))):
                guard
                    state.query == baseQuery,
                    state.nextCursor == requestQuery.cursor
                else { return .none }
                state.isLoadingMore = false
                state.failure = nil
                append(page, to: &state)
                return .none

            case let .internal(.additionalPageLoaded(baseQuery, requestQuery, .failure(failure))):
                guard
                    state.query == baseQuery,
                    state.nextCursor == requestQuery.cursor
                else { return .none }
                state.isLoadingMore = false
                state.failure = failure
                return .none

            case .delegate:
                return .none
            }
        }
    }

    private func overview(sourceID: SourceID, profileID: ProfileID?) -> Effect<Action> {
        let latestQuery = shelfQuery(.latest, sourceID: sourceID)
        var effects: [Effect<Action>] = [
            .run { send in
                do {
                    await send(.internal(.collectionsLoaded(
                        sourceID,
                        .success(try await mediaPlatform.collections(sourceID))
                    )))
                } catch {
                    await send(.internal(.collectionsLoaded(
                        sourceID,
                        .failure(Self.normalize(error))
                    )))
                }
            },
            shelf(.latest, query: latestQuery)
        ]
        if let profileID {
            effects.append(.run { send in
                do {
                    await send(.internal(.profileStateLoaded(
                        profileID,
                        .success(try await profiles.state(profileID))
                    )))
                } catch {
                    let failure = (error as? ProfileClientFailure)
                        ?? .unavailable(String(describing: error))
                    await send(.internal(.profileStateLoaded(profileID, .failure(failure))))
                }
            })
        }
        return .merge(effects).cancellable(id: CancelID.overview, cancelInFlight: true)
    }

    private func shelf(_ shelf: Shelf, query: MediaQuery) -> Effect<Action> {
        .run { send in
            do {
                await send(.internal(.shelfCached(
                    shelf,
                    query,
                    .success(try await mediaPlatform.cachedPage(query))
                )))
            } catch {
                await send(.internal(.shelfCached(
                    shelf,
                    query,
                    .failure(Self.normalize(error))
                )))
            }
            guard !Task.isCancelled else { return }
            do {
                let page: MediaPage
                switch shelf {
                case .latest:
                    page = try await mediaPlatform.latest(query)
                case .collection:
                    page = try await mediaPlatform.refreshPage(query)
                }
                await send(.internal(.shelfRefreshed(shelf, query, .success(page))))
            } catch {
                await send(.internal(.shelfRefreshed(
                    shelf,
                    query,
                    .failure(Self.normalize(error))
                )))
            }
        }
    }

    private func load(_ query: MediaQuery) -> Effect<Action> {
        .run { send in
            let cachedInterval = performance.start(.cachedLibraryPage)
            do {
                await send(.internal(.cachedPageLoaded(
                    query,
                    .success(try await mediaPlatform.cachedPage(query))
                )))
                performance.finish(cachedInterval, .success)
            } catch is CancellationError {
                performance.finish(cachedInterval, .cancelled)
                return
            } catch {
                performance.finish(cachedInterval, .failure)
                await send(.internal(.cachedPageLoaded(query, .failure(Self.normalize(error)))))
            }
            guard !Task.isCancelled else { return }
            let refreshedInterval = performance.start(.refreshedLibraryPage)
            do {
                await send(.internal(.refreshedPageLoaded(
                    query,
                    .success(try await mediaPlatform.refreshPage(query))
                )))
                performance.finish(refreshedInterval, .success)
            } catch is CancellationError {
                performance.finish(refreshedInterval, .cancelled)
                return
            } catch {
                performance.finish(refreshedInterval, .failure)
                await send(.internal(.refreshedPageLoaded(query, .failure(Self.normalize(error)))))
            }
        }
        .cancellable(id: CancelID.query, cancelInFlight: true)
    }

    private func loadMore(baseQuery: MediaQuery, requestQuery: MediaQuery) -> Effect<Action> {
        .run { send in
            do {
                await send(.internal(.additionalPageLoaded(
                    baseQuery: baseQuery,
                    requestQuery: requestQuery,
                    .success(try await mediaPlatform.refreshPage(requestQuery))
                )))
            } catch is CancellationError {
                return
            } catch {
                await send(.internal(.additionalPageLoaded(
                    baseQuery: baseQuery,
                    requestQuery: requestQuery,
                    .failure(Self.normalize(error))
                )))
            }
        }
        .cancellable(id: CancelID.pagination, cancelInFlight: false)
    }

    private func shelfQuery(_ shelf: Shelf, sourceID: SourceID) -> MediaQuery {
        precondition(shelf == .latest)
        return MediaQuery(
            scope: SourceScope(sourceID: sourceID),
            filters: [.provider(name: "cinelark.list", value: "latest")],
            limit: 30
        )
    }

    private func shelfQuery(_ collection: MediaCollection, sourceID: SourceID) -> MediaQuery {
        MediaQuery(
            scope: SourceScope(sourceID: sourceID),
            parent: MediaLocatorID(
                sourceID: sourceID,
                providerItemID: collection.id
            ),
            sort: MediaSort(field: .releaseDate, order: .descending),
            limit: 18
        )
    }

    private func reset(_ state: inout State) {
        state.collections = []
        state.query = nil
        state.itemIDs = []
        state.nextCursor = nil
        state.total = nil
        state.latestIDs = []
        state.collectionItemIDs = [:]
        state.resumeItems = []
        state.snapshots = [:]
        state.favorites = []
        state.localStates = [:]
        state.isLoadingOverview = false
        state.isRefreshing = false
        state.isLoadingMore = false
        state.failure = nil
    }

    private func clearCachedPresentation(_ state: inout State) {
        state.query = nil
        state.itemIDs = []
        state.nextCursor = nil
        state.total = nil
        state.latestIDs = []
        state.collectionItemIDs = [:]
        state.snapshots = [:]
        state.isLoadingOverview = false
        state.isRefreshing = false
        state.isLoadingMore = false
        state.failure = nil
    }

    private func apply(_ page: MediaPage, to state: inout State) {
        state.itemIDs = ingest(page.items, into: &state)
        state.nextCursor = page.nextCursor
        state.total = page.total
    }

    private func append(_ page: MediaPage, to state: inout State) {
        var seen = Set(state.itemIDs)
        for id in ingest(page.items, into: &state) where seen.insert(id).inserted {
            state.itemIDs.append(id)
        }
        state.nextCursor = page.nextCursor
        state.total = page.total ?? state.total
    }

    private func applyShelf(_ page: MediaPage, shelf: Shelf, to state: inout State) {
        let ids = ingest(page.items, into: &state)
        switch shelf {
        case .latest:
            state.latestIDs = ids
        case let .collection(collectionID):
            state.collectionItemIDs[collectionID] = ids
        }
    }

    private func ingest(_ items: [LocatedMediaItem], into state: inout State) -> [CatalogItemID] {
        items.compactMap { item in
            guard let id = item.catalogID else { return nil }
            state.snapshots[id] = ItemSnapshot(
                id: id,
                locator: item.locator,
                summary: applyingLocalState(
                    to: item.summary,
                    locator: item.locator,
                    states: state.localStates
                )
            )
            return id
        }
    }

    private func applyingLocalState(
        to summary: MediaSummary,
        locator: MediaLocatorID,
        states: [ProfileMediaKey: ProfileMediaState]
    ) -> MediaSummary {
        summary.replacingUserState(
            states[ProfileMediaKey(locator: locator)]?.userState ?? .empty
        )
    }

    private func localSnapshot(
        _ snapshot: ProfileMediaSnapshot,
        state: ProfileMediaState
    ) -> FavoriteSnapshot {
        FavoriteSnapshot(
            key: snapshot.key,
            locator: snapshot.locator,
            summary: MediaSummary(
                id: snapshot.locator.providerItemID,
                kind: snapshot.kind,
                title: snapshot.title,
                posterURL: snapshot.artworkURL,
                genres: (snapshot.metadata?.genres ?? []).compactMap {
                    let normalized = Genre.normalized(name: $0.name)
                    guard let normalized else { return nil }
                    return Genre(
                        id: $0.providerID.flatMap(Int.init) ?? normalized.id,
                        name: normalized.name,
                        slug: $0.slug ?? normalized.slug
                    )
                },
                userState: state.userState
            )
        )
    }

    private static func normalize(_ error: Error) -> MediaSourceFailure {
        if let failure = error as? MediaSourceFailure { return failure }
        return .transport(String(describing: error))
    }
}
