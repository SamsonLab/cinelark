import ComposableArchitecture
import Foundation
import Testing
import CineLarkDomain
import CineLarkPluginAPI
import CineLarkProfile

@testable import CineLark

@MainActor
struct MediaDetailFeatureTests {
    @Test("Series primary playback resumes the in-progress episode")
    func primarySeriesPlaybackResumesEpisode() async {
        let sourceID = SourceID(rawValue: UUID())
        let locator = MediaLocatorID(sourceID: sourceID, providerItemID: "series-1")
        let item = MediaSummary(id: locator.providerItemID, kind: .series, title: "Series")
        let watched = Episode(
            id: "episode-1",
            seriesID: item.id,
            seasonID: "season-1",
            number: 1,
            title: "Watched",
            synopsis: nil,
            airDate: nil,
            thumbnailURL: nil,
            durationSeconds: 1_800,
            hasMultipleVersions: false,
            userState: UserPlaybackState(
                played: true,
                positionSeconds: 0,
                progress: 1
            )
        )
        let resume = Episode(
            id: "episode-2",
            seriesID: item.id,
            seasonID: "season-1",
            number: 2,
            title: "Resume",
            synopsis: nil,
            airDate: nil,
            thumbnailURL: nil,
            durationSeconds: 1_800,
            hasMultipleVersions: false,
            userState: UserPlaybackState(
                played: false,
                positionSeconds: 600,
                progress: 0.33
            )
        )
        var state = MediaDetailFeature.State(
            locator: locator,
            profileID: nil,
            initialItem: item
        )
        state.episodes = [watched, resume]
        let store = TestStore(initialState: state) {
            MediaDetailFeature()
        }

        await store.send(.view(.playPrimary))
        await store.receive(.delegate(.play(
            locator: MediaLocatorID(sourceID: sourceID, providerItemID: resume.id),
            title: resume.title,
            kind: .episode,
            artworkURL: nil,
            metadata: nil,
            startPositionSeconds: 600,
            variantID: nil
        )))
    }

    @Test("Series playback state selects and resumes an episode from another season")
    func crossSeasonSeriesPlayback() async {
        let sourceID = SourceID(rawValue: UUID())
        let locator = MediaLocatorID(sourceID: sourceID, providerItemID: "series-1")
        let item = MediaSummary(id: locator.providerItemID, kind: .series, title: "Series")
        let season1 = Season(
            id: "season-1",
            seriesID: item.id,
            number: 1,
            title: "Season 1",
            posterURL: nil,
            episodeCount: 8,
            userState: .empty
        )
        let season2 = Season(
            id: "season-2",
            seriesID: item.id,
            number: 2,
            title: "Season 2",
            posterURL: nil,
            episodeCount: 8,
            userState: .empty
        )
        let target = ContinueWatchingItem(
            id: "episode:episode-4",
            item: PlayableItem(id: "episode-4", kind: .episode),
            mediaID: item.id,
            title: "Continue",
            subtitle: nil,
            posterURL: nil,
            thumbnailURL: nil,
            durationSeconds: 3_600,
            seasonID: season2.id,
            seasonNumber: season2.number,
            episodeNumber: 4,
            userState: UserPlaybackState(
                played: false,
                positionSeconds: 900,
                progress: 0.25
            )
        )
        let playbackState = SeriesPlaybackState(resume: target, nextUp: nil)
        var state = MediaDetailFeature.State(
            locator: locator,
            profileID: nil,
            initialItem: item
        )
        state.seasons = [season1, season2]
        state.selectedSeasonID = season1.id
        let store = TestStore(initialState: state) {
            MediaDetailFeature()
        } withDependencies: {
            $0.mediaPlatform = MediaPlatformClient(
                descriptors: { [] },
                cachedPage: { _ in throw MediaSourceFailure.unavailable },
                refreshPage: { _ in throw MediaSourceFailure.unavailable },
                episodes: { _, seasonID, _ in
                    #expect(seasonID == season2.id)
                    return Page(number: 1, size: 200, total: 0, items: [])
                }
            )
        }

        await store.send(.internal(.seriesPlaybackLoaded(playbackState))) {
            $0.seriesPlaybackState = playbackState
            $0.didApplyPlaybackSeason = true
        }
        await store.receive(.view(.seasonSelected(season2.id))) {
            $0.selectedSeasonID = season2.id
            $0.isLoadingEpisodes = true
        }
        await store.receive(.internal(.episodesLoaded(
            season2.id,
            .success(Page(number: 1, size: 200, total: 0, items: []))
        ))) {
            $0.isLoadingEpisodes = false
        }
        await store.send(.view(.playPrimary))
        await store.receive(.delegate(.play(
            locator: MediaLocatorID(sourceID: sourceID, providerItemID: target.item.id),
            title: target.title,
            kind: .episode,
            artworkURL: nil,
            metadata: nil,
            startPositionSeconds: 900,
            variantID: nil
        )))
    }

