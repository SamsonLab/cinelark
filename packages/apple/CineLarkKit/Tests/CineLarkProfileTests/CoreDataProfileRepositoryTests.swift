import Foundation
import Testing
import CineLarkDomain
import CineLarkPluginAPI
@testable import CineLarkProfile

@Test func legacyMediaSnapshotDecodesWithoutInsightMetadata() throws {
    let snapshot = ProfileMediaSnapshot(
        key: ProfileMediaKey(rawValue: "legacy:movie"),
        locator: MediaLocatorID(
            sourceID: SourceID(rawValue: UUID()),
            providerItemID: "movie"
        ),
        title: "Legacy Movie",
        kind: .movie,
        artworkURL: nil,
        modifiedAt: Date(timeIntervalSince1970: 100),
        deviceID: "legacy-device"
    )
    let data = try JSONEncoder().encode(snapshot)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["metadata"] == nil)

    let decoded = try JSONDecoder().decode(ProfileMediaSnapshot.self, from: data)
    #expect(decoded == snapshot)
    #expect(decoded.metadata == nil)
}

@Test func mediaStateIsIsolatedBetweenProfiles() async throws {
    let repository = try CoreDataProfileRepository(
        configuration: .init(inMemory: true)
    )
    let first = ProfileID(rawValue: UUID())
    let second = ProfileID(rawValue: UUID())
    let mediaKey = ProfileMediaKey(rawValue: "locator:shared")
    let timestamp = Date(timeIntervalSince1970: 100)

    try await repository.saveFavorite(
        ProfileFavoriteState(
            profileID: first,
            mediaKey: mediaKey,
            isFavorite: true,
            modifiedAt: timestamp,
            deviceID: "device"
        ),
        snapshot: nil
    )
    try await repository.savePlayback(ProfilePlaybackWrite(
        state: ProfilePlaybackState(
            profileID: second,
            mediaKey: mediaKey,
            state: UserPlaybackState(
                played: false,
                positionSeconds: 50,
                progress: 0.5
            ),
            modifiedAt: timestamp,
            deviceID: "device"
        ),
        snapshot: nil,
        session: nil,
        event: nil,
        deviceRecord: nil
    ))

    #expect(try await repository.favorite(profileID: first, mediaKey: mediaKey)?.isFavorite == true)
    #expect(try await repository.favorite(profileID: second, mediaKey: mediaKey) == nil)
    #expect(try await repository.playback(profileID: first, mediaKey: mediaKey) == nil)
    #expect(try await repository.playback(profileID: second, mediaKey: mediaKey)?.state.positionSeconds == 50)
}

@Test func partialSnapshotMetadataRetainsExistingDimensions() async throws {
    let repository = try CoreDataProfileRepository(configuration: .init(inMemory: true))
    let profileID = ProfileID(rawValue: UUID())
    let sourceID = SourceID(rawValue: UUID())
    let locator = MediaLocatorID(sourceID: sourceID, providerItemID: "movie-1")
    let mediaKey = ProfileMediaKey(locator: locator)
    let firstDate = Date(timeIntervalSince1970: 100)
    let secondDate = Date(timeIntervalSince1970: 200)
    let firstSnapshot = ProfileMediaSnapshot(
        key: mediaKey,
        locator: locator,
        title: "Synthetic Movie",
        kind: .movie,
        artworkURL: nil,
        metadata: ProfileMediaMetadataSnapshot(
            genres: [ProfileGenreSnapshot(name: "Drama", slug: "drama")],
            directors: [ProfilePersonSnapshot(providerID: "director-1", name: "Director")],
            cast: [ProfilePersonSnapshot(providerID: "actor-1", name: "Actor")]
        ),
        modifiedAt: firstDate,
        deviceID: "device-a"
    )
    try await repository.saveFavorite(
        ProfileFavoriteState(
            profileID: profileID,
            mediaKey: mediaKey,
            isFavorite: true,
            modifiedAt: firstDate,
            deviceID: "device-a"
        ),
        snapshot: firstSnapshot
    )
    let importedSnapshot = ProfileMediaSnapshot(
        key: mediaKey,
        locator: locator,
        title: "Synthetic Movie",
        kind: .movie,
        artworkURL: nil,
        metadata: ProfileMediaMetadataSnapshot(
            genres: [ProfileGenreSnapshot(name: "Science Fiction", slug: "science-fiction")]
        ),
        modifiedAt: secondDate,
        deviceID: "device-b"
    )
    try await repository.saveFavorite(
        ProfileFavoriteState(
            profileID: profileID,
            mediaKey: mediaKey,
            isFavorite: true,
            modifiedAt: secondDate,
            deviceID: "device-b"
        ),
        snapshot: importedSnapshot
    )

    let stored = try #require(
        try await repository.mediaSnapshots(keys: [mediaKey]).first
    )
    #expect(stored.metadata?.genres.map(\.name) == ["Science Fiction"])
    #expect(stored.metadata?.directors.map(\.name) == ["Director"])
    #expect(stored.metadata?.cast.map(\.name) == ["Actor"])
}

