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
    private(set) var playingID: String?
    var errorMessage: String?

    @ObservationIgnored private let provider: any MediaLibraryProvider
    @ObservationIgnored private let playback: PlaybackCoordinator

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

    func load() async {
        guard detail == nil, !isLoading else { return }
        isLoading = true
        do {
            detail = try await provider.detail(for: initialItem)
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
        } catch {
            present(error)
        }
        isLoading = false
    }

    func selectSeason(_ seasonID: String) async {
        guard selectedSeasonID != seasonID || episodes.isEmpty else { return }
        selectedSeasonID = seasonID
        isLoadingEpisodes = true
        do {
            let page = try await provider.episodes(
                seriesID: initialItem.id,
                seasonID: seasonID,
                page: PageRequest(number: 1, size: 100)
            )
            guard selectedSeasonID == seasonID else { return }
            episodes = page.items
        } catch {
            present(error)
        }
        isLoadingEpisodes = false
    }

    func playMovie(asset: MediaAsset) async {
        playingID = asset.id
        do {
            try await playback.play(
                asset: asset,
                title: item.title,
                startPositionSeconds: item.userState.positionSeconds
            )
        } catch {
            present(error)
        }
        playingID = nil
    }

    func playEpisode(_ episode: Episode) async {
        playingID = episode.id
        do {
            try await playback.playFirst(
                item: PlayableItem(id: episode.id, kind: .episode),
                title: episode.title,
                startPositionSeconds: episode.userState.positionSeconds
            )
        } catch {
            present(error)
        }
        playingID = nil
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
