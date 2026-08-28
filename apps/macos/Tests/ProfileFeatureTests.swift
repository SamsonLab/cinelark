import ComposableArchitecture
import Foundation
import Testing
import CineLarkDomain
import CineLarkPluginAPI
import CineLarkProfile

@testable import CineLark

private actor ProfileSyncRecorder {
    var importedBatch: RemoteStateImportBatch?
    var dueCalls = 0
    var mirrored: [RemoteStateMutation] = []
    var rescheduled: [(UUID, Int, Date)] = []
    let dueEntry: MirrorQueueEntry?

    init(dueEntry: MirrorQueueEntry? = nil) {
        self.dueEntry = dueEntry
    }

    func importBatch(_ batch: RemoteStateImportBatch) -> Bool {
        importedBatch = batch
        return true
    }

    func dueEntries() -> [MirrorQueueEntry] {
        defer { dueCalls += 1 }
        return dueCalls == 0 ? dueEntry.map { [$0] } ?? [] : []
    }

    func appendMirror(_ mutation: RemoteStateMutation) {
        mirrored.append(mutation)
    }

    func appendReschedule(_ id: UUID, _ attempts: Int, _ date: Date) {
        rescheduled.append((id, attempts, date))
    }
}

@MainActor
struct ProfileFeatureTests {
    @Test("Explicit remote import is converted to one local-first profile batch")
    func remoteImport() async {
        let profileID = ProfileID(rawValue: UUID())
        let sourceID = SourceID(rawValue: UUID())
        let locator = MediaLocatorID(sourceID: sourceID, providerItemID: "movie-1")
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let remoteLastPlayedAt = Date(timeIntervalSince1970: 1_787_753_106)
        let recorder = ProfileSyncRecorder()
        var state = ProfileFeature.State()
        state.activeProfileID = profileID
        state.activeSourceID = sourceID
        let store = TestStore(initialState: state) {
            ProfileFeature()
        } withDependencies: {
            $0.date.now = timestamp
            $0.profiles = Self.profileClient(recorder: recorder)
            $0.mediaPlatform = MediaPlatformClient(
                descriptors: { [] },
                cachedPage: { _ in throw MediaSourceFailure.unavailable },
                refreshPage: { _ in throw MediaSourceFailure.unavailable },
                importRemoteState: { _ in
                    RemoteStateSnapshot(
                        marker: "remote-v1",
                        remoteUserID: "user-1",
                        items: [
                            RemoteMediaState(
                                locator: locator,
                                summary: MediaSummary(
                                    id: "movie-1",
                                    kind: .movie,
                                    title: "Arrival",
                                    genres: [Genre(
                                        id: 2_122_445_355,
                                        name: "Science Fiction",
                                        slug: "science-fiction"
                                    )]
                                ),
                                isFavorite: true,
                                playback: UserPlaybackState(
                                    played: false,
                                    positionSeconds: 25,
                                    progress: 0.25,
                                    lastPlayedAt: remoteLastPlayedAt
                                )
                            )
                        ]
                    )
                }
            )
        }

        await store.send(.view(.importRemoteState)) {
            $0.isImportingRemoteState = true
        }
        await store.receive(.internal(.remoteStateImported(.success(true)))) {
            $0.isImportingRemoteState = false
            $0.lastImportApplied = true
        }

        let batch = await recorder.importedBatch
        #expect(batch?.marker == "remote-v1")
        #expect(batch?.favorites.first?.isFavorite == true)
        #expect(batch?.playback.first?.state.positionSeconds == 25)
        #expect(batch?.playback.first?.state.lastPlayedAt == remoteLastPlayedAt)
        #expect(batch?.snapshots.first?.locator == locator)
        #expect(batch?.snapshots.first?.metadata?.genres == [
            ProfileGenreSnapshot(
                name: "Science Fiction",
                slug: "science-fiction"
            )
        ])
    }

    @Test("Mirror failures reschedule with TestClock backoff before retrying the queue")
    func mirrorRetry() async {
        let clock = TestClock()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let profileID = ProfileID(rawValue: UUID())
        let sourceID = SourceID(rawValue: UUID())
        let locator = MediaLocatorID(sourceID: sourceID, providerItemID: "movie-1")
        let entry = MirrorQueueEntry(
            id: UUID(),
            profileID: profileID,
            sourceID: sourceID,
            remoteUserID: "user-1",
            locator: locator,
            mutation: .playback(ProfilePlaybackState(
                profileID: profileID,
                mediaKey: ProfileMediaKey(locator: locator),
                state: UserPlaybackState(
                    played: false,
                    positionSeconds: 25,
                    progress: 0.25
                ),
                modifiedAt: now,
                deviceID: "device"
            )),
            nextAttemptAt: now
        )
        let recorder = ProfileSyncRecorder(dueEntry: entry)
        let store = TestStore(initialState: ProfileFeature.State()) {
            ProfileFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date.now = now
            $0.profiles = Self.profileClient(recorder: recorder)
            $0.mediaPlatform = MediaPlatformClient(
                descriptors: { [] },
                cachedPage: { _ in throw MediaSourceFailure.unavailable },
                refreshPage: { _ in throw MediaSourceFailure.unavailable },
                mirrorRemoteState: { _, _, mutation in
                    await recorder.appendMirror(mutation)
                    throw MediaSourceFailure.unavailable
                }
            )
        }

        await store.send(.view(.processMirrorQueue)) {
            $0.isProcessingMirrorQueue = true
        }
        await store.receive(.internal(.mirrorPassFinished(.success(
            ProfileFeature.MirrorPassOutcome(
                shouldContinue: false,
                retryDelaySeconds: 2
            )
        )))) {
            $0.isProcessingMirrorQueue = false
        }

        let rescheduled = await recorder.rescheduled
        #expect(rescheduled.first?.1 == 1)
        #expect(rescheduled.first?.2 == now.addingTimeInterval(2))

        await clock.advance(by: .seconds(2))
        await store.receive(.view(.processMirrorQueue)) {
            $0.isProcessingMirrorQueue = true
        }
        await store.receive(.internal(.mirrorPassFinished(.success(
            ProfileFeature.MirrorPassOutcome(
                shouldContinue: false,
                retryDelaySeconds: nil
            )
        )))) {
            $0.isProcessingMirrorQueue = false
        }
    }

    @Test("Profile resolution remains semantic feature state until the user chooses")
    func profileResolutionChoice() async {
        let clientID = ClientID(rawValue: UUID())
        let date = Date(timeIntervalSince1970: 100)
        let provisional = ProfileManifest(
            profile: Profile(
                id: ProfileID(rawValue: UUID()),
                name: "This Mac",
                createdAt: date,
                modifiedAt: date,
                deviceID: clientID.description
            ),
            lastActivityAt: date,
            lastDeviceName: "This Mac",
            titleCount: 1,
            viewingSessionCount: 1,
            favoriteCount: 0,
            totalWatchSeconds: 120
        )
        let cloud = ProfileManifest(
            profile: Profile(
                id: ProfileID(rawValue: UUID()),
                name: "iCloud",
                createdAt: date,
                modifiedAt: date,
                deviceID: "other-device"
            ),
            lastActivityAt: date,
            lastDeviceName: "Other Mac",
            titleCount: 20,
            viewingSessionCount: 8,
            favoriteCount: 3,
            totalWatchSeconds: 3_600
        )
        let unresolved = ProfileBootstrap(
            profiles: [provisional.profile, cloud.profile],
            manifests: [provisional, cloud],
            resolution: .requiresChoice(
                provisional: provisional,
                cloudProfiles: [cloud]
            ),
            sources: [],
            selection: ActiveProfileSelection(profileID: nil, sourceID: nil)
        )
        let resolved = ProfileBootstrap(
            profiles: [cloud.profile],
            manifests: [cloud],
            resolution: .synchronize(cloud),
            sources: [],
            selection: ActiveProfileSelection(profileID: cloud.id, sourceID: nil)
        )
        let recorder = ProfileSyncRecorder()
        var client = Self.profileClient(recorder: recorder)
        client.resolveProfile = { choice in
            #expect(choice == .mergeIntoCloud(cloud.id))
            return resolved
        }
        let store = TestStore(initialState: ProfileFeature.State()) {
            ProfileFeature()
        } withDependencies: {
            $0.profiles = client
        }

        await store.send(.internal(.loaded(.success(unresolved)))) {
            $0.profiles = unresolved.profiles
            $0.manifests = unresolved.manifests
            $0.bootstrapResolution = unresolved.resolution
        }
        await store.send(.view(.resolveProfile(.mergeIntoCloud(cloud.id)))) {
            $0.isLoading = true
        }
        await store.receive(.internal(.loaded(.success(resolved)))) {
            $0.isLoading = false
            $0.profiles = resolved.profiles
            $0.manifests = resolved.manifests
            $0.activeProfileID = cloud.id
            $0.bootstrapResolution = resolved.resolution
        }
    }

    @Test("Repository invalidations coalesce behind an active bootstrap load")
    func repositoryInvalidationDefersReload() async {
        let date = Date(timeIntervalSince1970: 100)
        let profile = Profile(
            id: ProfileID(rawValue: UUID()),
            name: "Personal",
            createdAt: date,
            modifiedAt: date,
            deviceID: "client"
        )
        let manifest = ProfileManifest(
            profile: profile,
            lastActivityAt: date,
            lastDeviceName: "Mac",
            titleCount: 0,
            viewingSessionCount: 0,
            favoriteCount: 0,
            totalWatchSeconds: 0
        )
        let bootstrap = ProfileBootstrap(
            profiles: [profile],
            manifests: [manifest],
            resolution: .synchronize(manifest),
            sources: [],
            selection: ActiveProfileSelection(profileID: profile.id, sourceID: nil)
        )
        let recorder = ProfileSyncRecorder()
        var client = Self.profileClient(recorder: recorder)
        client.load = { bootstrap }
        var state = ProfileFeature.State()
        state.isLoading = true
        let store = TestStore(initialState: state) {
            ProfileFeature()
        } withDependencies: {
            $0.profiles = client
        }

        await store.send(.internal(.repositoryChanged(.profiles))) {
            $0.needsReloadAfterCurrentLoad = true
        }
        await store.send(.internal(.loaded(.success(bootstrap)))) {
            $0.profiles = bootstrap.profiles
            $0.manifests = bootstrap.manifests
            $0.activeProfileID = profile.id
            $0.bootstrapResolution = bootstrap.resolution
            $0.needsReloadAfterCurrentLoad = false
        }
        await store.receive(.internal(.loaded(.success(bootstrap)))) {
            $0.isLoading = false
        }
    }

    @Test("Cloud sync health refreshes through the dependency boundary")
    func cloudSyncStatusRefresh() async {
        let recorder = ProfileSyncRecorder()
        let completedAt = Date(timeIntervalSince1970: 200)
        let status = ProfileCloudSyncStatus(
            phase: .upToDate,
            availability: .available,
            activeOperations: [],
            lastSuccessfulAt: completedAt,
            failureDescription: nil
        )
        var client = Self.profileClient(recorder: recorder)
        client.cloudSyncStatus = { status }
        let store = TestStore(initialState: ProfileFeature.State()) {
            ProfileFeature()
        } withDependencies: {
            $0.profiles = client
        }

        await store.send(.view(.refreshCloudSyncStatus)) {
            $0.isRefreshingCloudSyncStatus = true
        }
        await store.receive(.internal(.cloudSyncStatusLoaded(status))) {
            $0.isRefreshingCloudSyncStatus = false
            $0.cloudSyncStatus = status
        }
    }

    @Test("Pending initial import can continue with the provisional local Profile")
    func continueOffline() async {
        let date = Date(timeIntervalSince1970: 100)
        let provisional = ProfileManifest(
            profile: Profile(
                id: ProfileID(rawValue: UUID()),
                name: "Personal",
                createdAt: date,
                modifiedAt: date,
                deviceID: "this-mac"
            ),
            lastActivityAt: nil,
            lastDeviceName: "This Mac",
            titleCount: 0,
            viewingSessionCount: 0,
            favoriteCount: 0,
            totalWatchSeconds: 0
        )
        let bootstrap = ProfileBootstrap(
            profiles: [provisional.profile],
            manifests: [provisional],
            resolution: .waitingForCloud(provisional),
            sources: [],
            selection: ActiveProfileSelection(profileID: nil, sourceID: nil)
        )
        let recorder = ProfileSyncRecorder()
        let store = TestStore(initialState: ProfileFeature.State()) {
            ProfileFeature()
        } withDependencies: {
            $0.profiles = Self.profileClient(recorder: recorder)
        }

        await store.send(.internal(.loaded(.success(bootstrap)))) {
            $0.profiles = bootstrap.profiles
            $0.manifests = bootstrap.manifests
            $0.bootstrapResolution = bootstrap.resolution
        }
        await store.send(.view(.continueOffline))
        let selection = ActiveProfileSelection(
            profileID: provisional.id,
            sourceID: nil
        )
        await store.receive(.internal(.selectionSaved(selection, .success))) {
            $0.activeProfileID = provisional.id
        }
        await store.receive(.delegate(.selectionChanged(selection)))
    }

    private static func profileClient(recorder: ProfileSyncRecorder) -> ProfileClient {
        ProfileClient(
            clientID: {
                ClientID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
            },
            load: { throw ProfileClientFailure.unavailable("unused") },
            resolveProfile: { _ in throw ProfileClientFailure.unavailable("unused") },
            cloudSyncStatus: { .localOnly },
            saveProfile: { _ in },
            setSelection: { _ in },
            saveSource: { _, _ in },
            saveBinding: { _ in },
            savePlayback: { _ in },
            saveFavorite: { _, _ in },
            state: { _ in ProfileStateSnapshot(states: [:], snapshots: [:]) },
            enqueueMirror: { _ in },
            importRemoteState: { batch in await recorder.importBatch(batch) },
            dueMirrorEntries: { _, _ in await recorder.dueEntries() },
            completeMirrorEntry: { _ in },
            rescheduleMirrorEntry: { id, attempts, date in
                await recorder.appendReschedule(id, attempts, date)
            },
            changes: { AsyncStream { $0.finish() } }
        )
    }
}