@Test func directSnapshotEnrichmentUsesVersionOrderingAndPreservesDimensions() async throws {
    let repository = try CoreDataProfileRepository(configuration: .init(inMemory: true))
    let profileID = ProfileID(rawValue: UUID())
    let clientID = ClientID(rawValue: UUID())
    let sourceID = SourceID(rawValue: UUID())
    let locator = MediaLocatorID(sourceID: sourceID, providerItemID: "movie-enrichment")
    let mediaKey = ProfileMediaKey(locator: locator)
    let firstDate = Date(timeIntervalSince1970: 100)
    let secondDate = Date(timeIntervalSince1970: 200)
    let firstStamp = MutationStamp(date: firstDate, clientID: clientID.description)
    let secondStamp = MutationStamp(date: secondDate, clientID: clientID.description)
    try await repository.saveProfile(Profile(
        id: profileID,
        name: "Personal",
        createdAt: firstDate,
        modifiedAt: firstDate,
        deviceID: clientID.description,
        mutationStamp: firstStamp
    ))
    try await repository.saveMediaSnapshot(ProfileMediaSnapshot(
        key: mediaKey,
        locator: locator,
        title: "Synthetic Movie",
        kind: .movie,
        artworkURL: nil,
        metadata: ProfileMediaMetadataSnapshot(
            directors: [ProfilePersonSnapshot(name: "Existing Director")]
        ),
        modifiedAt: firstDate,
        deviceID: clientID.description,
        mutationStamp: firstStamp
    ), profileID: profileID)
    try await repository.saveMediaSnapshot(ProfileMediaSnapshot(
        key: mediaKey,
        locator: locator,
        title: "Synthetic Movie",
        kind: .movie,
        artworkURL: URL(string: "https://example.invalid/poster.jpg"),
        metadata: ProfileMediaMetadataSnapshot(
            genres: [ProfileGenreSnapshot(name: "Drama")]
        ),
        modifiedAt: secondDate,
        deviceID: clientID.description,
        mutationStamp: secondStamp
    ), profileID: profileID)

    let result = try #require(
        try await repository.mediaSnapshots(keys: [mediaKey]).first
    )
    #expect(result.metadata?.genres.map(\.name) == ["Drama"])
    #expect(result.metadata?.directors.map(\.name) == ["Existing Director"])
    #expect(result.artworkURL == URL(string: "https://example.invalid/poster.jpg"))

    try await repository.saveMediaSnapshot(ProfileMediaSnapshot(
        key: mediaKey,
        locator: locator,
        title: "Stale",
        kind: .movie,
        artworkURL: nil,
        modifiedAt: firstDate,
        deviceID: clientID.description,
        mutationStamp: firstStamp
    ), profileID: profileID)
    #expect(try await repository.mediaSnapshots(keys: [mediaKey]).first == result)
}

