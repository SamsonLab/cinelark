import Foundation
import Observation
import CineLarkDomain
import CineLarkPlayback

@Observable
@MainActor
final class AppModel {
    enum Phase {
        case launching
        case signedOut
        case signedIn
    }

    private(set) var phase: Phase = .launching
    private(set) var hotItems: [MediaSummary] = []
    private(set) var continueWatching: [ContinueWatchingItem] = []
    private(set) var collections: [MediaCollection] = []
    private(set) var collectionItems: [String: [MediaSummary]] = [:]
    private(set) var searchResults: [MediaSummary] = []
    private(set) var isLoadingHome = false
    private(set) var loadingCollectionID: String?
    private(set) var isSearching = false
    private(set) var playingItemID: String?
    var errorMessage: String?

    @ObservationIgnored let provider: any MediaLibraryProvider
    @ObservationIgnored let playback: PlaybackCoordinator

    init(provider: any MediaLibraryProvider, launcher: any PlaybackLaunching) {
        self.provider = provider
        self.playback = PlaybackCoordinator(provider: provider, launcher: launcher)
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
        await provider.signOut()
        hotItems = []
        continueWatching = []
        collections = []
        collectionItems = [:]
        searchResults = []
        errorMessage = nil
        phase = .signedOut
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

    func loadCollection(_ collection: MediaCollection) async {
        guard collectionItems[collection.id] == nil else { return }
        loadingCollectionID = collection.id
        do {
            let page = try await provider.items(
                in: collection.id,
                page: PageRequest(number: 1, size: 60),
                sort: .newest
            )
            collectionItems[collection.id] = page.items
        } catch {
            handleAuthenticated(error)
        }
        loadingCollectionID = nil
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
                startPositionSeconds: item.userState.positionSeconds
            )
        } catch {
            present(error)
        }
        playingItemID = nil
    }

    func dismissError() {
        errorMessage = nil
    }

    private func handleAuthenticated(_ error: Error) {
        if error as? ProviderError == .sessionExpired ||
            error as? ProviderError == .unauthenticated {
            phase = .signedOut
        }
        present(error)
    }

    private func present(_ error: Error) {
        switch error {
        case let providerError as ProviderError:
            errorMessage = providerError.errorDescription
        case let playbackError as PlaybackLaunchError:
            errorMessage = playbackError.errorDescription
        default:
            errorMessage = "CineLark could not complete the request."
        }
    }
}
