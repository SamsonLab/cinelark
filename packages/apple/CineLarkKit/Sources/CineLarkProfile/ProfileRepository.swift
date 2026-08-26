import Foundation
import CineLarkPluginAPI

public protocol ProfileRepository: Sendable {
    func changes() async -> AsyncStream<ProfileRepositoryChange>

    func profiles() async throws -> [Profile]
    func saveProfile(_ profile: Profile) async throws
    func deleteProfile(id: ProfileID) async throws

    func activeSelection(deviceID: String) async throws -> ActiveProfileSelection
    func setActiveSelection(_ selection: ActiveProfileSelection, deviceID: String) async throws

    func sourceConfigurations() async throws -> [PersistedMediaSource]
    func saveSource(pluginID: PluginID, configuration: SourceConfiguration) async throws
    func deleteSource(id: SourceID) async throws
    func bindings(profileID: ProfileID) async throws -> [ProfileSourceBinding]
    func saveBinding(_ binding: ProfileSourceBinding) async throws

    func favorite(profileID: ProfileID, mediaKey: ProfileMediaKey) async throws -> ProfileFavoriteState?
    func favorites(profileID: ProfileID) async throws -> [ProfileFavoriteState]
    func mediaSnapshots(keys: Set<ProfileMediaKey>) async throws -> [ProfileMediaSnapshot]
    func saveFavorite(_ state: ProfileFavoriteState, snapshot: ProfileMediaSnapshot?) async throws

    func playback(profileID: ProfileID, mediaKey: ProfileMediaKey) async throws -> ProfilePlaybackState?
    func playbackStates(profileID: ProfileID) async throws -> [ProfilePlaybackState]
    func savePlayback(_ state: ProfilePlaybackState, snapshot: ProfileMediaSnapshot?) async throws

    @discardableResult
    func importRemoteState(_ batch: RemoteStateImportBatch) async throws -> Bool

    func enqueueMirror(_ entry: MirrorQueueEntry) async throws
    func dueMirrorEntries(at date: Date, limit: Int) async throws -> [MirrorQueueEntry]
    func completeMirrorEntry(id: UUID) async throws
    func rescheduleMirrorEntry(id: UUID, attempts: Int, nextAttemptAt: Date) async throws
}