@Test func viewingFactsAreIdempotentAndDriveProfileManifest() async throws {
    let repository = try CoreDataProfileRepository(configuration: .init(inMemory: true))
    let clientID = ClientID(rawValue: UUID())
    let profileID = ProfileID(rawValue: UUID())
    let locator = MediaLocatorID(
        sourceID: SourceID(rawValue: UUID()),
        providerItemID: "movie-1"
    )
    let date = Date(timeIntervalSince1970: 100)
    let stamp = MutationStamp(date: date, clientID: clientID.description)
    let sessionID = ViewingSessionID(rawValue: UUID())
    try await repository.saveProfile(Profile(
        id: profileID,
        name: "Personal",
        createdAt: date,
        modifiedAt: date,
        deviceID: clientID.description,
        mutationStamp: stamp
    ))
    try await repository.saveDeviceRecord(
        DeviceRecord(
            id: DeviceRecordID(clientID: clientID),
            clientID: clientID,
            displayName: "Test Mac",
            platform: "macOS",
            lastSeenAt: date,
            mutationStamp: stamp
        ),
        profileID: profileID
    )
    let registeredManifests = try await repository.profileManifests()
    #expect(registeredManifests.first?.lastDeviceName == "Test Mac")
    let started = playbackWrite(
        profileID: profileID,
        locator: locator,
        title: "Arrival",
        date: date,
        stamp: stamp,
        clientID: clientID,
        watchedSeconds: 0,
        sessionID: sessionID,
        status: .active,
        eventKind: .started,
        startedAt: date
    )
    let completedAt = date.addingTimeInterval(42)
    let completed = playbackWrite(
        profileID: profileID,
        locator: locator,
        title: "Arrival",
        date: completedAt,
        stamp: MutationStamp(date: completedAt, clientID: clientID.description),
        clientID: clientID,
        watchedSeconds: 42,
        sessionID: sessionID,
        status: .completed,
        eventKind: .completed,
        startedAt: date
    )

    try await repository.savePlayback(started)
    try await repository.savePlayback(started)
    try await repository.savePlayback(completed)
    try await repository.savePlayback(completed)

    let manifests = try await repository.profileManifests()
    let manifest = try #require(manifests.first)
    #expect(try await repository.viewingSessions(profileID: profileID).count == 1)
    #expect(try await repository.playbackEvents(profileID: profileID).count == 2)
    #expect(try await repository.deviceRecords().count == 1)
    #expect(manifest.lastDeviceName == "Test Mac")
    #expect(manifest.titleCount == 1)
    #expect(manifest.viewingSessionCount == 1)
    #expect(manifest.totalWatchSeconds == 42)
}

@Test func profileStateUsesModifiedAtThenDeviceIDForConflictResolution() async throws {
    let repository = try CoreDataProfileRepository(
        configuration: .init(inMemory: true)
    )
    let profileID = ProfileID(rawValue: UUID())
    let mediaKey = ProfileMediaKey(rawValue: "movie:arrival")
    let date = Date(timeIntervalSince1970: 100)

    try await repository.saveFavorite(
        ProfileFavoriteState(
            profileID: profileID,
            mediaKey: mediaKey,
            isFavorite: true,
            modifiedAt: date,
            deviceID: "device-b"
        ),
        snapshot: nil
    )
    try await repository.saveFavorite(
        ProfileFavoriteState(
            profileID: profileID,
            mediaKey: mediaKey,
            isFavorite: false,
            modifiedAt: date,
            deviceID: "device-a"
        ),
        snapshot: nil
    )

    let state = try await repository.favorite(profileID: profileID, mediaKey: mediaKey)
    #expect(state?.isFavorite == true)
    #expect(state?.deviceID == "device-b")
}

@Test func remoteImportIsIdempotent() async throws {
    let repository = try CoreDataProfileRepository(
        configuration: .init(inMemory: true)
    )
    let profileID = ProfileID(rawValue: UUID())
    let sourceID = SourceID(rawValue: UUID())
    let batch = RemoteStateImportBatch(
        marker: "initial-v1",
        profileID: profileID,
        sourceID: sourceID,
        remoteUserID: "emby-user",
        snapshots: [],
        favorites: [
            ProfileFavoriteState(
                profileID: profileID,
                mediaKey: ProfileMediaKey(rawValue: "movie:1"),
                isFavorite: true,
                modifiedAt: Date(timeIntervalSince1970: 1),
                deviceID: "remote"
            )
        ],
        playback: []
    )

    #expect(try await repository.importRemoteState(batch))
    #expect(try await !repository.importRemoteState(batch))
    #expect(try await repository.favorites(profileID: profileID).count == 1)
}

