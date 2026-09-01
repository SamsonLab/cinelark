import ComposableArchitecture
import Foundation
import CineLarkDomain
import CineLarkPluginAPI
import CineLarkProfile

@Reducer
struct PlaybackOptionsFeature {
    @ObservableState
    struct State: Equatable {
        let locator: MediaLocatorID
        let title: String
        let subtitle: String?
        let episodeNumber: Int?
        let kind: MediaKind
        let artworkURL: URL?
        let metadata: ProfileMediaMetadataSnapshot?
        let startPositionSeconds: Double
        var variants: [PlaybackVariant] = []
        var expandedVariantID: String?
        var isLoading = false
        var failure: MediaSourceFailure?
    }

    enum Action: Equatable {
        case view(View)
        case `internal`(Internal)
        case delegate(Delegate)

        enum View: Equatable {
            case appeared
            case dismissFailure
            case toggleDetails(String)
            case variantSelected(String)
        }

        enum Internal: Equatable {
            case variantsLoaded(Result<[PlaybackVariant], MediaSourceFailure>)
        }

        enum Delegate: Equatable {
            case play(String)
        }
    }

    @Dependency(\.mediaPlatform) private var mediaPlatform

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.appeared):
                guard state.variants.isEmpty, !state.isLoading else { return .none }
                state.isLoading = true
                state.failure = nil
                let locator = state.locator
                return .run { send in
                    do {
                        await send(.internal(.variantsLoaded(.success(
                            try await mediaPlatform.playbackVariants(locator)
                        ))))
                    } catch {
                        await send(.internal(.variantsLoaded(.failure(Self.normalize(error)))))
                    }
                }

            case let .internal(.variantsLoaded(.success(variants))):
                state.isLoading = false
                state.variants = variants
                return .none

            case let .internal(.variantsLoaded(.failure(failure))):
                state.isLoading = false
                state.failure = failure
                return .none

            case let .view(.toggleDetails(id)):
                guard state.variants.contains(where: { $0.id == id }) else { return .none }
                state.expandedVariantID = state.expandedVariantID == id ? nil : id
                return .none

            case let .view(.variantSelected(id)):
                guard state.variants.contains(where: { $0.id == id }) else { return .none }
                return .send(.delegate(.play(id)))

            case .view(.dismissFailure):
                state.failure = nil
                return .none

            case .delegate:
                return .none
            }
        }
    }

    private static func normalize(_ error: Error) -> MediaSourceFailure {
        if let failure = error as? MediaSourceFailure { return failure }
        return .transport(String(describing: error))
    }
}

@Reducer
struct MediaDetailFeature {
    @ObservableState
    struct State: Equatable {
        let locator: MediaLocatorID
        let profileID: ProfileID?
        let initialItem: MediaSummary
        var detail: MediaDetail?
        var seasons: [Season] = []
        var didRequestSeasons = false
        var didApplyPlaybackSeason = false
        var selectedSeasonID: String?
        var episodes: [Episode] = []
        var seriesPlaybackState: SeriesPlaybackState?
        var movieVariants: [PlaybackVariant] = []
        var isLoading = false
        var isLoadingEpisodes = false
        var isLoadingMovieVariants = false
        var isUpdatingFavorite = false
        var localStates: [ProfileMediaKey: ProfileMediaState] = [:]
        var failure: MediaSourceFailure?
        @Presents var playbackOptions: PlaybackOptionsFeature.State?

        var mediaKey: ProfileMediaKey { ProfileMediaKey(locator: locator) }
        var localState: ProfileMediaState { localStates[mediaKey] ?? ProfileMediaState() }
        var item: MediaSummary {
            (detail?.summary ?? initialItem).replacingUserState(localState.userState)
        }
        var isFavorite: Bool { localState.isFavorite }
        var primaryEpisode: Episode? {
            episodes.first {
                !$0.userState.played && $0.userState.positionSeconds > 0
            } ?? episodes.first {
                !$0.userState.played
            } ?? episodes.first
        }
        var resumableSeriesItem: ContinueWatchingItem? {
            seriesPlaybackState?.resumableItem
        }
        var primarySeriesItem: ContinueWatchingItem? {
            seriesPlaybackState?.primaryItem ?? primaryEpisode.map { episode in
                ContinueWatchingItem(
                    id: "episode:\(episode.id)",
                    item: PlayableItem(id: episode.id, kind: .episode),
                    mediaID: locator.providerItemID,
                    title: episode.title,
                    subtitle: nil,
                    posterURL: item.posterURL,
                    thumbnailURL: episode.thumbnailURL,
                    durationSeconds: episode.durationSeconds,
                    seasonID: episode.seasonID,
                    seasonNumber: seasons.first { $0.id == episode.seasonID }?.number,
                    episodeNumber: episode.number,
                    userState: episode.userState
                )
            }
        }
        var canPlayPrimary: Bool {
            item.kind != .series || primarySeriesItem != nil
        }
    }

