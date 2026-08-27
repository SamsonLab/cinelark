import ComposableArchitecture
import Foundation
import CineLarkDomain
import CineLarkProfile
import CineLarkPluginAPI

struct ProfileBootstrap: Equatable, Sendable {
    let profiles: [Profile]
    let manifests: [ProfileManifest]
    let resolution: ProfileBootstrapResolution
    let sources: [PersistedMediaSource]
    let selection: ActiveProfileSelection
    let bindings: [ProfileSourceBinding]

    init(
        profiles: [Profile],
        manifests: [ProfileManifest] = [],
        resolution: ProfileBootstrapResolution,
        sources: [PersistedMediaSource],
        selection: ActiveProfileSelection,
        bindings: [ProfileSourceBinding] = []
    ) {
        self.profiles = profiles
        self.manifests = manifests
        self.resolution = resolution
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
    var resolveProfile: @Sendable (ProfileResolutionChoice) async throws -> ProfileBootstrap
    var saveProfile: @Sendable (Profile) async throws -> Void
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
        resolveProfile: { _ in
            throw ProfileClientFailure.unavailable("Profile repository is not configured")
        },
        saveProfile: { _ in throw ProfileClientFailure.unavailable("Profile repository is not configured") },
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
            resolveProfile: { choice in
                guard let provisional = try await repository.provisionalProfileManifest(
                    clientID: clientID
                ) else {
                    throw ProfileClientFailure.unavailable("Provisional Profile no longer exists")
                }
                let previousSelection = try await repository.activeSelection(
                    deviceID: clientID.description
                )
                let selectedProfileID: ProfileID
                switch choice {
                case let .useCloud(profileID):
                    try await repository.discardProvisionalProfile(
                        clientID: clientID,
                        profileID: provisional.id
                    )
                    selectedProfileID = profileID
                case let .mergeIntoCloud(profileID):
                    let timestamp = now()
                    let stamp = try await repository.nextMutationStamp(
                        clientID: clientID,
                        at: timestamp
                    )
                    _ = try await repository.mergeProvisionalProfile(
                        clientID: clientID,
                        request: ProfileMergeRequest(
                            operationID: uuid(),
                            sourceProfileID: provisional.id,
                            targetProfileID: profileID,
                            mergedAt: timestamp,
                            mutationStamp: stamp
                        )
                    )
                    selectedProfileID = profileID
                case .keepSeparate:
                    try await repository.promoteProvisionalProfile(
                        clientID: clientID,
                        profileID: provisional.id
                    )
                    selectedProfileID = provisional.id
                }
                try await repository.setActiveSelection(
                    ActiveProfileSelection(
                        profileID: selectedProfileID,
                        sourceID: previousSelection.sourceID
                    ),
                    deviceID: clientID.description
                )
                return try await loadBootstrap(
                    repository: repository,
                    clientID: clientID,
                    now: now,
                    uuid: uuid,
                    deviceName: deviceName,
                    platform: platform
                )
            },
            saveProfile: { profile in
                let stamp: MutationStamp
                if let existing = profile.mutationStamp {
                    stamp = existing
                } else {
                    stamp = try await repository.nextMutationStamp(
                        clientID: clientID,
                        at: profile.modifiedAt
                    )
                }
                let stamped = profile.withMutationStamp(stamp)
                if let provisional = try await repository.provisionalProfileManifest(
                    clientID: clientID
                ) {
                    guard provisional.id == profile.id else {
                        throw ProfileClientFailure.unavailable(
                            "Resolve iCloud Profile setup before creating another Profile"
                        )
                    }
                    try await repository.saveProvisionalProfile(stamped, clientID: clientID)
                    return
                }
                try await repository.saveProfile(stamped)
            },
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
        async let cloudManifestValues = repository.profileManifests()
        async let sourceValues = repository.sourceConfigurations()
        async let selectionValue = repository.activeSelection(deviceID: clientID.description)
        var (cloudManifests, sources, selection) = try await (
            cloudManifestValues,
            sourceValues,
            selectionValue
        )
        var provisional = try await repository.provisionalProfileManifest(clientID: clientID)

        let selectedCloudProfileExists = selection.profileID.map { profileID in
            cloudManifests.contains { $0.id == profileID }
        } ?? false
        if provisional == nil && !selectedCloudProfileExists {
            let timestamp = now()
            let stamp = try await repository.nextMutationStamp(
                clientID: clientID,
                at: timestamp
            )
            let profile = Profile(
                id: ProfileID(rawValue: uuid()),
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
        var resolution = ProfileBootstrapResolver.resolve(ProfileBootstrapInput(
            provisionalProfile: provisional,
            cloudProfiles: cloudManifests,
            activeProfileID: selection.profileID,
            cloudAvailability: availability
        ))

        if case let .promoteProvisional(manifest) = resolution {
            try await repository.promoteProvisionalProfile(
                clientID: clientID,
                profileID: manifest.id
            )
            selection = ActiveProfileSelection(
                profileID: manifest.id,
                sourceID: selection.sourceID
            )
            try await repository.setActiveSelection(selection, deviceID: clientID.description)
            cloudManifests = try await repository.profileManifests()
            provisional = nil
            if let promoted = cloudManifests.first(where: { $0.id == manifest.id }) {
                resolution = .synchronize(promoted)
            }
        } else {
            let resolvedProfileID: ProfileID?
            switch resolution {
            case let .localOnly(manifest), let .synchronize(manifest):
                resolvedProfileID = manifest.id
            case .waitingForCloud, .promoteProvisional, .requiresChoice:
                resolvedProfileID = nil
            }
            if let resolvedProfileID, selection.profileID != resolvedProfileID {
                selection = ActiveProfileSelection(
                    profileID: resolvedProfileID,
                    sourceID: selection.sourceID
                )
                try await repository.setActiveSelection(selection, deviceID: clientID.description)
            }
        }

        var manifests = cloudManifests
        if let provisional,
           !manifests.contains(where: { $0.id == provisional.id }) {
            manifests.append(provisional)
        }
        var bindings: [ProfileSourceBinding] = []
        for manifest in manifests {
            bindings.append(contentsOf: try await repository.bindings(profileID: manifest.id))
        }
        let registrationProfileID: ProfileID?
        switch resolution {
        case let .localOnly(manifest), let .synchronize(manifest):
            registrationProfileID = manifest.id
        case let .waitingForCloud(manifest):
            registrationProfileID = manifest?.id
        case let .requiresChoice(provisional, _):
            registrationProfileID = provisional.id
        case let .promoteProvisional(manifest):
            registrationProfileID = manifest.id
        }
        if let registrationProfileID {
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
                profileID: registrationProfileID
            )
        }
        return ProfileBootstrap(
            profiles: manifests.map(\.profile),
            manifests: manifests,
            resolution: resolution,
            sources: sources,
            selection: selection,
            bindings: bindings
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