@Test func onlyOneProfileCanMirrorAnEmbyUser() async throws {
    let repository = try CoreDataProfileRepository(
        configuration: .init(inMemory: true)
    )
    let sourceID = SourceID(rawValue: UUID())
    let first = ProfileID(rawValue: UUID())
    let second = ProfileID(rawValue: UUID())

    try await repository.saveBinding(
        ProfileSourceBinding(
            profileID: first,
            sourceID: sourceID,
            remoteUserID: "emby-user",
            mirrorsRemoteState: true
        )
    )

    await #expect(throws: ProfileRepositoryError.mirrorOwnerConflict(existing: first)) {
        try await repository.saveBinding(
            ProfileSourceBinding(
                profileID: second,
                sourceID: sourceID,
                remoteUserID: "emby-user",
                mirrorsRemoteState: true
            )
        )
    }
}

@Test func sourceConfigurationAndActiveSelectionRemainLocal() async throws {
    let repository = try CoreDataProfileRepository(
        configuration: .init(inMemory: true)
    )
    let profileID = ProfileID(rawValue: UUID())
    let sourceID = SourceID(rawValue: UUID())
    let pluginID: PluginID = "emby"
    let configuration = SourceConfiguration(
        sourceID: sourceID,
        baseURL: URL(string: "https://example.com/emby")!,
        serverIdentity: SourceInstanceIdentity(pluginID: pluginID, serverID: "server"),
        displayName: "Living Room",
        remoteUserID: "user"
    )

    try await repository.saveSource(pluginID: pluginID, configuration: configuration)
    try await repository.setActiveSelection(
        ActiveProfileSelection(profileID: profileID, sourceID: sourceID),
        deviceID: "this-mac"
    )

    let sources = try await repository.sourceConfigurations()
    let selection = try await repository.activeSelection(deviceID: "this-mac")
    #expect(sources.count == 1)
    #expect(sources.first?.pluginID == pluginID)
    #expect(sources.first?.configuration == configuration)
    #expect(selection == ActiveProfileSelection(profileID: profileID, sourceID: sourceID))
}

@Test func mutationClockRemainsMonotonicAcrossEqualBackwardAndObservedTime() {
    let clientID = ClientID(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    )
    var clock = MutationClockState(clientID: clientID)
    let first = clock.tick(at: Date(timeIntervalSince1970: 100))
    let equalTime = clock.tick(at: Date(timeIntervalSince1970: 100))
    let backwardTime = clock.tick(at: Date(timeIntervalSince1970: 50))

    #expect(first.physicalMillisecondsUTC == 100_000)
    #expect(first.logicalCounter == 0)
    #expect(equalTime.physicalMillisecondsUTC == 100_000)
    #expect(equalTime.logicalCounter == 1)
    #expect(backwardTime.physicalMillisecondsUTC == 100_000)
    #expect(backwardTime.logicalCounter == 2)

    clock.observe(MutationStamp(
        physicalMillisecondsUTC: 200_000,
        logicalCounter: 4,
        clientID: "remote-client"
    ))
    let afterRemote = clock.tick(at: Date(timeIntervalSince1970: 75))
    #expect(afterRemote.physicalMillisecondsUTC == 200_000)
    #expect(afterRemote.logicalCounter == 5)
    #expect(afterRemote.clientID == clientID.description)
}

@Test func bootstrapResolutionDistinguishesCloudStateAndProfileIdentity() {
    let provisional = manifest(id: "00000000-0000-0000-0000-000000000001", name: "This Mac")
    let cloud = manifest(id: "00000000-0000-0000-0000-000000000002", name: "Personal")

    #expect(ProfileBootstrapResolver.resolve(ProfileBootstrapInput(
        provisionalProfile: provisional,
        cloudProfiles: [],
        activeProfileID: nil,
        cloudAvailability: .unavailable
    )) == .localOnly(provisional))
    #expect(ProfileBootstrapResolver.resolve(ProfileBootstrapInput(
        provisionalProfile: provisional,
        cloudProfiles: [],
        activeProfileID: nil,
        cloudAvailability: .pendingInitialImport
    )) == .waitingForCloud(provisional))
    #expect(ProfileBootstrapResolver.resolve(ProfileBootstrapInput(
        provisionalProfile: provisional,
        cloudProfiles: [],
        activeProfileID: nil,
        cloudAvailability: .available
    )) == .promoteProvisional(provisional))
    #expect(ProfileBootstrapResolver.resolve(ProfileBootstrapInput(
        provisionalProfile: provisional,
        cloudProfiles: [provisional],
        activeProfileID: provisional.id,
        cloudAvailability: .available
    )) == .synchronize(provisional))
    #expect(ProfileBootstrapResolver.resolve(ProfileBootstrapInput(
        provisionalProfile: provisional,
        cloudProfiles: [cloud],
        activeProfileID: nil,
        cloudAvailability: .available
    )) == .requiresChoice(provisional: provisional, cloudProfiles: [cloud]))
}

