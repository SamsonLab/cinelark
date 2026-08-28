import Foundation
import CineLarkPluginAPI

public protocol ProfileRepository: Sendable {
    func changes() async -> AsyncStream<ProfileRepositoryChange>

    func profiles() async throws -> [Profile]
    func profileManifests() async throws -> [ProfileManifest]
    func cloudProfileAvailability() async -> CloudProfileAvailability
    func cloudSyncStatus() async -> ProfileCloudSyncStatus
    func provisionalProfileManifest(clientID: ClientID) async throws -> ProfileManifest?
    func saveProfile(_ profile: Profile) async throws
    func saveProvisionalProfile(_ profile: Profile, clientID: ClientID) async throws
    func promoteProvisionalProfile(clientID: ClientID, profileID: ProfileID) async throws
    func discardProvisionalProfile(clientID: ClientID, profileID: ProfileID) async throws
    @discardableResult
    func mergeProvisionalProfile(
        clientID: ClientID,
        request: ProfileMergeRequest
    ) async throws -> Bool
    func tombstoneProfile(id: ProfileID, at date: Date, mutationStamp: MutationStamp) async throws
    @discardableResult
    func mergeProfiles(_ request: ProfileMergeRequest) async throws -> Bool

    func nextMutationStamp(clientID: ClientID, at wallTime: Date) async throws -> MutationStamp

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
    func saveMediaSnapshot(_ snapshot: ProfileMediaSnapshot, profileID: ProfileID) async throws
    func saveFavorite(_ state: ProfileFavoriteState, snapshot: ProfileMediaSnapshot?) async throws

    func playback(profileID: ProfileID, mediaKey: ProfileMediaKey) async throws -> ProfilePlaybackState?
    func playbackStates(profileID: ProfileID) async throws -> [ProfilePlaybackState]
    func viewingSessions(profileID: ProfileID) async throws -> [ViewingSession]
    func playbackEvents(profileID: ProfileID) async throws -> [ProfilePlaybackEvent]
    func deviceRecords() async throws -> [DeviceRecord]
    func saveDeviceRecord(_ record: DeviceRecord, profileID: ProfileID) async throws
    func savePlayback(_ write: ProfilePlaybackWrite) async throws

    @discardableResult
    func importRemoteState(_ batch: RemoteStateImportBatch) async throws -> Bool

    func enqueueMirror(_ entry: MirrorQueueEntry) async throws
    func dueMirrorEntries(at date: Date, limit: Int) async throws -> [MirrorQueueEntry]
    func completeMirrorEntry(id: UUID) async throws
    func rescheduleMirrorEntry(id: UUID, attempts: Int, nextAttemptAt: Date) async throws
}
