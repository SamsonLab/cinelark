import ComposableArchitecture
import Foundation
import CineLarkDomain
import CineLarkProfile
import CineLarkPluginAPI

struct ProfileBootstrap: Equatable, Sendable {
    let profiles: [Profile]
    let sources: [PersistedMediaSource]
    let selection: ActiveProfileSelection
    let bindings: [ProfileSourceBinding]

    init(
        profiles: [Profile],
        sources: [PersistedMediaSource],
        selection: ActiveProfileSelection,
        bindings: [ProfileSourceBinding] = []
    ) {
        self.profiles = profiles
        self.sources = sources
        self.selection = selection
        self.bindings = bindings
    }
}

struct ProfileMediaState: Equatable, Sendable {
    var isFavorite = false
    var playback: UserPlaybackState = .empty

    var userState: UserPlaybackState {
        UserPlaybackState(
            played: playback.played,
            favorite: isFavorite,
            positionSeconds: playback.positionSeconds,
            progress: playback.progress,
            lastPlayedAt: playback.lastPlayedAt
        )
    }
}

struct ProfileStateSnapshot: Equatable, Sendable {
    let states: [ProfileMediaKey: ProfileMediaState]
    let snapshots: [ProfileMediaKey: ProfileMediaSnapshot]
}

enum ProfileClientFailure: Error, Equatable, Sendable {
    case unavailable(String)
}

struct ProfileClient: Sendable {
    var deviceID: @Sendable () -> String
    var load: @Sendable () async throws -> ProfileBootstrap
    var saveProfile: @Sendable (Profile) async throws -> Void
    var setSelection: @Sendable (ActiveProfileSelection) async throws -> Void
    var saveSource: @Sendable (PluginID, SourceConfiguration) async throws -> Void
    var saveBinding: @Sendable (ProfileSourceBinding) async throws -> Void
    var savePlayback: @Sendable (ProfilePlaybackState, ProfileMediaSnapshot?) async throws -> Void
    var saveFavorite: @Sendable (ProfileFavoriteState, ProfileMediaSnapshot?) async throws -> Void
    var state: @Sendable (ProfileID) async throws -> ProfileStateSnapshot
    var enqueueMirror: @Sendable (MirrorQueueEntry) async throws -> Void
    var importRemoteState: @Sendable (RemoteStateImportBatch) async throws -> Bool
    var dueMirrorEntries: @Sendable (Date, Int) async throws -> [MirrorQueueEntry]
    var completeMirrorEntry: @Sendable (UUID) async throws -> Void
    var rescheduleMirrorEntry: @Sendable (UUID, Int, Date) async throws -> Void
    var changes: @Sendable () async -> AsyncStream<ProfileRepositoryChange>
}

extension ProfileClient: DependencyKey {
    static let liveValue = Self(
        deviceID: { "unconfigured-device" },
        load: { throw ProfileClientFailure.unavailable("Profile repository is not configured") },
        saveProfile: { _ in throw ProfileClientFailure.unavailable("Profile repository is not configured") },
        setSelection: { _ in throw ProfileClientFailure.unavailable("Profile repository is not configured") },
        saveSource: { _, _ in throw ProfileClientFailure.unavailable("Profile repository is not configured") },
        saveBinding: { _ in throw ProfileClientFailure.unavailable("Profile repository is not configured") },
        savePlayback: { _, _ in throw ProfileClientFailure.unavailable("Profile repository is not configured") },
        saveFavorite: { _, _ in throw ProfileClientFailure.unavailable("Profile repository is not configured") },
        state: { _ in throw ProfileClientFailure.unavailable("Profile repository is not configured") },
        enqueueMirror: { _ in throw ProfileClientFailure.unavailable("Profile repository is not configured") },
        importRemoteState: { _ in throw ProfileClientFailure.unavailable("Profile repository is not configured") },
        dueMirrorEntries: { _, _ in throw ProfileClientFailure.unavailable("Profile repository is not configured") },
        completeMirrorEntry: { _ in throw ProfileClientFailure.unavailable("Profile repository is not configured") },
        rescheduleMirrorEntry: { _, _, _ in throw ProfileClientFailure.unavailable("Profile repository is not configured") },
        changes: { AsyncStream { $0.finish() } }
    )

    static let testValue = liveValue
}