@Test func cloudSyncStatusProjectsAccountAndTransportFacts() {
    let completedAt = Date(timeIntervalSince1970: 200)

    #expect(ProfileCloudSyncStatus.resolve(
        availability: .unavailable
    ).phase == .localOnly)
    #expect(ProfileCloudSyncStatus.resolve(
        availability: .pendingInitialImport
    ).phase == .checking)
    #expect(ProfileCloudSyncStatus.resolve(
        availability: .available,
        activeOperations: [.exporting]
    ).phase == .synchronizing)
    #expect(ProfileCloudSyncStatus.resolve(
        availability: .available,
        lastSuccessfulAt: completedAt
    ) == ProfileCloudSyncStatus(
        phase: .upToDate,
        availability: .available,
        activeOperations: [],
        lastSuccessfulAt: completedAt,
        failureDescription: nil
    ))
    #expect(ProfileCloudSyncStatus.resolve(
        availability: .available,
        failureDescription: "iCloud synchronization failed."
    ).phase == .failed)
}

@Test func mutationStampWinsEvenWhenWallClockMovesBackward() async throws {
    let repository = try CoreDataProfileRepository(configuration: .init(inMemory: true))
    let profileID = ProfileID(rawValue: UUID())
    let mediaKey = ProfileMediaKey(rawValue: "movie:clock")

    try await repository.saveFavorite(ProfileFavoriteState(
        profileID: profileID,
        mediaKey: mediaKey,
        isFavorite: false,
        modifiedAt: Date(timeIntervalSince1970: 200),
        deviceID: "client",
        mutationStamp: MutationStamp(
            physicalMillisecondsUTC: 100_000,
            logicalCounter: 0,
            clientID: "client"
        )
    ), snapshot: nil)
    try await repository.saveFavorite(ProfileFavoriteState(
        profileID: profileID,
        mediaKey: mediaKey,
        isFavorite: true,
        modifiedAt: Date(timeIntervalSince1970: 50),
        deviceID: "client",
        mutationStamp: MutationStamp(
            physicalMillisecondsUTC: 100_000,
            logicalCounter: 1,
            clientID: "client"
        )
    ), snapshot: nil)

    #expect(try await repository.favorite(profileID: profileID, mediaKey: mediaKey)?.isFavorite == true)
}

@Test func profileMergeIsIdempotentAndRetainsSourceFacts() async throws {
    let repository = try CoreDataProfileRepository(configuration: .init(inMemory: true))
    let sourceID = ProfileID(rawValue: UUID())
    let targetID = ProfileID(rawValue: UUID())
    let createdAt = Date(timeIntervalSince1970: 100)
    let baseStamp = MutationStamp(date: createdAt, clientID: "client-a")
    for (id, name) in [(sourceID, "Local"), (targetID, "Cloud")] {
        try await repository.saveProfile(Profile(
            id: id,
            name: name,
            createdAt: createdAt,
            modifiedAt: createdAt,
            deviceID: "client-a",
            mutationStamp: baseStamp
        ))
    }
    let mediaKey = ProfileMediaKey(rawValue: "movie:merge")
    try await repository.saveFavorite(ProfileFavoriteState(
        profileID: sourceID,
        mediaKey: mediaKey,
        isFavorite: true,
        modifiedAt: createdAt,
        deviceID: "client-a",
        mutationStamp: baseStamp
    ), snapshot: nil)
    let locator = MediaLocatorID(
        sourceID: SourceID(rawValue: UUID()),
        providerItemID: "movie-merge"
    )
    try await repository.savePlayback(playbackWrite(
        profileID: sourceID,
        locator: locator,
        title: "Merge Movie",
        date: createdAt,
        stamp: baseStamp,
        clientID: ClientID(rawValue: UUID()),
        watchedSeconds: 25
    ))

    let request = ProfileMergeRequest(
        operationID: UUID(),
        sourceProfileID: sourceID,
        targetProfileID: targetID,
        mergedAt: Date(timeIntervalSince1970: 200),
        mutationStamp: MutationStamp(
            physicalMillisecondsUTC: 200_000,
            logicalCounter: 0,
            clientID: "client-a"
        )
    )
    #expect(try await repository.mergeProfiles(request))
    #expect(try await !repository.mergeProfiles(request))
    #expect(try await repository.profiles().map(\.id) == [targetID])
    #expect(try await repository.favorite(profileID: targetID, mediaKey: mediaKey)?.isFavorite == true)
    #expect(try await repository.favorite(profileID: sourceID, mediaKey: mediaKey)?.isFavorite == true)
    #expect(try await repository.viewingSessions(profileID: targetID).count == 1)
    #expect(try await repository.playbackEvents(profileID: targetID).count == 1)
}

