import ComposableArchitecture
import Foundation
import CineLarkProfile
import CineLarkPluginAPI
import CineLarkDomain

@Reducer
struct ProfileFeature {
    enum SelectionSaveResult: Equatable {
        case success
        case failure(ProfileClientFailure)
    }

    struct MirrorPassOutcome: Equatable {
        let shouldContinue: Bool
        let retryDelaySeconds: Int?
        let terminalFailure: ProfileClientFailure?

        init(
            shouldContinue: Bool,
            retryDelaySeconds: Int?,
            terminalFailure: ProfileClientFailure? = nil
        ) {
            self.shouldContinue = shouldContinue
            self.retryDelaySeconds = retryDelaySeconds
            self.terminalFailure = terminalFailure
        }
    }

    @ObservableState
    struct State: Equatable {
        var profile: Profile?
        var manifest: ProfileManifest?
        var sources: [PersistedMediaSource] = []
        var bindings: [ProfileSourceBinding] = []
        var activeProfileID: ProfileID?
        var activeSourceID: SourceID?
        var cloudSyncStatus: ProfileCloudSyncStatus = .checking
        var isLoading = false
        var isRefreshingCloudSyncStatus = false
        var needsReloadAfterCurrentLoad = false
        var isImportingRemoteState = false
        var isProcessingMirrorQueue = false
        var lastImportApplied: Bool?
        var failure: ProfileClientFailure?

        var activeBinding: ProfileSourceBinding? {
            guard let activeProfileID, let activeSourceID else { return nil }
            return bindings.first {
                $0.profileID == activeProfileID && $0.sourceID == activeSourceID
            }
        }
    }

    enum Action: Equatable {
        case view(View)
        case `internal`(Internal)
        case delegate(Delegate)

        enum View: Equatable {
            case appeared
            case reload
            case refreshCloudSyncStatus
            case selectSource(SourceID?)
            case setRemoteMirrorEnabled(Bool)
            case importRemoteState
            case processMirrorQueue
        }

        enum Internal: Equatable {
            case loaded(Result<ProfileBootstrap, ProfileClientFailure>)
            case cloudSyncStatusLoaded(ProfileCloudSyncStatus)
            case selectionSaved(
                ActiveProfileSelection,
                SelectionSaveResult
            )
            case commitSelection(ActiveProfileSelection)
            case repositoryChanged(ProfileRepositoryChange)
            case bindingSaved(Result<ProfileSourceBinding, ProfileClientFailure>)
            case remoteStateImported(Result<Bool, ProfileClientFailure>)
            case mirrorPassFinished(Result<MirrorPassOutcome, ProfileClientFailure>)
        }

        enum Delegate: Equatable {
            case sourceSelectionRequested(SourceID?)
            case selectionChanged(ActiveProfileSelection)
        }
    }

    private enum CancelID {
        case load
        case changes
        case cloudSyncStatus
        case selection
        case importRemoteState
        case mirrorQueue
    }

