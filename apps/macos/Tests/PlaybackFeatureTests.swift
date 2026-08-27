import ComposableArchitecture
import Foundation
import Testing
import CineLarkDomain
import CineLarkPlayback
import CineLarkPluginAPI
import CineLarkProfile

@testable import CineLark

private actor PlaybackReportRecorder {
    var remoteEvents: [CineLarkPluginAPI.PlaybackEvent] = []
    var localStates: [ProfilePlaybackState] = []

    func append(_ event: CineLarkPluginAPI.PlaybackEvent) {
        remoteEvents.append(event)
    }

    func append(_ state: ProfilePlaybackState) {
        localStates.append(state)
    }
}

@MainActor
struct PlaybackFeatureTests {
    @Test("Playback lifecycle reports remote state and persists local progress")
    func lifecycleReporting() async {
        let clock = TestClock()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let profileID = ProfileID(rawValue: UUID())
        let sourceID = SourceID(rawValue: UUID())
        let locator = MediaLocatorID(sourceID: sourceID, providerItemID: "movie")
        let playbackID = UUID()
        let recorder = PlaybackReportRecorder()
        let profileClient = ProfileClient(
            clientID: {
                ClientID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
            },
            load: { throw ProfileClientFailure.unavailable("unused") },
            resolveProfile: { _ in throw ProfileClientFailure.unavailable("unused") },
            saveProfile: { _ in },
            setSelection: { _ in },
            saveSource: { _, _ in },
            saveBinding: { _ in },
            savePlayback: { state, _ in await recorder.append(state) },
            saveFavorite: { _, _ in },
            state: { _ in ProfileStateSnapshot(states: [:], snapshots: [:]) },
            enqueueMirror: { _ in },
            importRemoteState: { _ in true },
            dueMirrorEntries: { _, _ in [] },
            completeMirrorEntry: { _ in },
            rescheduleMirrorEntry: { _, _, _ in },
            changes: { AsyncStream { $0.finish() } }
        )
        var initialState = PlaybackFeature.State(profileID: profileID)
        initialState.active = PlaybackFeature.Active(
            id: playbackID,
            locator: locator,
            mediaKey: ProfileMediaKey(locator: locator),
            title: "Movie",
            kind: .movie,
            positionSeconds: 12,
            durationSeconds: 120,
            isPaused: false
        )
        let store = TestStore(initialState: initialState) {
            PlaybackFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date.now = now
            $0.profiles = profileClient
            $0.mediaPlatform = MediaPlatformClient(
                descriptors: { [] },
                cachedPage: { _ in throw MediaSourceFailure.unavailable },
                refreshPage: { _ in throw MediaSourceFailure.unavailable },
                reportPlayback: { _, event in await recorder.append(event) }
            )
        }

        await store.send(.internal(.engineEvent(.fileLoaded(
            playbackID: playbackID,
            resumedAtSeconds: 12
        )))) {
            $0.active?.didReportStarted = true
        }

        await clock.advance(by: .seconds(10))
        await store.receive(.internal(.progressTick))

        await store.send(.internal(.engineEvent(.positionChanged(
            playbackID: playbackID,
            positionSeconds: 120,
            durationSeconds: 120
        )))) {
            $0.active?.positionSeconds = 120
        }
        await store.send(.internal(.engineEvent(.ended(
            playbackID: playbackID,
            reason: "eof"
        )))) {
            $0.active = nil
        }
        await store.receive(.delegate(.stopped))

        let remoteEvents = await recorder.remoteEvents
        #expect(remoteEvents == [
            .started(locator: locator, positionSeconds: 12),
            .progress(locator: locator, positionSeconds: 12, isPaused: false),
            .stopped(locator: locator, positionSeconds: 120, reachedEOF: true)
        ])
        let localStates = await recorder.localStates
        #expect(localStates.last?.state.played == true)
        #expect(localStates.last?.state.positionSeconds == 0)
    }
}