@Test func provisionalStateStaysLocalUntilIdempotentPromotion() async throws {
    let repository = try CoreDataProfileRepository(configuration: .init(
        inMemory: true,
        cloudAvailabilityOverride: .unavailable
    ))
    let clientID = ClientID(rawValue: UUID())
    let profileID = ProfileID(rawValue: UUID())
    let sourceID = SourceID(rawValue: UUID())
    let locator = MediaLocatorID(sourceID: sourceID, providerItemID: "movie-1")
    let mediaKey = ProfileMediaKey(locator: locator)
    let date = Date(timeIntervalSince1970: 100)
    let stamp = MutationStamp(date: date, clientID: clientID.description)
    let profile = Profile(
        id: profileID,
        name: "Personal",
        createdAt: date,
        modifiedAt: date,
        deviceID: clientID.description,
        mutationStamp: stamp
    )
    try await repository.saveProvisionalProfile(profile, clientID: clientID)
    try await repository.saveFavorite(ProfileFavoriteState(
        profileID: profileID,
        mediaKey: mediaKey,
        isFavorite: true,
        modifiedAt: date,
        deviceID: clientID.description,
        mutationStamp: stamp
    ), snapshot: ProfileMediaSnapshot(
        key: mediaKey,
        locator: locator,
        title: "Arrival",
        kind: .movie,
        artworkURL: nil,
        modifiedAt: date,
        deviceID: clientID.description,
        mutationStamp: stamp
    ))
    try await repository.savePlayback(playbackWrite(
        profileID: profileID,
        locator: locator,
        title: "Arrival",
        date: date,
        stamp: stamp,
        clientID: clientID,
        watchedSeconds: 30
    ))

    #expect(try await repository.profiles().isEmpty)
    #expect(try await repository.provisionalProfileManifest(clientID: clientID)?.titleCount == 1)
    #expect(try await repository.provisionalProfileManifest(clientID: clientID)?.viewingSessionCount == 1)

    try await repository.promoteProvisionalProfile(clientID: clientID, profileID: profileID)
    try await repository.promoteProvisionalProfile(clientID: clientID, profileID: profileID)

    #expect(try await repository.provisionalProfileManifest(clientID: clientID) == nil)
    #expect(try await repository.profiles().map(\.id) == [profileID])
    #expect(try await repository.favorite(profileID: profileID, mediaKey: mediaKey)?.isFavorite == true)
    #expect(try await repository.viewingSessions(profileID: profileID).count == 1)
    #expect(try await repository.playbackEvents(profileID: profileID).count == 1)
    #expect(try await repository.deviceRecords().map(\.displayName) == ["Test Mac"])
}

