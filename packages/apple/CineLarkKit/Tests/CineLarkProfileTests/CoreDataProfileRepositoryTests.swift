import Foundation
import Testing
import CineLarkDomain
import CineLarkPluginAPI
@testable import CineLarkProfile

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
    try await repository.savePlayback(
        ProfilePlaybackState(
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
        snapshot: nil
    )

    #expect(try await repository.favorite(profileID: first, mediaKey: mediaKey)?.isFavorite == true)
    #expect(try await repository.favorite(profileID: second, mediaKey: mediaKey) == nil)
    #expect(try await repository.playback(profileID: first, mediaKey: mediaKey) == nil)
    #expect(try await repository.playback(profileID: second, mediaKey: mediaKey)?.state.positionSeconds == 50)
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