    @Test("Authoritative Series detail recovers seasons and episodes from a stale list kind")
    func authoritativeSeriesKindLoadsHierarchy() async {
        let sourceID = SourceID(rawValue: UUID())
        let locator = MediaLocatorID(sourceID: sourceID, providerItemID: "series-1")
        let initial = MediaSummary(id: locator.providerItemID, kind: .movie, title: "Stale Item")
        let series = MediaSummary(id: locator.providerItemID, kind: .series, title: "Series")
        let detail = MediaDetail(
            summary: series,
            directors: [],
            cast: [],
            tmdbID: nil,
            imdbID: nil
        )
        let season = Season(
            id: "season-1",
            seriesID: locator.providerItemID,
            number: 1,
            title: "Season 1",
            posterURL: nil,
            episodeCount: 1,
            userState: .empty
        )
        let episode = Episode(
            id: "episode-1",
            seriesID: locator.providerItemID,
            seasonID: season.id,
            number: 1,
            title: "Pilot",
            synopsis: "Episode overview",
            airDate: nil,
            thumbnailURL: nil,
            durationSeconds: 1_800,
            versionCount: 1,
            hasMultipleVersions: false,
            userState: .empty
        )
        let store = TestStore(
            initialState: MediaDetailFeature.State(
                locator: locator,
                profileID: nil,
                initialItem: initial
            )
        ) {
            MediaDetailFeature()
        } withDependencies: {
            $0.mediaPlatform = MediaPlatformClient(
                descriptors: { [] },
                cachedPage: { _ in MediaPage(items: [], nextCursor: nil, total: 0) },
                refreshPage: { _ in MediaPage(items: [], nextCursor: nil, total: 0) },
                detail: { _, _ in detail },
                seasons: { _ in [season] },
                episodes: { _, _, _ in
                    Page(number: 1, size: 200, total: 1, items: [episode])
                }
            )
        }

        await store.send(.view(.appeared)) {
            $0.isLoading = true
            $0.isLoadingMovieVariants = true
        }
        await store.receive(.internal(.detailLoaded(.success(detail)))) {
            $0.isLoading = false
            $0.detail = detail
            $0.didRequestSeasons = true
        }
        await store.receive(.internal(.movieVariantsLoaded(.success([])))) {
            $0.isLoadingMovieVariants = false
        }
        await store.receive(.internal(.seriesPlaybackLoaded(
            SeriesPlaybackState(resume: nil, nextUp: nil)
        ))) {
            $0.seriesPlaybackState = SeriesPlaybackState(resume: nil, nextUp: nil)
        }
        await store.receive(.internal(.seasonsLoaded(.success([season])))) {
            $0.seasons = [season]
        }
        await store.receive(.view(.seasonSelected(season.id))) {
            $0.selectedSeasonID = season.id
            $0.isLoadingEpisodes = true
        }
        await store.receive(.internal(.episodesLoaded(
            season.id,
            .success(Page(number: 1, size: 200, total: 1, items: [episode]))
        ))) {
            $0.isLoadingEpisodes = false
            $0.episodes = [episode]
        }
    }

    @Test("Hierarchy episode playback preserves episode identity and series metadata")
    func episodePlaybackIdentity() async {
        let sourceID = SourceID(rawValue: UUID())
        let seriesLocator = MediaLocatorID(
            sourceID: sourceID,
            providerItemID: "series-1"
        )
        let genre = Genre(id: 1, name: "Drama", slug: "drama")
        let item = MediaSummary(
            id: seriesLocator.providerItemID,
            kind: .series,
            title: "Synthetic Series",
            genres: [genre]
        )
        let episode = Episode(
            id: "episode-1",
            seriesID: seriesLocator.providerItemID,
            seasonID: "season-1",
            number: 1,
            title: "Synthetic Pilot",
            synopsis: nil,
            airDate: nil,
            thumbnailURL: nil,
            durationSeconds: 1_800,
            versionCount: 1,
            hasMultipleVersions: false,
            userState: .empty
        )
        let variant = PlaybackVariant(
            id: "source-1080p",
            displayName: "1080p HEVC",
            width: 1_920,
            height: 1_080,
            videoCodec: "hevc",
            isPreferred: true
        )
        let store = TestStore(
            initialState: MediaDetailFeature.State(
                locator: seriesLocator,
                profileID: nil,
                initialItem: item
            )
        ) {
            MediaDetailFeature()
        } withDependencies: {
            $0.mediaPlatform = MediaPlatformClient(
                descriptors: { [] },
                cachedPage: { _ in throw MediaSourceFailure.unavailable },
                refreshPage: { _ in throw MediaSourceFailure.unavailable },
                playbackVariants: { _ in [variant] }
            )
        }

        await store.send(.view(.episodeSelected(episode))) {
            $0.playbackOptions = PlaybackOptionsFeature.State(
                locator: MediaLocatorID(sourceID: sourceID, providerItemID: episode.id),
                title: episode.title,
                subtitle: nil,
                episodeNumber: episode.number,
                kind: .episode,
                artworkURL: nil,
                metadata: ProfileMediaMetadataSnapshot(
                    genres: [ProfileGenreSnapshot(name: genre.name, slug: genre.slug)]
                ),
                startPositionSeconds: 0
            )
        }
        await store.send(.playbackOptions(.presented(.view(.appeared)))) {
            $0.playbackOptions?.isLoading = true
        }
        await store.receive(.playbackOptions(.presented(.internal(
            .variantsLoaded(.success([variant]))
        )))) {
            $0.playbackOptions?.isLoading = false
            $0.playbackOptions?.variants = [variant]
        }
        await store.send(.playbackOptions(.presented(.view(
            .variantSelected(variant.id)
        ))))
        await store.receive(.playbackOptions(.presented(.delegate(.play(variant.id))))) {
            $0.playbackOptions = nil
        }
        await store.receive(.delegate(.play(
            locator: MediaLocatorID(sourceID: sourceID, providerItemID: episode.id),
            title: episode.title,
            kind: .episode,
            artworkURL: nil,
            metadata: ProfileMediaMetadataSnapshot(
                genres: [ProfileGenreSnapshot(
                    name: genre.name,
                    slug: genre.slug
                )]
            ),
            startPositionSeconds: 0,
            variantID: variant.id
        )))
    }
}