@Test func provisionalMergeMovesFactsWithoutPublishingTheSourceProfile() async throws {
    let repository = try CoreDataProfileRepository(configuration: .init(inMemory: true))
    let clientID = ClientID(rawValue: UUID())
    let sourceID = ProfileID(rawValue: UUID())
    let targetID = ProfileID(rawValue: UUID())
    let mediaKey = ProfileMediaKey(rawValue: "movie:merge-provisional")
    let date = Date(timeIntervalSince1970: 100)
    let stamp = MutationStamp(date: date, clientID: clientID.description)
    try await repository.saveProvisionalProfile(Profile(
        id: sourceID,
        name: "This Mac",
        createdAt: date,
        modifiedAt: date,
        deviceID: clientID.description,
        mutationStamp: stamp
    ), clientID: clientID)
    try await repository.saveProfile(Profile(
        id: targetID,
        name: "iCloud",
        createdAt: date,
        modifiedAt: date,
        deviceID: "other-device",
        mutationStamp: stamp
    ))
    try await repository.saveFavorite(ProfileFavoriteState(
        profileID: sourceID,
        mediaKey: mediaKey,
        isFavorite: true,
        modifiedAt: date,
        deviceID: clientID.description,
        mutationStamp: stamp
    ), snapshot: nil)
    let request = ProfileMergeRequest(
        operationID: UUID(),
        sourceProfileID: sourceID,
        targetProfileID: targetID,
        mergedAt: date,
        mutationStamp: stamp
    )

    #expect(try await repository.mergeProvisionalProfile(clientID: clientID, request: request))
    #expect(try await !repository.mergeProvisionalProfile(clientID: clientID, request: request))
    #expect(try await repository.profiles().map(\.id) == [targetID])
    #expect(try await repository.provisionalProfileManifest(clientID: clientID) == nil)
    #expect(try await repository.favorite(profileID: targetID, mediaKey: mediaKey)?.isFavorite == true)
}

@Test func syncAuditIsDeterministicRedactedAndSensitiveToFactChanges() async throws {
    let first = try CoreDataProfileRepository(configuration: .init(inMemory: true))
    let second = try CoreDataProfileRepository(configuration: .init(inMemory: true))
    let profileID = ProfileID(
        rawValue: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    )
    let sourceID = SourceID(
        rawValue: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    )
    let clientID = ClientID(
        rawValue: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    )
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let stamp = MutationStamp(date: date, clientID: clientID.description)
    let profile = Profile(
        id: profileID,
        name: "Private Profile Name",
        createdAt: date,
        modifiedAt: date,
        deviceID: clientID.description,
        mutationStamp: stamp
    )
    let locator = MediaLocatorID(
        sourceID: sourceID,
        providerItemID: "private-provider-item"
    )
    let mediaKey = ProfileMediaKey(locator: locator)
    let favorite = ProfileFavoriteState(
        profileID: profileID,
        mediaKey: mediaKey,
        isFavorite: true,
        modifiedAt: date,
        deviceID: clientID.description,
        mutationStamp: stamp
    )
    let snapshot = ProfileMediaSnapshot(
        key: mediaKey,
        locator: locator,
        title: "Private Movie Title",
        kind: .movie,
        artworkURL: URL(string: "https://private.example/poster.jpg"),
        modifiedAt: date,
        deviceID: clientID.description,
        mutationStamp: stamp
    )
    let write = playbackWrite(
        profileID: profileID,
        locator: locator,
        title: "Private Movie Title",
        date: date,
        stamp: stamp,
        clientID: clientID,
        watchedSeconds: 90,
        artworkURL: URL(string: "https://private.example/poster.jpg"),
        sessionID: ViewingSessionID(
            rawValue: UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
        ),
        eventID: ProfilePlaybackEventID(
            rawValue: UUID(uuidString: "50000000-0000-0000-0000-000000000005")!
        )
    )

    try await first.saveProfile(profile)
    try await first.saveFavorite(favorite, snapshot: snapshot)
    try await first.savePlayback(write)
    try await second.savePlayback(write)
    try await second.saveFavorite(favorite, snapshot: snapshot)
    try await second.saveProfile(profile)

    let firstAudit = try await ProfileSyncAuditSnapshot.capture(
        repository: first,
        capturedAt: date
    )
    let secondAudit = try await ProfileSyncAuditSnapshot.capture(
        repository: second,
        capturedAt: date.addingTimeInterval(60)
    )
    #expect(firstAudit.profileSetDigest == secondAudit.profileSetDigest)
    #expect(firstAudit.profiles.first?.factDigest == secondAudit.profiles.first?.factDigest)

    let jsonData = try JSONEncoder().encode(firstAudit)
    let json = try #require(String(data: jsonData, encoding: .utf8))
    #expect(!json.contains(profileID.rawValue.uuidString.lowercased()))
    #expect(!json.contains(clientID.description))
    #expect(!json.contains("Private Profile Name"))
    #expect(!json.contains("Private Movie Title"))
    #expect(!json.contains("private-provider-item"))
    #expect(!json.contains("private.example"))

    let later = date.addingTimeInterval(1)
    try await second.saveFavorite(
        ProfileFavoriteState(
            profileID: profileID,
            mediaKey: mediaKey,
            isFavorite: false,
            modifiedAt: later,
            deviceID: clientID.description,
            mutationStamp: MutationStamp(date: later, clientID: clientID.description)
        ),
        snapshot: snapshot
    )
    let changed = try await ProfileSyncAuditSnapshot.capture(
        repository: second,
        capturedAt: later
    )
    #expect(changed.profileSetDigest != firstAudit.profileSetDigest)
}