    enum Action: Equatable {
        case view(View)
        case `internal`(Internal)
        case playbackOptions(PresentationAction<PlaybackOptionsFeature.Action>)
        case delegate(Delegate)

        enum View: Equatable {
            case appeared
            case seasonSelected(String)
            case toggleFavorite
            case playPrimary
            case movieVariantSelected(String)
            case episodeSelected(Episode)
        }

        enum Internal: Equatable {
            case detailLoaded(Result<MediaDetail, MediaSourceFailure>)
            case profileStateLoaded(ProfileID, Result<ProfileStateSnapshot, ProfileClientFailure>)
            case seasonsLoaded(Result<[Season], MediaSourceFailure>)
            case seriesPlaybackLoaded(SeriesPlaybackState)
            case episodesLoaded(String, Result<Page<Episode>, MediaSourceFailure>)
            case movieVariantsLoaded(Result<[PlaybackVariant], MediaSourceFailure>)
            case favoriteSaved(Bool, Result<Bool, MediaSourceFailure>)
        }

        enum Delegate: Equatable {
            case play(
                locator: MediaLocatorID,
                title: String,
                kind: MediaKind,
                artworkURL: URL?,
                metadata: ProfileMediaMetadataSnapshot?,
                startPositionSeconds: Double,
                variantID: String?
            )
        }
    }

    private enum CancelID {
        case load
        case seasons
        case episodes
        case movieVariants
        case favorite
    }

