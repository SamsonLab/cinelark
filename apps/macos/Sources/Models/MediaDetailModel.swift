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
    private(set) var seriesPlaybackState: SeriesPlaybackState?
    private(set) var isLoading = false
    private(set) var isLoadingEpisodes = false
    private(set) var isUpdatingFavorite = false
    private(set) var isStartingPlayback = false
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
        guard let loaded = detail?.summary else { return initialItem }
        return MediaSummary(
            id: initialItem.id,
            kind: initialItem.kind,
            title: loaded.title.isEmpty ? initialItem.title : loaded.title,
            originalTitle: loaded.originalTitle ?? initialItem.originalTitle,
            synopsis: loaded.synopsis ?? initialItem.synopsis,
            releaseYear: loaded.releaseYear ?? initialItem.releaseYear,
            rating: loaded.rating ?? initialItem.rating,
            durationSeconds: loaded.durationSeconds ?? initialItem.durationSeconds,
            posterURL: heroPosterURL,
            backdropURL: heroBackdropURL,
            logoURL: loaded.logoURL ?? initialItem.logoURL,
            totalSeasons: loaded.totalSeasons ?? initialItem.totalSeasons,
            hasMultipleVersions: loaded.hasMultipleVersions || initialItem.hasMultipleVersions,
            genres: loaded.genres.isEmpty ? initialItem.genres : loaded.genres,
            userState: loaded.userState == .empty ? initialItem.userState : loaded.userState
        )
    }

    var heroPosterURL: URL? {
        initialItem.posterURL ?? detail?.summary.posterURL
    }

    var heroBackdropURL: URL? {
        initialItem.backdropURL ?? detail?.summary.backdropURL
    }

    var isFavorite: Bool {
        favoriteState ?? item.userState.favorite ?? false
    }

    var canRemoveFavorite: Bool {
        initialItem.kind == .series
    }

    var resumableSeriesItem: ContinueWatchingItem? {
        seriesPlaybackState?.resumableItem
    }

    var primarySeriesItem: ContinueWatchingItem? {
        seriesPlaybackState?.primaryItem
    }

    var canStartPlayback: Bool {
        switch initialItem.kind {
        case .movie:
            !movieAssets.isEmpty
        case .series:
            primarySeriesItem != nil || !episodes.isEmpty
        }
    }

    func load() async {
        guard detail == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        async let detailRequest = provider.detail(for: initialItem)

        switch initialItem.kind {
        case .movie:
            async let assetsRequest = provider.assets(
                for: PlayableItem(id: initialItem.id, kind: .movie)
            )
            do {
                movieAssets = try await assetsRequest
            } catch is CancellationError {
                return
            } catch {
                present(error)
            }
        case .series:
            async let playbackStateRequest = provider.playbackState(seriesID: initialItem.id)
            async let seasonsRequest = provider.seasons(seriesID: initialItem.id)

            seriesPlaybackState = try? await playbackStateRequest
            do {
                seasons = try await seasonsRequest
                let preferredSeasonID = seasonID(for: primarySeriesItem) ?? seasons.first?.id
                if let preferredSeasonID {
                    await selectSeason(preferredSeasonID)
                }
            } catch is CancellationError {
                return
            } catch {
                present(error)
            }
        }

        do {
            detail = try await detailRequest
            favoriteState = detail?.summary.userState.favorite
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }
    }

    func selectSeason(_ seasonID: String) async {
        await loadEpisodes(seasonID: seasonID, force: false)
    }

    func refreshPlaybackContext() async {
        do {
            switch initialItem.kind {
            case .movie:
                detail = try await provider.detail(for: initialItem)
            case .series:
                seriesPlaybackState = try await provider.playbackState(seriesID: initialItem.id)
                let preferredSeasonID = seasonID(for: primarySeriesItem) ?? selectedSeasonID
                if let preferredSeasonID {
                    await loadEpisodes(seasonID: preferredSeasonID, force: true)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }
    }

    func playPrimary() async {
        guard canStartPlayback, !isStartingPlayback else { return }
        isStartingPlayback = true
        defer { isStartingPlayback = false }
        do {
            switch initialItem.kind {
            case .movie:
                guard let asset = movieAssets.first else { throw ProviderError.notFound }
                try await playback.play(
                    item: PlayableItem(id: item.id, kind: .movie),
                    asset: asset,
                    title: item.title,
                    startPositionSeconds: item.userState.played
                        ? 0
                        : item.userState.positionSeconds
                )
            case .series:
                if let target = primarySeriesItem {
                    try await playback.playFirst(
                        item: target.item,
                        title: target.title,
                        startPositionSeconds: target.userState.positionSeconds,
                        seriesID: initialItem.id
                    )
                } else if let firstEpisode = episodes.first {
                    try await playback.playFirst(
                        item: PlayableItem(id: firstEpisode.id, kind: .episode),
                        title: firstEpisode.title,
                        seriesID: initialItem.id
                    )
                }
            }
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

    private func seasonID(for item: ContinueWatchingItem?) -> String? {
        guard let item else { return nil }
        if let seasonID = item.seasonID {
            return seasonID
        }
        guard let seasonNumber = item.seasonNumber else { return nil }
        return seasons.first { $0.number == seasonNumber }?.id
    }

    private func loadEpisodes(seasonID: String, force: Bool) async {
        guard force || selectedSeasonID != seasonID || episodes.isEmpty else { return }
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

    private func present(_ error: Error) {
        if let error = error as? LocalizedError,
           let description = error.errorDescription {
            errorMessage = description
        } else {
            errorMessage = "CineLark could not complete the request."
        }
    }
}
