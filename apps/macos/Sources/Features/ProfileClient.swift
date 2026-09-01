import ComposableArchitecture
import Foundation
import CineLarkDomain
import CineLarkProfile
import CineLarkPluginAPI

struct ProfileBootstrap: Equatable, Sendable {
    let profile: Profile
    let manifest: ProfileManifest
    let sources: [PersistedMediaSource]
    let selection: ActiveProfileSelection
    let bindings: [ProfileSourceBinding]

    init(
        profile: Profile,
        manifest: ProfileManifest,
        sources: [PersistedMediaSource],
        selection: ActiveProfileSelection,
        bindings: [ProfileSourceBinding] = []
    ) {
        self.profile = profile
        self.manifest = manifest
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
    var clientID: @Sendable () -> ClientID
    var load: @Sendable () async throws -> ProfileBootstrap
    var cloudSyncStatus: @Sendable () async -> ProfileCloudSyncStatus
    var setSelection: @Sendable (ActiveProfileSelection) async throws -> Void
    var saveSource: @Sendable (PluginID, SourceConfiguration) async throws -> Void
    var saveBinding: @Sendable (ProfileSourceBinding) async throws -> Void
    var savePlayback: @Sendable (ProfilePlaybackWrite) async throws -> Void
    var saveFavorite: @Sendable (ProfileFavoriteState, ProfileMediaSnapshot?) async throws -> Void
    var state: @Sendable (ProfileID) async throws -> ProfileStateSnapshot
    var enqueueMirror: @Sendable (MirrorQueueEntry) async throws -> Void
    var importRemoteState: @Sendable (RemoteStateImportBatch) async throws -> Bool
    var dueMirrorEntries: @Sendable (Date, Int) async throws -> [MirrorQueueEntry]
    var completeMirrorEntry: @Sendable (UUID) async throws -> Void
    var rescheduleMirrorEntry: @Sendable (UUID, Int, Date) async throws -> Void
    var changes: @Sendable () async -> AsyncStream<ProfileRepositoryChange>

    func deviceID() -> String {
        clientID().description
    }

    func deviceRecordID() -> DeviceRecordID {
        DeviceRecordID(clientID: clientID())
    }
}

extension ProfileClient: DependencyKey {
    static let liveValue = Self(
        clientID: {
            ClientID(
                rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            )
        },
        load: { throw ProfileClientFailure.unavailable("Profile repository is not configured") },
        cloudSyncStatus: { .localOnly },
        setSelection: { _ in throw ProfileClientFailure.unavailable("Profile repository is not configured") },
        saveSource: { _, _ in throw ProfileClientFailure.unavailable("Profile repository is not configured") },
        saveBinding: { _ in throw ProfileClientFailure.unavailable("Profile repository is not configured") },
        savePlayback: { _ in throw ProfileClientFailure.unavailable("Profile repository is not configured") },
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
        clientID: ClientID,
        now: @escaping @Sendable () -> Date = { Date() },
        uuid: @escaping @Sendable () -> UUID = { UUID() },
        deviceName: @escaping @Sendable () -> String = {
            Host.current().localizedName ?? "Mac"
        },
        platform: @escaping @Sendable () -> String = {
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        }
    ) -> Self {
        Self(
            clientID: { clientID },
            load: {
                try await loadBootstrap(
                    repository: repository,
                    clientID: clientID,
                    now: now,
                    uuid: uuid,
                    deviceName: deviceName,
                    platform: platform
                )
            },
            cloudSyncStatus: { await repository.cloudSyncStatus() },
            setSelection: {
                try await repository.setActiveSelection($0, deviceID: clientID.description)
            },
            saveSource: { try await repository.saveSource(pluginID: $0, configuration: $1) },
            saveBinding: { try await repository.saveBinding($0) },
            savePlayback: { write in
                let state = write.state
                let stamp: MutationStamp
                if let existing = state.mutationStamp {
                    stamp = existing
                } else {
                    stamp = try await repository.nextMutationStamp(
                        clientID: clientID,
                        at: state.modifiedAt
                    )
                }
                let stampedState = state.withMutationStamp(stamp)
                let stampedSnapshot = write.snapshot?.withMutationStamp(stamp)
                let stampedSession = write.session?.withMutationStamp(stamp)
                let stampedEvent = write.event?.withMutationStamp(stamp)
                let currentDevice = (write.deviceRecord ?? DeviceRecord(
                    id: DeviceRecordID(clientID: clientID),
                    clientID: clientID,
                    displayName: deviceName(),
                    platform: platform(),
                    lastSeenAt: state.modifiedAt
                )).withMutationStamp(stamp)
                try await repository.savePlayback(ProfilePlaybackWrite(
                    state: stampedState,
                    snapshot: stampedSnapshot,
                    session: stampedSession,
                    event: stampedEvent,
                    deviceRecord: currentDevice
                ))
                guard let stampedSnapshot else { return }
                try await enqueueMirrorIfEnabled(
                    repository: repository,
                    profileID: stampedState.profileID,
                    snapshot: stampedSnapshot,
                    mutation: .playback(stampedState),
                    now: now,
                    uuid: uuid
                )
            },
            saveFavorite: { state, snapshot in
                let stamp: MutationStamp
                if let existing = state.mutationStamp {
                    stamp = existing
                } else {
                    stamp = try await repository.nextMutationStamp(
                        clientID: clientID,
                        at: state.modifiedAt
                    )
                }
                let stampedState = state.withMutationStamp(stamp)
                let stampedSnapshot = snapshot?.withMutationStamp(stamp)
                try await repository.saveFavorite(stampedState, snapshot: stampedSnapshot)
                guard let stampedSnapshot else { return }
                try await enqueueMirrorIfEnabled(
                    repository: repository,
                    profileID: stampedState.profileID,
                    snapshot: stampedSnapshot,
                    mutation: .favorite(stampedState),
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
            importRemoteState: { batch in
                try await repository.importRemoteState(
                    try await stampImportBatch(
                        batch,
                        repository: repository,
                        clientID: clientID
                    )
                )
            },
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

    private static func loadBootstrap(
        repository: any ProfileRepository,
        clientID: ClientID,
        now: @Sendable () -> Date,
        uuid: @Sendable () -> UUID,
        deviceName: @Sendable () -> String,
        platform: @Sendable () -> String
    ) async throws -> ProfileBootstrap {
        async let sourceValues = repository.sourceConfigurations()
        async let selectionValue = repository.activeSelection(deviceID: clientID.description)
        var cloudManifests = try await repository.profileManifests()
        let (sources, previousSelection) = try await (sourceValues, selectionValue)
        var selection = previousSelection
        var provisional = try await repository.provisionalProfileManifest(clientID: clientID)

        if provisional == nil && !cloudManifests.contains(where: { $0.id == .personal }) {
            let timestamp = now()
            let stamp = try await repository.nextMutationStamp(
                clientID: clientID,
                at: timestamp
            )
            let profile = Profile(
                id: .personal,
                name: "Personal",
                createdAt: timestamp,
                modifiedAt: timestamp,
                deviceID: clientID.description,
                mutationStamp: stamp
            )
            try await repository.saveProvisionalProfile(profile, clientID: clientID)
            provisional = try await repository.provisionalProfileManifest(clientID: clientID)
        }

        let availability = await repository.cloudProfileAvailability()
        if availability == .available {
            (cloudManifests, provisional) = try await consolidatePersonalProfile(
                repository: repository,
                clientID: clientID,
                cloudManifests: cloudManifests,
                provisional: provisional,
                now: now,
                uuid: uuid
            )
        }

        let cloudProfile = cloudManifests.first(where: { $0.id == .personal })
            ?? cloudManifests.first
        let manifest: ProfileManifest
        switch availability {
        case .available:
            guard let cloudProfile = cloudManifests.first(where: { $0.id == .personal }) else {
                throw ProfileClientFailure.unavailable("Personal Profile is unavailable")
            }
            manifest = cloudProfile
        case .pendingInitialImport:
            guard let local = provisional ?? cloudProfile else {
                throw ProfileClientFailure.unavailable("Personal Profile is unavailable")
            }
            manifest = local
        case .unavailable:
            guard let local = provisional ?? cloudProfile else {
                throw ProfileClientFailure.unavailable("Personal Profile is unavailable")
            }
            manifest = local
        }

        selection = ActiveProfileSelection(
            profileID: manifest.id,
            sourceID: selection.sourceID
        )
        if selection != previousSelection {
            try await repository.setActiveSelection(selection, deviceID: clientID.description)
        }
        let bindings = try await repository.bindings(profileID: manifest.id)
        let timestamp = now()
        let stamp = try await repository.nextMutationStamp(
            clientID: clientID,
            at: timestamp
        )
        try await repository.saveDeviceRecord(
            DeviceRecord(
                id: DeviceRecordID(clientID: clientID),
                clientID: clientID,
                displayName: deviceName(),
                platform: platform(),
                lastSeenAt: timestamp,
                mutationStamp: stamp
            ),
            profileID: manifest.id
        )
        return ProfileBootstrap(
            profile: manifest.profile,
            manifest: manifest,
            sources: sources,
            selection: selection,
            bindings: bindings
        )
    }

    private static func consolidatePersonalProfile(
        repository: any ProfileRepository,
        clientID: ClientID,
        cloudManifests: [ProfileManifest],
        provisional: ProfileManifest?,
        now: @Sendable () -> Date,
        uuid: @Sendable () -> UUID
    ) async throws -> ([ProfileManifest], ProfileManifest?) {
        var cloudManifests = cloudManifests
        var provisional = provisional
        if !cloudManifests.contains(where: { $0.id == .personal }) {
            if provisional?.id == .personal {
                try await repository.promoteProvisionalProfile(
                    clientID: clientID,
                    profileID: .personal
                )
                provisional = nil
            } else {
                let timestamp = now()
                let stamp = try await repository.nextMutationStamp(
                    clientID: clientID,
                    at: timestamp
                )
                try await repository.saveProfile(Profile(
                    id: .personal,
                    name: "Personal",
                    createdAt: cloudManifests.map(\.profile.createdAt).min() ?? timestamp,
                    modifiedAt: timestamp,
                    deviceID: clientID.description,
                    mutationStamp: stamp
                ))
            }
            cloudManifests = try await repository.profileManifests()
        }

        for legacy in cloudManifests where legacy.id != .personal {
            let timestamp = now()
            let stamp = try await repository.nextMutationStamp(
                clientID: clientID,
                at: timestamp
            )
            _ = try await repository.mergeProfiles(ProfileMergeRequest(
                operationID: uuid(),
                sourceProfileID: legacy.id,
                targetProfileID: .personal,
                mergedAt: timestamp,
                mutationStamp: stamp
            ))
        }

        if let provisionalManifest = provisional {
            if provisionalManifest.id == .personal {
                try await repository.promoteProvisionalProfile(
                    clientID: clientID,
                    profileID: .personal
                )
            } else {
                let timestamp = now()
                let stamp = try await repository.nextMutationStamp(
                    clientID: clientID,
                    at: timestamp
                )
                _ = try await repository.mergeProvisionalProfile(
                    clientID: clientID,
                    request: ProfileMergeRequest(
                        operationID: uuid(),
                        sourceProfileID: provisionalManifest.id,
                        targetProfileID: .personal,
                        mergedAt: timestamp,
                        mutationStamp: stamp
                    )
                )
            }
            provisional = nil
        }
        return (try await repository.profileManifests(), provisional)
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

    private static func stampImportBatch(
        _ batch: RemoteStateImportBatch,
        repository: any ProfileRepository,
        clientID: ClientID
    ) async throws -> RemoteStateImportBatch {
        var snapshots: [ProfileMediaSnapshot] = []
        for snapshot in batch.snapshots {
            let stamp: MutationStamp
            if let existing = snapshot.mutationStamp {
                stamp = existing
            } else {
                stamp = try await repository.nextMutationStamp(
                    clientID: clientID,
                    at: snapshot.modifiedAt
                )
            }
            snapshots.append(snapshot.withMutationStamp(stamp))
        }
        var favorites: [ProfileFavoriteState] = []
        for favorite in batch.favorites {
            let stamp: MutationStamp
            if let existing = favorite.mutationStamp {
                stamp = existing
            } else {
                stamp = try await repository.nextMutationStamp(
                    clientID: clientID,
                    at: favorite.modifiedAt
                )
            }
            favorites.append(favorite.withMutationStamp(stamp))
        }
        var playback: [ProfilePlaybackState] = []
        for state in batch.playback {
            let stamp: MutationStamp
            if let existing = state.mutationStamp {
                stamp = existing
            } else {
                stamp = try await repository.nextMutationStamp(
                    clientID: clientID,
                    at: state.modifiedAt
                )
            }
            playback.append(state.withMutationStamp(stamp))
        }
        return RemoteStateImportBatch(
            marker: batch.marker,
            profileID: batch.profileID,
            sourceID: batch.sourceID,
            remoteUserID: batch.remoteUserID,
            snapshots: snapshots,
            favorites: favorites,
            playback: playback
        )
    }
}