    @Dependency(\.mediaPlatform) private var mediaPlatform
    @Dependency(\.profiles) private var profiles
    @Dependency(\.date.now) private var now
    @Dependency(\.performance) private var performance

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.appeared):
                guard !state.isLoading, state.detail == nil else { return .none }
                state.isLoading = true
                state.failure = nil
                let locator = state.locator
                let item = state.initialItem
                var effects: [Effect<Action>] = [
                    .run { send in
                        let interval = performance.start(.mediaDetail)
                        do {
                            await send(.internal(.detailLoaded(.success(
                                try await mediaPlatform.detail(locator, item)
                            ))))
                            performance.finish(interval, .success)
                        } catch is CancellationError {
                            performance.finish(interval, .cancelled)
                        } catch {
                            performance.finish(interval, .failure)
                            await send(.internal(.detailLoaded(.failure(Self.normalize(error)))))
                        }
                    }
                ]
                if item.kind == .series {
                    state.didRequestSeasons = true
                    effects.append(loadSeasons(locator))
                    effects.append(loadSeriesPlayback(locator))
                } else if item.kind == .movie {
                    state.isLoadingMovieVariants = true
                    effects.append(loadMovieVariants(locator))
                }
                if let profileID = state.profileID {
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
                return .merge(effects)
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .internal(.detailLoaded(.success(detail))):
                state.isLoading = false
                state.detail = detail
                guard detail.summary.kind == .series, !state.didRequestSeasons else {
                    return .none
                }
                state.didRequestSeasons = true
                let locator = state.locator
                return .merge(
                    loadSeasons(locator)
                        .cancellable(id: CancelID.seasons, cancelInFlight: true),
                    loadSeriesPlayback(locator)
                )

            case let .internal(.profileStateLoaded(profileID, .success(snapshot))):
                guard state.profileID == profileID else { return .none }
                let sourceKeys = Set(snapshot.snapshots.compactMap { key, value in
                    value.locator.sourceID == state.locator.sourceID ? key : nil
                })
                let localStates = snapshot.states.filter { sourceKeys.contains($0.key) }
                state.localStates = localStates
                state.episodes = applyingLocalState(
                    to: state.episodes,
                    sourceID: state.locator.sourceID,
                    states: localStates
                )
                return .none

            case let .internal(.profileStateLoaded(profileID, .failure(failure))):
                guard state.profileID == profileID else { return .none }
                state.failure = .transport(String(describing: failure))
                return .none

            case let .internal(.detailLoaded(.failure(failure))):
                state.isLoading = false
                state.failure = failure
                return .none

            case let .internal(.seasonsLoaded(.success(seasons))):
                state.seasons = seasons
                guard let first = seasons.first else { return .none }
                let preferredID = Self.seasonID(
                    for: state.seriesPlaybackState?.primaryItem,
                    seasons: seasons
                )
                if preferredID != nil {
                    state.didApplyPlaybackSeason = true
                }
                return .send(.view(.seasonSelected(preferredID ?? first.id)))

            case let .internal(.seasonsLoaded(.failure(failure))):
                state.failure = failure
                return .none

            case let .internal(.seriesPlaybackLoaded(playbackState)):
                state.seriesPlaybackState = playbackState
                guard !state.didApplyPlaybackSeason,
                      let preferredID = Self.seasonID(
                          for: playbackState.primaryItem,
                          seasons: state.seasons
                      ) else {
                    return .none
                }
                state.didApplyPlaybackSeason = true
                guard preferredID != state.selectedSeasonID else { return .none }
                return .send(.view(.seasonSelected(preferredID)))

            case let .view(.seasonSelected(seasonID)):
                state.selectedSeasonID = seasonID
                state.isLoadingEpisodes = true
                state.failure = nil
                let locator = state.locator
                return .run { send in
                    do {
                        await send(.internal(.episodesLoaded(
                            seasonID,
                            .success(try await mediaPlatform.episodes(
                                locator,
                                seasonID,
                                PageRequest(number: 1, size: 200)
                            ))
                        )))
                    } catch {
                        await send(.internal(.episodesLoaded(
                            seasonID,
                            .failure(Self.normalize(error))
                        )))
                    }
                }
                .cancellable(id: CancelID.episodes, cancelInFlight: true)

            case let .internal(.episodesLoaded(seasonID, .success(page))):
                guard state.selectedSeasonID == seasonID else { return .none }
                state.isLoadingEpisodes = false
                state.episodes = applyingLocalState(
                    to: page.items,
                    sourceID: state.locator.sourceID,
                    states: state.localStates
                )
                return .none

            case let .internal(.episodesLoaded(seasonID, .failure(failure))):
                guard state.selectedSeasonID == seasonID else { return .none }
                state.isLoadingEpisodes = false
                state.failure = failure
                return .none

            case let .internal(.movieVariantsLoaded(.success(variants))):
                state.isLoadingMovieVariants = false
                state.movieVariants = variants
                return .none

            case let .internal(.movieVariantsLoaded(.failure(failure))):
                state.isLoadingMovieVariants = false
                state.failure = failure
                return .none

            case .view(.toggleFavorite):
                guard let profileID = state.profileID, !state.isUpdatingFavorite else {
                    return .none
                }
                let desired = !state.isFavorite
                state.isUpdatingFavorite = true
                let mediaKey = ProfileMediaKey(locator: state.locator)
                let snapshot = ProfileMediaSnapshot(
                    key: mediaKey,
                    locator: state.locator,
                    title: state.item.title,
                    kind: state.item.kind,
                    artworkURL: state.item.posterURL,
                    metadata: profileMetadata(state),
                    modifiedAt: now,
                    deviceID: profiles.deviceID()
                )
                let favorite = ProfileFavoriteState(
                    profileID: profileID,
                    mediaKey: mediaKey,
                    isFavorite: desired,
                    modifiedAt: now,
                    deviceID: profiles.deviceID()
                )
                return .run { send in
                    do {
                        try await profiles.saveFavorite(favorite, snapshot)
                        await send(.internal(.favoriteSaved(desired, .success(true))))
                    } catch {
                        await send(.internal(.favoriteSaved(
                            desired,
                            .failure(Self.normalize(error))
                        )))
                    }
                }
                .cancellable(id: CancelID.favorite, cancelInFlight: true)

            case let .internal(.favoriteSaved(value, .success)):
                state.isUpdatingFavorite = false
                state.localStates[state.mediaKey, default: ProfileMediaState()].isFavorite = value
                return .none

            case let .internal(.favoriteSaved(_, .failure(failure))):
                state.isUpdatingFavorite = false
                state.failure = failure
                return .none

            case .view(.playPrimary):
                if state.item.kind == .series {
                    guard let target = state.primarySeriesItem else { return .none }
                    return .send(.delegate(.play(
                        locator: MediaLocatorID(
                            sourceID: state.locator.sourceID,
                            providerItemID: target.item.id
                        ),
                        title: target.title,
                        kind: .episode,
                        artworkURL: target.thumbnailURL ?? target.posterURL ?? state.item.posterURL,
                        metadata: profileMetadata(state),
                        startPositionSeconds: target.userState.played
                            ? 0
                            : target.userState.positionSeconds,
                        variantID: nil
                    )))
                }
                return .send(.delegate(.play(
                    locator: state.locator,
                    title: state.item.title,
                    kind: state.item.kind,
                    artworkURL: state.item.posterURL,
                    metadata: profileMetadata(state),
                    startPositionSeconds: state.item.userState.played
                        ? 0
                        : state.item.userState.positionSeconds,
                    variantID: nil
                )))

            case let .view(.movieVariantSelected(variantID)):
                guard state.movieVariants.contains(where: { $0.id == variantID }) else {
                    return .none
                }
                return .send(.delegate(.play(
                    locator: state.locator,
                    title: state.item.title,
                    kind: state.item.kind,
                    artworkURL: state.item.posterURL,
                    metadata: profileMetadata(state),
                    startPositionSeconds: state.item.userState.played
                        ? 0
                        : state.item.userState.positionSeconds,
                    variantID: variantID
                )))

            case let .view(.episodeSelected(episode)):
                let locator = MediaLocatorID(
                    sourceID: state.locator.sourceID,
                    providerItemID: episode.id
                )
                let seasonTitle = state.seasons.first { $0.id == episode.seasonID }?.title
                state.playbackOptions = PlaybackOptionsFeature.State(
                    locator: locator,
                    title: episode.title,
                    subtitle: seasonTitle,
                    episodeNumber: episode.number,
                    kind: .episode,
                    artworkURL: episode.thumbnailURL ?? state.item.posterURL,
                    metadata: profileMetadata(state),
                    startPositionSeconds: episode.userState.played
                        ? 0
                        : episode.userState.positionSeconds
                )
                return .none

            case let .playbackOptions(.presented(.delegate(.play(variantID)))):
                guard let options = state.playbackOptions else { return .none }
                state.playbackOptions = nil
                return .send(.delegate(.play(
                    locator: options.locator,
                    title: options.title,
                    kind: options.kind,
                    artworkURL: options.artworkURL,
                    metadata: options.metadata,
                    startPositionSeconds: options.startPositionSeconds,
                    variantID: variantID
                )))

            case .playbackOptions, .delegate:
                return .none
            }
        }
        .ifLet(\.$playbackOptions, action: \.playbackOptions) {
            PlaybackOptionsFeature()
        }
    }

    private func loadSeasons(_ locator: MediaLocatorID) -> Effect<Action> {
        .run { send in
            do {
                await send(.internal(.seasonsLoaded(.success(
                    try await mediaPlatform.seasons(locator)
                ))))
            } catch {
                await send(.internal(.seasonsLoaded(.failure(Self.normalize(error)))))
            }
        }
    }

    private func loadMovieVariants(_ locator: MediaLocatorID) -> Effect<Action> {
        .run { send in
            do {
                await send(.internal(.movieVariantsLoaded(.success(
                    try await mediaPlatform.playbackVariants(locator)
                ))))
            } catch {
                await send(.internal(.movieVariantsLoaded(.failure(Self.normalize(error)))))
            }
        }
        .cancellable(id: CancelID.movieVariants, cancelInFlight: true)
    }

    private func loadSeriesPlayback(_ locator: MediaLocatorID) -> Effect<Action> {
        .run { send in
            let playbackState = (try? await mediaPlatform.seriesPlayback(locator))
                ?? SeriesPlaybackState(resume: nil, nextUp: nil)
            await send(.internal(.seriesPlaybackLoaded(playbackState)))
        }
    }

    private static func seasonID(
        for item: ContinueWatchingItem?,
        seasons: [Season]
    ) -> String? {
        guard let item else { return nil }
        if let seasonID = item.seasonID,
           seasons.contains(where: { $0.id == seasonID }) {
            return seasonID
        }
        guard let seasonNumber = item.seasonNumber else { return nil }
        return seasons.first { $0.number == seasonNumber }?.id
    }

    private static func normalize(_ error: Error) -> MediaSourceFailure {
        if let failure = error as? MediaSourceFailure { return failure }
        return .transport(String(describing: error))
    }

    private func profileMetadata(_ state: State) -> ProfileMediaMetadataSnapshot? {
        let summary = state.detail?.summary ?? state.initialItem
        let genres = summary.genres.map {
            ProfileGenreSnapshot(
                name: $0.name,
                slug: $0.slug
            )
        }
        let directors = state.detail?.directors.map {
            ProfilePersonSnapshot(providerID: $0.id, name: $0.name)
        } ?? []
        let cast = state.detail?.cast.map {
            ProfilePersonSnapshot(providerID: $0.id, name: $0.name)
        } ?? []
        guard !genres.isEmpty || !directors.isEmpty || !cast.isEmpty else { return nil }
        return ProfileMediaMetadataSnapshot(
            genres: genres,
            directors: directors,
            cast: cast
        )
    }

    private func applyingLocalState(
        to episodes: [Episode],
        sourceID: SourceID,
        states: [ProfileMediaKey: ProfileMediaState]
    ) -> [Episode] {
        episodes.map { episode in
            let locator = MediaLocatorID(sourceID: sourceID, providerItemID: episode.id)
            return episode.replacingUserState(
                states[ProfileMediaKey(locator: locator)]?.userState ?? .empty
            )
        }
    }
}
