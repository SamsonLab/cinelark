import Foundation
import Observation
import CineLarkDomain

@Observable
@MainActor
final class MediaDetailModel {
    let initialItem: MediaSummary

    private(set) var detail: MediaDetail?
    private(set) var seasons: [Season] = []
    private(set) var selectedSeasonID: String?
    private(set) var episodes: [Episode] = []
    private(set) var movieAssets: [MediaAsset] = []
    private(set) var isLoading = false
    private(set) var isLoadingEpisodes = false
    private(set) var isUpdatingFavorite = false
    private(set) var favoriteState: Bool?
    var errorMessage: String?

    @ObservationIgnored private let provider: any MediaLibraryProvider
    @ObservationIgnored let playback: PlaybackCoordinator

    init(
        item: MediaSummary,
        provider: any MediaLibraryProvider,
        playback: PlaybackCoordinator
    ) {
        self.initialItem = item
        self.provider = provider
        self.playback = playback
    }

    var item: MediaSummary {
        detail?.summary ?? initialItem
    }

    var isFavorite: Bool {
        favoriteState ?? item.userState.favorite ?? false
    }

    var canRemoveFavorite: Bool {
        initialItem.kind == .series
    }

    func load() async {
        guard detail == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await provider.detail(for: initialItem)
            favoriteState = detail?.summary.userState.favorite
            switch initialItem.kind {
            case .movie:
                movieAssets = try await provider.assets(
                    for: PlayableItem(id: initialItem.id, kind: .movie)
                )
            case .series:
                seasons = try await provider.seasons(seriesID: initialItem.id)
                if let first = seasons.first {
                    await selectSeason(first.id)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }
    }

    func selectSeason(_ seasonID: String) async {
        guard selectedSeasonID != seasonID || episodes.isEmpty else { return }
        selectedSeasonID = seasonID
        isLoadingEpisodes = true
        defer {
            if selectedSeasonID == seasonID {
                isLoadingEpisodes = false
            }
        }
        do {
            let page = try await provider.episodes(
                seriesID: initialItem.id,
                seasonID: seasonID,
                page: PageRequest(number: 1, size: 100)
            )
            guard selectedSeasonID == seasonID, !Task.isCancelled else { return }
            episodes = page.items
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }
    }

    func toggleFavorite() async {
        guard !isUpdatingFavorite else { return }
        let desiredState = !isFavorite
        guard desiredState || canRemoveFavorite else { return }

        isUpdatingFavorite = true
        defer { isUpdatingFavorite = false }
        do {
            favoriteState = try await provider.setFavorite(
                desiredState,
                target: FavoriteTarget(
                    id: initialItem.id,
                    kind: initialItem.kind == .movie ? .movie : .series
                )
            )
        } catch {
            present(error)
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func present(_ error: Error) {
        if let error = error as? LocalizedError,
           let description = error.errorDescription {
            errorMessage = description
        } else {
            errorMessage = "CineLark could not complete the request."
        }
    }
}
