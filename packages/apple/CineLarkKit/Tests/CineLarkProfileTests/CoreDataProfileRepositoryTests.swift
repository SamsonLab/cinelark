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
