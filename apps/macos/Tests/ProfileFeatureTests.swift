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
                                    title: "Arrival"
                                ),
                                isFavorite: true,
                                playback: UserPlaybackState(
                                    played: false,
                                    positionSeconds: 25,
                                    progress: 0.25
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
        #expect(batch?.snapshots.first?.locator == locator)
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

    private static func profileClient(recorder: ProfileSyncRecorder) -> ProfileClient {
        ProfileClient(
            clientID: {
                ClientID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
            },
            load: { throw ProfileClientFailure.unavailable("unused") },
            saveProfile: { _ in },
            setSelection: { _ in },
            saveSource: { _, _ in },
            saveBinding: { _ in },
            savePlayback: { _, _ in },
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
