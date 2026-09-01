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
    var completed: [UUID] = []
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

    func appendCompletion(_ id: UUID) {
        completed.append(id)
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

    @Test("Mirror retries honor provider delay through TestClock")
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
                    throw MediaSourceFailure.rateLimited(retryAfterSeconds: 7)
                }
            )
        }

        await store.send(.view(.processMirrorQueue)) {
            $0.isProcessingMirrorQueue = true
        }
        await store.receive(.internal(.mirrorPassFinished(.success(
            ProfileFeature.MirrorPassOutcome(
                shouldContinue: false,
                retryDelaySeconds: 7
            )
        )))) {
            $0.isProcessingMirrorQueue = false
        }

        let rescheduled = await recorder.rescheduled
        #expect(rescheduled.first?.1 == 1)
        #expect(rescheduled.first?.2 == now.addingTimeInterval(7))

        await clock.advance(by: .seconds(7))
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

    @Test("Permanent mirror failures stop retrying without rolling back local state")
    func terminalMirrorFailure() async {
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
            mutation: .favorite(ProfileFavoriteState(
                profileID: profileID,
                mediaKey: ProfileMediaKey(locator: locator),
                isFavorite: true,
                modifiedAt: now,
                deviceID: "device"
            )),
            nextAttemptAt: now
        )
        let recorder = ProfileSyncRecorder(dueEntry: entry)
        let store = TestStore(initialState: ProfileFeature.State()) {
            ProfileFeature()
        } withDependencies: {
            $0.date.now = now
            $0.profiles = Self.profileClient(recorder: recorder)
            $0.mediaPlatform = MediaPlatformClient(
                descriptors: { [] },
                cachedPage: { _ in throw MediaSourceFailure.unavailable },
                refreshPage: { _ in throw MediaSourceFailure.unavailable },
                mirrorRemoteState: { _, _, _ in
                    throw MediaSourceFailure.requestRejected
                }
            )
        }

        await store.send(.view(.processMirrorQueue)) {
            $0.isProcessingMirrorQueue = true
        }
        let failure = ProfileClientFailure.unavailable(
            "The media source rejected a mirrored state update."
        )
        await store.receive(.internal(.mirrorPassFinished(.success(
            ProfileFeature.MirrorPassOutcome(
                shouldContinue: false,
                retryDelaySeconds: nil,
                terminalFailure: failure
            )
        )))) {
            $0.isProcessingMirrorQueue = false
            $0.failure = failure
        }

        #expect(await recorder.completed == [entry.id])
        #expect(await recorder.rescheduled.isEmpty)
    }

    @Test("Bootstrap consolidates legacy Profiles into the stable Personal Profile")
    func bootstrapConsolidatesLegacyProfiles() async throws {
        let clientID = ClientID(rawValue: UUID())
        let date = Date(timeIntervalSince1970: 100)
        let repository = try CoreDataProfileRepository(configuration: .init(inMemory: true))
        let first = ProfileID(rawValue: UUID())
        let second = ProfileID(rawValue: UUID())
        try await repository.saveProfile(Profile(
            id: first,
            name: "Legacy A",
            createdAt: date,
            modifiedAt: date,
            deviceID: "device-a"
        ))
        try await repository.saveProfile(Profile(
            id: second,
            name: "Legacy B",
            createdAt: date.addingTimeInterval(1),
            modifiedAt: date.addingTimeInterval(1),
            deviceID: "device-b"
        ))
        try await repository.saveFavorite(
            ProfileFavoriteState(
                profileID: first,
                mediaKey: ProfileMediaKey(rawValue: "legacy:a"),
                isFavorite: true,
                modifiedAt: date,
                deviceID: "device-a"
            ),
            snapshot: nil
        )
        try await repository.saveFavorite(
            ProfileFavoriteState(
                profileID: second,
                mediaKey: ProfileMediaKey(rawValue: "legacy:b"),
                isFavorite: true,
                modifiedAt: date.addingTimeInterval(1),
                deviceID: "device-b"
            ),
            snapshot: nil
        )
        let client = ProfileClient.live(repository: repository, clientID: clientID)

        let firstBootstrap = try await client.load()
        let secondBootstrap = try await client.load()

        #expect(firstBootstrap.profile.id == .personal)
        #expect(firstBootstrap.selection.profileID == .personal)
        #expect(secondBootstrap.profile.id == .personal)
        #expect(try await repository.profiles().map(\.id) == [.personal])
        #expect(try await repository.favorites(profileID: .personal).count == 2)
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
            profile: profile,
            manifest: manifest,
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
            $0.profile = bootstrap.profile
            $0.manifest = bootstrap.manifest
            $0.activeProfileID = profile.id
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

    @Test("Pending initial import uses the Personal Profile locally")
    func pendingImportUsesPersonalProfile() async throws {
        let clientID = ClientID(rawValue: UUID())
        let repository = try CoreDataProfileRepository(configuration: .init(
            inMemory: true,
            cloudAvailabilityOverride: .pendingInitialImport
        ))
        let client = ProfileClient.live(
            repository: repository,
            clientID: clientID,
            now: { Date(timeIntervalSince1970: 100) }
        )

        let bootstrap = try await client.load()

        #expect(bootstrap.profile.id == .personal)
        #expect(bootstrap.selection.profileID == .personal)
        #expect(try await repository.profiles().isEmpty)
        #expect(try await repository.provisionalProfileManifest(clientID: clientID)?.id == .personal)
    }

    private static func profileClient(recorder: ProfileSyncRecorder) -> ProfileClient {
        ProfileClient(
            clientID: {
                ClientID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
            },
            load: { throw ProfileClientFailure.unavailable("unused") },
            cloudSyncStatus: { .localOnly },
            setSelection: { _ in },
            saveSource: { _, _ in },
            saveBinding: { _ in },
            savePlayback: { _ in },
            saveFavorite: { _, _ in },
            state: { _ in ProfileStateSnapshot(states: [:], snapshots: [:]) },
            enqueueMirror: { _ in },
            importRemoteState: { batch in await recorder.importBatch(batch) },
            dueMirrorEntries: { _, _ in await recorder.dueEntries() },
            completeMirrorEntry: { id in await recorder.appendCompletion(id) },
            rescheduleMirrorEntry: { id, attempts, date in
                await recorder.appendReschedule(id, attempts, date)
            },
            changes: { AsyncStream { $0.finish() } }
        )
    }
}
