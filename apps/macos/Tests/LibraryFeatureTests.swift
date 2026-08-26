import ComposableArchitecture
import Foundation
import Testing
import CineLarkDomain
import CineLarkPluginAPI
import CineLarkProfile

@testable import CineLark

@MainActor
struct LibraryFeatureTests {
    @Test("Local Profile state replaces provider user data and owns Resume")
    func localProfileStateIsAuthoritative() async {
        let profileID = ProfileID(rawValue: UUID())
        let sourceID = SourceID(rawValue: UUID())
        let catalogID = CatalogItemID(rawValue: UUID())
        let locator = MediaLocatorID(sourceID: sourceID, providerItemID: "movie-1")
        let key = ProfileMediaKey(locator: locator)
        let localPlayback = UserPlaybackState(
            played: false,
            positionSeconds: 25,
            progress: 0.25,
            lastPlayedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let localState = ProfileMediaState(isFavorite: true, playback: localPlayback)
        let profileSnapshot = ProfileMediaSnapshot(
            key: key,
            locator: locator,
            title: "Local Title",
            kind: .movie,
            artworkURL: nil,
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
            deviceID: "device"
        )
        let query = MediaQuery(scope: SourceScope(sourceID: sourceID), limit: 60)
        var state = LibraryFeature.State()
        state.profileID = profileID
        state.sourceID = sourceID
        state.query = query
        state.isRefreshing = true
        let store = TestStore(initialState: state) {
            LibraryFeature()
        }
        store.exhaustivity = .off

        await store.send(.internal(.profileStateLoaded(
            profileID,
            .success(ProfileStateSnapshot(
                states: [key: localState],
                snapshots: [key: profileSnapshot]
            ))
        )))

        let remoteSummary = MediaSummary(
            id: locator.providerItemID,
            kind: .movie,
            title: "Remote Title",
            userState: UserPlaybackState(
                played: true,
                favorite: false,
                positionSeconds: 0,
                progress: 1
            )
        )
        await store.send(.internal(.refreshedPageLoaded(
            query,
            .success(MediaPage(
                items: [LocatedMediaItem(
                    catalogID: catalogID,
                    locator: locator,
                    summary: remoteSummary
                )],
                nextCursor: nil,
                total: 1
            ))
        )))

        #expect(store.state.orderedItems.first?.summary.userState == localState.userState)
        #expect(store.state.favorites.first?.locator == locator)
        #expect(store.state.resumeItems.first?.summary.userState == localState.userState)
    }

    @Test("Cached-first loading cannot overwrite a newer refresh")
    func cachedFirstOrdering() async {
        let sourceID = SourceID(rawValue: UUID())
        let query = MediaQuery(scope: SourceScope(sourceID: sourceID))
        let cachedID = CatalogItemID(rawValue: UUID())
        let refreshedID = CatalogItemID(rawValue: UUID())
        let cachedPage = Self.page(id: cachedID, sourceID: sourceID, title: "Cached")
        let refreshedPage = Self.page(id: refreshedID, sourceID: sourceID, title: "Fresh")
        let store = TestStore(initialState: LibraryFeature.State()) {
            LibraryFeature()
        } withDependencies: {
            $0.mediaPlatform = MediaPlatformClient(
                descriptors: { [] },
                cachedPage: { _ in
                    cachedPage
                },
                refreshPage: { _ in
                    refreshedPage
                }
            )
        }

        await store.send(.view(.load(query))) {
            $0.query = query
            $0.isRefreshing = true
        }
        await store.receive(.internal(.cachedPageLoaded(query, .success(cachedPage)))) {
            $0.itemIDs = [cachedID]
            $0.total = 1
            $0.snapshots = [
                cachedID: LibraryFeature.ItemSnapshot(
                    id: cachedID,
                    locator: MediaLocatorID(
                        sourceID: sourceID,
                        providerItemID: "Cached"
                    ),
                    summary: MediaSummary(id: "Cached", kind: .movie, title: "Cached")
                )
            ]
        }
        await store.receive(.internal(.refreshedPageLoaded(query, .success(refreshedPage)))) {
            $0.isRefreshing = false
            $0.itemIDs = [refreshedID]
            $0.snapshots = [
                cachedID: LibraryFeature.ItemSnapshot(
                    id: cachedID,
                    locator: MediaLocatorID(
                        sourceID: sourceID,
                        providerItemID: "Cached"
                    ),
                    summary: MediaSummary(id: "Cached", kind: .movie, title: "Cached")
                ),
                refreshedID: LibraryFeature.ItemSnapshot(
                    id: refreshedID,
                    locator: MediaLocatorID(
                        sourceID: sourceID,
                        providerItemID: "Fresh"
                    ),
                    summary: MediaSummary(id: "Fresh", kind: .movie, title: "Fresh")
                )
            ]
        }
    }

    @Test("Pagination appends unique catalog items and advances the opaque cursor")
    func pagination() async {
        let sourceID = SourceID(rawValue: UUID())
        let firstID = CatalogItemID(rawValue: UUID())
        let secondID = CatalogItemID(rawValue: UUID())
        let cursor = MediaCursor(rawValue: "next-page")
        let query = MediaQuery(scope: SourceScope(sourceID: sourceID), limit: 2)
        let firstPage = MediaPage(
            items: Self.page(id: firstID, sourceID: sourceID, title: "First").items,
            nextCursor: cursor,
            total: 2
        )
        let secondPage = MediaPage(
            items: Self.page(id: secondID, sourceID: sourceID, title: "Second").items,
            nextCursor: nil,
            total: 2
        )
        let store = TestStore(initialState: LibraryFeature.State()) {
            LibraryFeature()
        } withDependencies: {
            $0.mediaPlatform = MediaPlatformClient(
                descriptors: { [] },
                cachedPage: { _ in MediaPage(items: [], nextCursor: nil, total: nil) },
                refreshPage: { request in
                    request.cursor == nil ? firstPage : secondPage
                }
            )
        }

        await store.send(.view(.load(query))) {
            $0.query = query
            $0.isRefreshing = true
        }
        await store.receive(.internal(.cachedPageLoaded(
            query,
            .success(MediaPage(items: [], nextCursor: nil, total: nil))
        )))
        await store.receive(.internal(.refreshedPageLoaded(query, .success(firstPage)))) {
            $0.isRefreshing = false
            $0.itemIDs = [firstID]
            $0.nextCursor = cursor
            $0.total = 2
            $0.snapshots[firstID] = LibraryFeature.ItemSnapshot(
                id: firstID,
                locator: MediaLocatorID(sourceID: sourceID, providerItemID: "First"),
                summary: MediaSummary(id: "First", kind: .movie, title: "First")
            )
        }

        let requestQuery = MediaQuery(
            scope: query.scope,
            cursor: cursor,
            limit: query.limit
        )
        await store.send(.view(.loadMore)) {
            $0.isLoadingMore = true
        }
        await store.receive(.internal(.additionalPageLoaded(
            baseQuery: query,
            requestQuery: requestQuery,
            .success(secondPage)
        ))) {
            $0.isLoadingMore = false
            $0.itemIDs = [firstID, secondID]
            $0.nextCursor = nil
            $0.snapshots[secondID] = LibraryFeature.ItemSnapshot(
                id: secondID,
                locator: MediaLocatorID(sourceID: sourceID, providerItemID: "Second"),
                summary: MediaSummary(id: "Second", kind: .movie, title: "Second")
            )
        }
    }

    nonisolated private static func page(
        id: CatalogItemID,
        sourceID: SourceID,
        title: String
    ) -> MediaPage {
        MediaPage(
            items: [
                LocatedMediaItem(
                    catalogID: id,
                    locator: MediaLocatorID(sourceID: sourceID, providerItemID: title),
                    summary: MediaSummary(id: title, kind: .movie, title: title)
                )
            ],
            nextCursor: nil,
            total: 1
        )
    }
}
