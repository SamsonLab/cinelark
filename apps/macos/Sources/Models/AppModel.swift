import AppKit
import Foundation
import Observation
import OSLog
import CineLarkDomain
import CineLarkPlayback

@Observable
@MainActor
final class AppModel {
    private static let logger = Logger(
        subsystem: "com.samsonlab.cinelark",
        category: "AppPlaybackSync"
    )

    enum ErrorRecovery: Equatable {
        case installIINA
    }

    private struct CollectionQuery: Hashable {
        let collectionID: String
        let sort: MediaSort
    }

    private struct CollectionPageState {
        var items: [MediaSummary]
        var nextPage: Int
        var total: Int
        var canLoadMore: Bool
    }

    private static let collectionPageSize = 20

    enum Phase {
        case launching
        case signedOut
        case signedIn
    }

    private(set) var phase: Phase = .launching
    private(set) var hotItems: [MediaSummary] = []
    private(set) var continueWatching: [ContinueWatchingItem] = []
    private(set) var collections: [MediaCollection] = []
    private var collectionPages: [CollectionQuery: CollectionPageState] = [:]
    private var loadingCollectionQueries: Set<CollectionQuery> = []
    private(set) var searchResults: [MediaSummary] = []
    private(set) var isLoadingHome = false
    private(set) var isSearching = false
    private(set) var playingItemID: String?
    private(set) var errorRecovery: ErrorRecovery?
    var errorMessage: String?

    @ObservationIgnored private var suppressesPlaybackRefresh = false
    @ObservationIgnored let provider: any MediaLibraryProvider
    @ObservationIgnored let playback: PlaybackCoordinator

    init(provider: any MediaLibraryProvider, launcher: any PlaybackLaunching) {
        self.provider = provider
        let playback = PlaybackCoordinator(provider: provider, launcher: launcher)
        self.playback = playback
        playback.onStoppedReported = { [weak self] in
            guard let self,
                  self.phase == .signedIn,
                  !self.suppressesPlaybackRefresh else { return }
            await self.refreshContinueWatching()
        }
    }

    func bootstrap() async {
        guard phase == .launching else { return }
        do {
            if try await provider.restoreSession() == nil {
                phase = .signedOut
            } else {
                phase = .signedIn
                await refreshHome()
            }
        } catch {
            phase = .signedOut
            present(error)
        }
    }