extension DependencyValues {
    var profiles: ProfileClient {
        get { self[ProfileClient.self] }
        set { self[ProfileClient.self] = newValue }
    }
}

extension ProfileClient {
    static func live(
        repository: any ProfileRepository,
        deviceID: String,
        now: @escaping @Sendable () -> Date = { Date() },
        uuid: @escaping @Sendable () -> UUID = { UUID() }
    ) -> Self {
        Self(
            deviceID: { deviceID },
            load: {
                async let profiles = repository.profiles()
                async let sources = repository.sourceConfigurations()
                async let selection = repository.activeSelection(deviceID: deviceID)
                let values = try await ProfileBootstrap(
                    profiles: profiles,
                    sources: sources,
                    selection: selection
                )
                var bindings: [ProfileSourceBinding] = []
                for profile in values.profiles {
                    bindings.append(contentsOf: try await repository.bindings(profileID: profile.id))
                }
                return ProfileBootstrap(
                    profiles: values.profiles,
                    sources: values.sources,
                    selection: values.selection,
                    bindings: bindings
                )
            },
            saveProfile: { try await repository.saveProfile($0) },
            setSelection: { try await repository.setActiveSelection($0, deviceID: deviceID) },
            saveSource: { try await repository.saveSource(pluginID: $0, configuration: $1) },
            saveBinding: { try await repository.saveBinding($0) },
            savePlayback: { state, snapshot in
                try await repository.savePlayback(state, snapshot: snapshot)
                guard let snapshot else { return }
                try await enqueueMirrorIfEnabled(
                    repository: repository,
                    profileID: state.profileID,
                    snapshot: snapshot,
                    mutation: .playback(state),
                    now: now,
                    uuid: uuid
                )
            },
            saveFavorite: { state, snapshot in
                try await repository.saveFavorite(state, snapshot: snapshot)
                guard let snapshot else { return }
                try await enqueueMirrorIfEnabled(
                    repository: repository,
                    profileID: state.profileID,
                    snapshot: snapshot,
                    mutation: .favorite(state),
                    now: now,
                    uuid: uuid
                )
            },
            state: { profileID in
                async let favoriteValues = repository.favorites(profileID: profileID)
                async let playbackValues = repository.playbackStates(profileID: profileID)
                let (favorites, playback) = try await (favoriteValues, playbackValues)
                var states: [ProfileMediaKey: ProfileMediaState] = [:]
                for value in favorites {
                    states[value.mediaKey, default: ProfileMediaState()].isFavorite = value.isFavorite
                }
                for value in playback {
                    states[value.mediaKey, default: ProfileMediaState()].playback = value.state
                }
                let snapshots = try await repository.mediaSnapshots(keys: Set(states.keys))
                return ProfileStateSnapshot(
                    states: states,
                    snapshots: Dictionary(uniqueKeysWithValues: snapshots.map { ($0.key, $0) })
                )
            },
            enqueueMirror: { try await repository.enqueueMirror($0) },
            importRemoteState: { try await repository.importRemoteState($0) },
            dueMirrorEntries: { try await repository.dueMirrorEntries(at: $0, limit: $1) },
            completeMirrorEntry: { try await repository.completeMirrorEntry(id: $0) },
            rescheduleMirrorEntry: {
                try await repository.rescheduleMirrorEntry(
                    id: $0,
                    attempts: $1,
                    nextAttemptAt: $2
                )
            },
            changes: { await repository.changes() }
        )
    }

    private static func enqueueMirrorIfEnabled(
        repository: any ProfileRepository,
        profileID: ProfileID,
        snapshot: ProfileMediaSnapshot,
        mutation: MirrorMutation,
        now: @Sendable () -> Date,
        uuid: @Sendable () -> UUID
    ) async throws {
        guard let binding = try await repository.bindings(profileID: profileID).first(where: {
            $0.sourceID == snapshot.locator.sourceID && $0.mirrorsRemoteState
        }), let remoteUserID = binding.remoteUserID else { return }
        try await repository.enqueueMirror(MirrorQueueEntry(
            id: uuid(),
            profileID: profileID,
            sourceID: snapshot.locator.sourceID,
            remoteUserID: remoteUserID,
            locator: snapshot.locator,
            mutation: mutation,
            nextAttemptAt: now()
        ))
    }
}
