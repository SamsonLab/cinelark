import ComposableArchitecture
import Foundation
import CineLarkDomain
import CineLarkPluginAPI
import CineLarkProfile

@Reducer
struct MediaDetailFeature {
    @ObservableState
    struct State: Equatable {
        let locator: MediaLocatorID
        let profileID: ProfileID?
        let initialItem: MediaSummary
        var detail: MediaDetail?
        var seasons: [Season] = []
        var selectedSeasonID: String?
        var episodes: [Episode] = []
        var isLoading = false
        var isLoadingEpisodes = false
        var isUpdatingFavorite = false
        var localStates: [ProfileMediaKey: ProfileMediaState] = [:]
        var failure: MediaSourceFailure?

        var mediaKey: ProfileMediaKey { ProfileMediaKey(locator: locator) }
        var localState: ProfileMediaState { localStates[mediaKey] ?? ProfileMediaState() }
        var item: MediaSummary {
            (detail?.summary ?? initialItem).replacingUserState(localState.userState)
        }
        var isFavorite: Bool { localState.isFavorite }
    }

    enum Action: Equatable {
        case view(View)
        case `internal`(Internal)
        case delegate(Delegate)

        enum View: Equatable {
            case appeared
            case seasonSelected(String)
            case toggleFavorite
            case playPrimary
            case episodeSelected(Episode)
        }

        enum Internal: Equatable {
            case detailLoaded(Result<MediaDetail, MediaSourceFailure>)
            case profileStateLoaded(ProfileID, Result<ProfileStateSnapshot, ProfileClientFailure>)
            case seasonsLoaded(Result<[Season], MediaSourceFailure>)
            case episodesLoaded(String, Result<Page<Episode>, MediaSourceFailure>)
            case favoriteSaved(Bool, Result<Bool, MediaSourceFailure>)
        }

        enum Delegate: Equatable {
            case play(
                locator: MediaLocatorID,
                title: String,
                kind: MediaKind,
                artworkURL: URL?,
                metadata: ProfileMediaMetadataSnapshot?,
                startPositionSeconds: Double
            )
        }
    }

    private enum CancelID {
        case load
        case episodes
        case favorite
    }

    @Dependency(\.mediaPlatform) private var mediaPlatform
    @Dependency(\.profiles) private var profiles
    @Dependency(\.date.now) private var now

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
                        do {
                            await send(.internal(.detailLoaded(.success(
                                try await mediaPlatform.detail(locator, item)
                            ))))
                        } catch {
                            await send(.internal(.detailLoaded(.failure(Self.normalize(error)))))
                        }
                    }
                ]
                if item.kind == .series {
                    effects.append(.run { send in
                        do {
                            await send(.internal(.seasonsLoaded(.success(
                                try await mediaPlatform.seasons(locator)
                            ))))
                        } catch {
                            await send(.internal(.seasonsLoaded(.failure(Self.normalize(error)))))
                        }
                    })
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
                return .none

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
                return .send(.view(.seasonSelected(first.id)))

            case let .internal(.seasonsLoaded(.failure(failure))):
                state.failure = failure
                return .none

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
                if state.item.kind == .series, let episode = state.episodes.first {
                    return .send(.view(.episodeSelected(episode)))
                }
                return .send(.delegate(.play(
                    locator: state.locator,
                    title: state.item.title,
                    kind: state.item.kind,
                    artworkURL: state.item.posterURL,
                    metadata: profileMetadata(state),
                    startPositionSeconds: state.item.userState.played
                        ? 0
                        : state.item.userState.positionSeconds
                )))

            case let .view(.episodeSelected(episode)):
                return .send(.delegate(.play(
                    locator: MediaLocatorID(
                        sourceID: state.locator.sourceID,
                        providerItemID: episode.id
                    ),
                    title: episode.title,
                    kind: .series,
                    artworkURL: episode.thumbnailURL ?? state.item.posterURL,
                    metadata: profileMetadata(state),
                    startPositionSeconds: episode.userState.played
                        ? 0
                        : episode.userState.positionSeconds
                )))

            case .delegate:
                return .none
            }
        }
    }

    private static func normalize(_ error: Error) -> MediaSourceFailure {
        if let failure = error as? MediaSourceFailure { return failure }
        return .transport(String(describing: error))
    }

    private func profileMetadata(_ state: State) -> ProfileMediaMetadataSnapshot? {
        let summary = state.detail?.summary ?? state.initialItem
        let genres = summary.genres.map {
            ProfileGenreSnapshot(
                providerID: String($0.id),
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