    func signIn(username: String, password: String, totpCode: String?) async {
        errorMessage = nil
        do {
            _ = try await provider.signIn(
                credentials: ProviderCredentials(
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    totpCode: totpCode?.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            phase = .signedIn
            await refreshHome()
        } catch {
            phase = .signedOut
            present(error)
        }
    }

    func signOut() async {
        suppressesPlaybackRefresh = true
        await playback.stop()
        await provider.signOut()
        hotItems = []
        continueWatching = []
        collections = []
        collectionPages = [:]
        loadingCollectionQueries = []
        searchResults = []
        errorMessage = nil
        phase = .signedOut
        suppressesPlaybackRefresh = false
    }

    func refreshHome() async {
        guard phase == .signedIn else { return }
        isLoadingHome = true
        errorMessage = nil

        async let hotRequest = provider.hot(page: PageRequest(number: 1, size: 20))
        async let collectionsRequest = provider.collections()
        async let shelfRequest = provider.playbackShelf(limit: 16)

        do {
            hotItems = try await hotRequest.items
        } catch {
            handleAuthenticated(error)
        }
        do {
            collections = try await collectionsRequest
            await withTaskGroup(of: Void.self) { group in
                for collection in collections {
                    group.addTask {
                        await self.loadCollection(collection, sort: .newest)
                    }
                }
                await group.waitForAll()
            }
        } catch {
            handleAuthenticated(error)
        }
        do {
            continueWatching = try await shelfRequest.resume
        } catch {
            handleAuthenticated(error)
        }

        isLoadingHome = false
    }

    func refreshContinueWatching() async {
        guard phase == .signedIn, !suppressesPlaybackRefresh else { return }
        Self.logger.info("Refreshing Continue Watching after playback synchronization")
        do {
            let shelf = try await provider.playbackShelf(limit: 16)
            guard phase == .signedIn, !suppressesPlaybackRefresh else { return }
            continueWatching = shelf.resume
            Self.logger.info(
                "Continue Watching refresh completed items=\(self.continueWatching.count)"
            )
        } catch is CancellationError {
            Self.logger.notice("Continue Watching refresh was cancelled")
            return
        } catch {
            Self.logger.error("Continue Watching refresh failed")
            handleAuthenticated(error)
        }
    }

    func items(in collection: MediaCollection, sort: MediaSort) -> [MediaSummary] {
        collectionPages[CollectionQuery(collectionID: collection.id, sort: sort)]?.items ?? []
    }

    func isLoading(_ collection: MediaCollection, sort: MediaSort) -> Bool {
        loadingCollectionQueries.contains(
            CollectionQuery(collectionID: collection.id, sort: sort)
        )
    }

    func canLoadMore(_ collection: MediaCollection, sort: MediaSort) -> Bool {
        guard let state = collectionPages[
            CollectionQuery(collectionID: collection.id, sort: sort)
        ] else {
            return false
        }
        return state.canLoadMore && state.items.count < state.total
    }

    func loadCollection(_ collection: MediaCollection, sort: MediaSort) async {
        let query = CollectionQuery(collectionID: collection.id, sort: sort)
        guard collectionPages[query] == nil else { return }

        await loadCollectionPage(
            collection,
            sort: sort,
            pageNumber: 1,
            replacingItems: true
        )
    }

    func loadMore(in collection: MediaCollection, sort: MediaSort) async {
        let query = CollectionQuery(collectionID: collection.id, sort: sort)
        guard let state = collectionPages[query], state.canLoadMore else { return }

        await loadCollectionPage(
            collection,
            sort: sort,
            pageNumber: state.nextPage,
            replacingItems: false
        )
    }

    private func loadCollectionPage(
        _ collection: MediaCollection,
        sort: MediaSort,
        pageNumber: Int,
        replacingItems: Bool
    ) async {
        let query = CollectionQuery(collectionID: collection.id, sort: sort)
        guard !loadingCollectionQueries.contains(query) else { return }

        loadingCollectionQueries.insert(query)
        defer { loadingCollectionQueries.remove(query) }

        do {
            let page = try await provider.items(
                in: collection.id,
                page: PageRequest(number: pageNumber, size: Self.collectionPageSize),
                sort: sort
            )
            guard !Task.isCancelled, phase == .signedIn else { return }

            let existingItems = replacingItems
                ? []
                : collectionPages[query]?.items ?? []
            let items = appendingUnique(page.items, to: existingItems)
            let loadedThrough = max(page.number, pageNumber) * max(page.size, 1)
            let total = max(page.total, items.count)

            collectionPages[query] = CollectionPageState(
                items: items,
                nextPage: max(page.number, pageNumber) + 1,
                total: total,
                canLoadMore: !page.items.isEmpty && loadedThrough < total
            )
        } catch is CancellationError {
            return
        } catch {
            handleAuthenticated(error)
        }
    }

    private func appendingUnique(
        _ newItems: [MediaSummary],
        to existingItems: [MediaSummary]
    ) -> [MediaSummary] {
        var knownIDs = Set(existingItems.map(\.id))
        return existingItems + newItems.filter { knownIDs.insert($0.id).inserted }
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        do {
            let page = try await provider.search(
                trimmed,
                page: PageRequest(number: 1, size: 60)
            )
            guard !Task.isCancelled else { return }
            searchResults = page.items
        } catch is CancellationError {
            return
        } catch {
            handleAuthenticated(error)
        }
        isSearching = false
    }

    func play(_ item: ContinueWatchingItem) async {
        playingItemID = item.id
        do {
            try await playback.playFirst(
                item: item.item,
                title: item.title,
                startPositionSeconds: item.userState.positionSeconds,
                seriesID: item.item.kind == .episode ? item.mediaID : nil
            )
        } catch {
            present(error)
        }
        playingItemID = nil
    }

    func prepareForTermination() async {
        suppressesPlaybackRefresh = true
        await playback.stop()
    }

    func dismissError() {
        errorMessage = nil
        errorRecovery = nil
    }

    func performErrorRecovery() {
        guard errorRecovery == .installIINA,
              let url = URL(string: "https://iina.io/download/") else { return }
        dismissError()
        NSWorkspace.shared.open(url)
    }

    private func handleAuthenticated(_ error: Error) {
        guard !(error is CancellationError) else { return }
        if error as? ProviderError == .sessionExpired ||
            error as? ProviderError == .unauthenticated {
            phase = .signedOut
        }
        present(error)
    }

    private func present(_ error: Error) {
        errorRecovery = nil
        switch error {
        case let providerError as ProviderError:
            errorMessage = providerError.errorDescription
        case let playbackError as PlaybackLaunchError:
            errorMessage = playbackError.errorDescription
            if case .iinaNotInstalled = playbackError {
                errorRecovery = .installIINA
            }
        default:
            errorMessage = "CineLark could not complete the request."
        }
    }
}