private func manifest(id: String, name: String) -> ProfileManifest {
    let date = Date(timeIntervalSince1970: 100)
    return ProfileManifest(
        profile: Profile(
            id: ProfileID(rawValue: UUID(uuidString: id)!),
            name: name,
            createdAt: date,
            modifiedAt: date,
            deviceID: "client"
        ),
        lastActivityAt: date,
        lastDeviceName: "Mac",
        titleCount: 1,
        viewingSessionCount: 0,
        favoriteCount: 0,
        totalWatchSeconds: 0
    )
}

private func playbackWrite(
    profileID: ProfileID,
    locator: MediaLocatorID,
    title: String,
    date: Date,
    stamp: MutationStamp,
    clientID: ClientID,
    watchedSeconds: Double,
    artworkURL: URL? = nil,
    sessionID: ViewingSessionID = ViewingSessionID(rawValue: UUID()),
    eventID: ProfilePlaybackEventID = ProfilePlaybackEventID(rawValue: UUID()),
    status: ViewingSessionStatus = .completed,
    eventKind: ProfilePlaybackEventKind = .completed,
    startedAt: Date? = nil
) -> ProfilePlaybackWrite {
    let mediaKey = ProfileMediaKey(locator: locator)
    let deviceRecordID = DeviceRecordID(clientID: clientID)
    let deviceID = clientID.description
    let isCompleted = status == .completed
    return ProfilePlaybackWrite(
        state: ProfilePlaybackState(
            profileID: profileID,
            mediaKey: mediaKey,
            state: UserPlaybackState(
                played: isCompleted,
                positionSeconds: isCompleted ? 0 : watchedSeconds,
                progress: isCompleted ? 1 : 0,
                lastPlayedAt: date
            ),
            modifiedAt: date,
            deviceID: deviceID,
            mutationStamp: stamp
        ),
        snapshot: ProfileMediaSnapshot(
            key: mediaKey,
            locator: locator,
            title: title,
            kind: .movie,
            artworkURL: artworkURL,
            modifiedAt: date,
            deviceID: deviceID,
            mutationStamp: stamp
        ),
        session: ViewingSession(
            id: sessionID,
            profileID: profileID,
            mediaKey: mediaKey,
            deviceRecordID: deviceRecordID,
            startedAt: startedAt ?? date.addingTimeInterval(-watchedSeconds),
            endedAt: status == .active ? nil : date,
            startPositionSeconds: 0,
            endPositionSeconds: watchedSeconds,
            watchedSeconds: watchedSeconds,
            status: status,
            modifiedAt: date,
            deviceID: deviceID,
            mutationStamp: stamp
        ),
        event: ProfilePlaybackEvent(
            id: eventID,
            sessionID: sessionID,
            profileID: profileID,
            mediaKey: mediaKey,
            deviceRecordID: deviceRecordID,
            kind: eventKind,
            observedAt: date,
            positionSeconds: watchedSeconds,
            durationSeconds: watchedSeconds,
            isPaused: false,
            deviceID: deviceID,
            mutationStamp: stamp
        ),
        deviceRecord: DeviceRecord(
            id: deviceRecordID,
            clientID: clientID,
            displayName: "Test Mac",
            platform: "macOS",
            lastSeenAt: date,
            mutationStamp: stamp
        )
    )
}