    @Dependency(\.profiles) private var profiles
    @Dependency(\.date.now) private var now
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.mediaPlatform) private var mediaPlatform

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.appeared):
                guard !state.isLoading else { return .none }
                return .merge(
                    load(&state),
                    refreshCloudSyncStatus(&state),
                    subscribe(),
                    .send(.view(.processMirrorQueue))
                )

            case .view(.reload):
                return .merge(
                    load(&state),
                    refreshCloudSyncStatus(&state)
                )

            case .view(.refreshCloudSyncStatus):
                return refreshCloudSyncStatus(&state)

            case let .view(.selectSource(sourceID)):
                return .send(.delegate(.sourceSelectionRequested(sourceID)))

            case let .view(.setRemoteMirrorEnabled(enabled)):
                guard
                    let profileID = state.activeProfileID,
                    let sourceID = state.activeSourceID,
                    let source = state.sources.first(where: { $0.id == sourceID }),
                    let remoteUserID = source.configuration.remoteUserID
                else { return .none }
                let binding = ProfileSourceBinding(
                    profileID: profileID,
                    sourceID: sourceID,
                    remoteUserID: remoteUserID,
                    mirrorsRemoteState: enabled
                )
                return .run { send in
                    do {
                        try await profiles.saveBinding(binding)
                        await send(.internal(.bindingSaved(.success(binding))))
                    } catch {
                        await send(.internal(.bindingSaved(.failure(Self.normalize(error)))))
                    }
                }

            case .view(.importRemoteState):
                guard
                    !state.isImportingRemoteState,
                    let profileID = state.activeProfileID,
                    let sourceID = state.activeSourceID
                else { return .none }
                state.isImportingRemoteState = true
                state.lastImportApplied = nil
                state.failure = nil
                let timestamp = now
                let deviceID = profiles.deviceID()
                return importRemoteState(
                    profileID: profileID,
                    sourceID: sourceID,
                    timestamp: timestamp,
                    deviceID: deviceID
                )

            case .view(.processMirrorQueue):
                guard !state.isProcessingMirrorQueue else { return .none }
                state.isProcessingMirrorQueue = true
                return mirrorPass()

            case let .internal(.loaded(.success(bootstrap))):
                state.isLoading = false
                state.failure = nil
                state.profile = bootstrap.profile
                state.manifest = bootstrap.manifest
                state.sources = bootstrap.sources
                state.bindings = bootstrap.bindings
                state.activeProfileID = bootstrap.selection.profileID
                state.activeSourceID = bootstrap.selection.sourceID
                if state.needsReloadAfterCurrentLoad {
                    state.needsReloadAfterCurrentLoad = false
                    return load(&state)
                }
                return .none

            case let .internal(.loaded(.failure(failure))):
                state.isLoading = false
                state.failure = failure
                if state.needsReloadAfterCurrentLoad {
                    state.needsReloadAfterCurrentLoad = false
                    return load(&state)
                }
                return .none

            case let .internal(.cloudSyncStatusLoaded(status)):
                state.isRefreshingCloudSyncStatus = false
                state.cloudSyncStatus = status
                return .none

            case let .internal(.selectionSaved(selection, .success)):
                state.activeProfileID = selection.profileID
                state.activeSourceID = selection.sourceID
                return .send(.delegate(.selectionChanged(selection)))

            case let .internal(.selectionSaved(_, .failure(failure))):
                state.failure = failure
                return .none

            case let .internal(.commitSelection(selection)):
                return persistSelection(selection)

            case .internal(.repositoryChanged(.mirrorQueue)):
                if state.isLoading {
                    state.needsReloadAfterCurrentLoad = true
                    return .send(.view(.processMirrorQueue))
                }
                return .merge(
                    .send(.view(.reload)),
                    .send(.view(.processMirrorQueue))
                )

            case .internal(.repositoryChanged(.cloudSyncStatus)):
                return refreshCloudSyncStatus(&state)

            case .internal(.repositoryChanged(.mediaMetadata)):
                return .none

            case .internal(.repositoryChanged):
                if state.isLoading {
                    state.needsReloadAfterCurrentLoad = true
                    return .none
                }
                return .send(.view(.reload))

            case let .internal(.bindingSaved(.success(binding))):
                state.failure = nil
                state.bindings.removeAll {
                    $0.profileID == binding.profileID && $0.sourceID == binding.sourceID
                }
                state.bindings.append(binding)
                return binding.mirrorsRemoteState
                    ? .send(.view(.processMirrorQueue))
                    : .none

            case let .internal(.bindingSaved(.failure(failure))):
                state.failure = failure
                return .none

            case let .internal(.remoteStateImported(.success(applied))):
                state.isImportingRemoteState = false
                state.lastImportApplied = applied
                return .none

            case let .internal(.remoteStateImported(.failure(failure))):
                state.isImportingRemoteState = false
                state.failure = failure
                return .none

            case let .internal(.mirrorPassFinished(.success(outcome))):
                state.isProcessingMirrorQueue = false
                if let failure = outcome.terminalFailure {
                    state.failure = failure
                }
                if outcome.shouldContinue {
                    return .send(.view(.processMirrorQueue))
                }
                guard let seconds = outcome.retryDelaySeconds else { return .none }
                return .run { send in
                    try await clock.sleep(for: .seconds(seconds))
                    await send(.view(.processMirrorQueue))
                }
                .cancellable(id: CancelID.mirrorQueue, cancelInFlight: true)

            case let .internal(.mirrorPassFinished(.failure(failure))):
                state.isProcessingMirrorQueue = false
                state.failure = failure
                return .none

            case .delegate:
                return .none
            }
        }
    }

    func persistSelection(_ selection: ActiveProfileSelection) -> Effect<Action> {
        .run { send in
            do {
                try await profiles.setSelection(selection)
                await send(.internal(.selectionSaved(selection, .success)))
            } catch {
                await send(
                    .internal(
                        .selectionSaved(
                            selection,
                            .failure(Self.normalize(error))
                        )
                    )
                )
            }
        }
        .cancellable(id: CancelID.selection, cancelInFlight: true)
    }

    private func load(_ state: inout State) -> Effect<Action> {
        state.isLoading = true
        state.failure = nil
        return .run { send in
            do {
                await send(.internal(.loaded(.success(try await profiles.load()))))
            } catch {
                await send(.internal(.loaded(.failure(Self.normalize(error)))))
            }
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }

    private func subscribe() -> Effect<Action> {
        .run { send in
            for await change in await profiles.changes() {
                await send(.internal(.repositoryChanged(change)))
            }
        }
        .cancellable(id: CancelID.changes, cancelInFlight: true)
    }

    private func refreshCloudSyncStatus(_ state: inout State) -> Effect<Action> {
        state.isRefreshingCloudSyncStatus = true
        return .run { send in
            await send(.internal(.cloudSyncStatusLoaded(
                await profiles.cloudSyncStatus()
            )))
        }
        .cancellable(id: CancelID.cloudSyncStatus, cancelInFlight: true)
    }

    private func importRemoteState(
        profileID: ProfileID,
        sourceID: SourceID,
        timestamp: Date,
        deviceID: String
    ) -> Effect<Action> {
        .run { send in
            do {
                let remote = try await mediaPlatform.importRemoteState(sourceID)
                let snapshots = remote.items.map {
                    ProfileMediaSnapshot(
                        key: ProfileMediaKey(locator: $0.locator),
                        locator: $0.locator,
                        title: $0.summary.title,
                        kind: $0.summary.kind,
                        artworkURL: $0.summary.posterURL,
                        metadata: Self.profileMetadata($0.summary),
                        modifiedAt: timestamp,
                        deviceID: deviceID
                    )
                }
                let favorites = remote.items.compactMap { item -> ProfileFavoriteState? in
                    guard let isFavorite = item.isFavorite else { return nil }
                    return ProfileFavoriteState(
                        profileID: profileID,
                        mediaKey: ProfileMediaKey(locator: item.locator),
                        isFavorite: isFavorite,
                        modifiedAt: timestamp,
                        deviceID: deviceID
                    )
                }
                let playback = remote.items.compactMap { item -> ProfilePlaybackState? in
                    guard let playback = item.playback else { return nil }
                    return ProfilePlaybackState(
                        profileID: profileID,
                        mediaKey: ProfileMediaKey(locator: item.locator),
                        state: playback,
                        modifiedAt: timestamp,
                        deviceID: deviceID
                    )
                }
                let applied = try await profiles.importRemoteState(RemoteStateImportBatch(
                    marker: remote.marker,
                    profileID: profileID,
                    sourceID: sourceID,
                    remoteUserID: remote.remoteUserID,
                    snapshots: snapshots,
                    favorites: favorites,
                    playback: playback
                ))
                await send(.internal(.remoteStateImported(.success(applied))))
            } catch is CancellationError {
                return
            } catch {
                await send(.internal(.remoteStateImported(.failure(Self.normalize(error)))))
            }
        }
        .cancellable(id: CancelID.importRemoteState, cancelInFlight: true)
    }

    private static func profileMetadata(
        _ summary: MediaSummary
    ) -> ProfileMediaMetadataSnapshot? {
        let genres = summary.genres.map {
            ProfileGenreSnapshot(
                name: $0.name,
                slug: $0.slug
            )
        }
        return genres.isEmpty ? nil : ProfileMediaMetadataSnapshot(genres: genres)
    }

    private func mirrorPass() -> Effect<Action> {
        let timestamp = now
        return .run { send in
            do {
                let limit = 20
                let entries = try await profiles.dueMirrorEntries(timestamp, limit)
                var retryDelay: Int?
                var terminalFailure: ProfileClientFailure?
                for entry in entries {
                    guard let locator = entry.locator else {
                        try await profiles.completeMirrorEntry(entry.id)
                        continue
                    }
                    let mutation: RemoteStateMutation
                    switch entry.mutation {
                    case let .favorite(state):
                        mutation = .favorite(locator, state.isFavorite)
                    case let .playback(state):
                        mutation = .playback(locator, state.state)
                    }
                    do {
                        try await mediaPlatform.mirrorRemoteState(
                            entry.sourceID,
                            entry.remoteUserID,
                            mutation
                        )
                        try await profiles.completeMirrorEntry(entry.id)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch let failure as MediaSourceFailure {
                        switch failure.retryDecision {
                        case let .retry(retryAfterSeconds):
                            let attempts = entry.attempts + 1
                            let exponentialDelay = min(300, 1 << min(attempts, 8))
                            let delay = max(1, retryAfterSeconds ?? exponentialDelay)
                            try await profiles.rescheduleMirrorEntry(
                                entry.id,
                                attempts,
                                timestamp.addingTimeInterval(TimeInterval(delay))
                            )
                            retryDelay = min(retryDelay ?? delay, delay)
                        case .stop:
                            try await profiles.completeMirrorEntry(entry.id)
                            terminalFailure = terminalFailure ?? Self.mirrorFailure(failure)
                        }
                    } catch {
                        let attempts = entry.attempts + 1
                        let delay = min(300, 1 << min(attempts, 8))
                        try await profiles.rescheduleMirrorEntry(
                            entry.id,
                            attempts,
                            timestamp.addingTimeInterval(TimeInterval(delay))
                        )
                        retryDelay = min(retryDelay ?? delay, delay)
                    }
                }
                await send(.internal(.mirrorPassFinished(.success(MirrorPassOutcome(
                    shouldContinue: entries.count == limit && retryDelay == nil,
                    retryDelaySeconds: retryDelay,
                    terminalFailure: terminalFailure
                )))))
            } catch is CancellationError {
                return
            } catch {
                await send(.internal(.mirrorPassFinished(.failure(Self.normalize(error)))))
            }
        }
        .cancellable(id: CancelID.mirrorQueue, cancelInFlight: true)
    }

    private static func normalize(_ error: Error) -> ProfileClientFailure {
        if let failure = error as? ProfileClientFailure { return failure }
        return .unavailable(String(describing: error))
    }

    private static func mirrorFailure(_ failure: MediaSourceFailure) -> ProfileClientFailure {
        switch failure {
        case .unauthorized:
            return .unavailable(
                "The media source needs authentication before mirroring can continue."
            )
        case .invalidResponse, .requestRejected, .unsupported:
            return .unavailable("The media source rejected a mirrored state update.")
        case .rateLimited, .transport, .unavailable:
            return .unavailable("The media source is temporarily unavailable.")
        }
    }
}
