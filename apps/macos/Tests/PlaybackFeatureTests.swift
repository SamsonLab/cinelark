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
    var localWrites: [ProfilePlaybackWrite] = []

    func append(_ event: CineLarkPluginAPI.PlaybackEvent) {
        remoteEvents.append(event)
    }

    func append(_ write: ProfilePlaybackWrite) {
        localWrites.append(write)
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
        let artworkURL = URL(string: "https://example.test/poster.jpg")!
        let playbackID = UUID()
        let recorder = PlaybackReportRecorder()
        let profileClient = ProfileClient(
            clientID: {
                ClientID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
            },
            load: { throw ProfileClientFailure.unavailable("unused") },
            cloudSyncStatus: { .localOnly },
            setSelection: { _ in },
            saveSource: { _, _ in },
            saveBinding: { _ in },
            savePlayback: { write in await recorder.append(write) },
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
        let metadata = ProfileMediaMetadataSnapshot(
            genres: [ProfileGenreSnapshot(name: "Drama")],
            directors: [ProfilePersonSnapshot(name: "Director", tmdbID: "42")]
        )
        initialState.active = PlaybackFeature.Active(
            id: playbackID,
            locator: locator,
            mediaKey: ProfileMediaKey(locator: locator),
            title: "Movie",
            kind: .movie,
            artworkURL: artworkURL,
            metadata: metadata,
            positionSeconds: 12,
            durationSeconds: 120,
            isPaused: false
        )
        initialState.isStarting = true
        initialState.lastRequest = PlaybackFeature.Request(
            locator: locator,
            title: "Movie",
            kind: .movie,
            artworkURL: artworkURL,
            metadata: metadata,
            startPositionSeconds: 12,
            variantID: nil
        )
        let store = TestStore(initialState: initialState) {
            PlaybackFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date.now = now
            $0.uuid = .incrementing
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
            $0.lastRequest = nil
            $0.isStarting = false
            $0.active?.didReportStarted = true
            $0.active?.sessionStartedAt = now
            $0.active?.sessionStartPositionSeconds = 12
            $0.active?.lastAccountedPositionSeconds = 12
        }

        await store.send(.internal(.engineEvent(.positionChanged(
            playbackID: playbackID,
            positionSeconds: 22,
            durationSeconds: 120
        )))) {
            $0.active?.positionSeconds = 22
        }
        await clock.advance(by: .seconds(10))
        await store.receive(.internal(.progressTick)) {
            $0.active?.lastAccountedPositionSeconds = 22
            $0.active?.watchedSeconds = 10
        }

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
            .progress(locator: locator, positionSeconds: 22, isPaused: false),
            .stopped(locator: locator, positionSeconds: 120, reachedEOF: true)
        ])
        let localWrites = await recorder.localWrites
        #expect(localWrites.map(\.event?.kind) == [.started, .checkpoint, .completed])
        #expect(localWrites.last?.state.state.played == true)
        #expect(localWrites.last?.state.state.positionSeconds == 0)
        #expect(localWrites.last?.session?.status == .completed)
        #expect(localWrites.last?.session?.watchedSeconds == 10)
        #expect(localWrites.last?.snapshot?.artworkURL == artworkURL)
        #expect(localWrites.last?.snapshot?.metadata == metadata)
    }

    @Test("Paused time and seeks do not inflate watched seconds")
    func pauseAwareWatchAccounting() async {
        let clock = TestClock()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let profileID = ProfileID(rawValue: UUID())
        let sourceID = SourceID(rawValue: UUID())
        let locator = MediaLocatorID(sourceID: sourceID, providerItemID: "episode")
        let playbackID = UUID()
        let recorder = PlaybackReportRecorder()
        let profileClient = ProfileClient(
            clientID: {
                ClientID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
            },
            load: { throw ProfileClientFailure.unavailable("unused") },
            cloudSyncStatus: { .localOnly },
            setSelection: { _ in },
            saveSource: { _, _ in },
            saveBinding: { _ in },
            savePlayback: { write in await recorder.append(write) },
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
            title: "Episode",
            kind: .movie,
            positionSeconds: 0,
            durationSeconds: 120,
            isPaused: false
        )
        let store = TestStore(initialState: initialState) {
            PlaybackFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date.now = now
            $0.uuid = .incrementing
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
            resumedAtSeconds: 0
        )))) {
            $0.active?.didReportStarted = true
            $0.active?.sessionStartedAt = now
            $0.active?.lastAccountedPositionSeconds = 0
        }
        await store.send(.internal(.engineEvent(.stateChanged(
            playbackID: playbackID,
            snapshot: playbackSnapshot(state: .paused, position: 10)
        )))) {
            $0.active?.positionSeconds = 10
            $0.active?.isPaused = true
            $0.active?.lastAccountedPositionSeconds = 10
            $0.active?.watchedSeconds = 10
            $0.active?.volume = 50
        }
        await store.send(.internal(.engineEvent(.stateChanged(
            playbackID: playbackID,
            snapshot: playbackSnapshot(state: .paused, position: 90)
        )))) {
            $0.active?.positionSeconds = 90
            $0.active?.lastAccountedPositionSeconds = 90
        }
        await store.send(.internal(.engineEvent(.stateChanged(
            playbackID: playbackID,
            snapshot: playbackSnapshot(state: .playing, position: 90)
        )))) {
            $0.active?.isPaused = false
        }
        await store.send(.internal(.engineEvent(.positionChanged(
            playbackID: playbackID,
            positionSeconds: 100,
            durationSeconds: 120
        )))) {
            $0.active?.positionSeconds = 100
        }
        await clock.advance(by: .seconds(10))
        await store.receive(.internal(.progressTick)) {
            $0.active?.lastAccountedPositionSeconds = 100
            $0.active?.watchedSeconds = 20
        }
        await store.send(.internal(.engineEvent(.ended(
            playbackID: playbackID,
            reason: "closed"
        )))) {
            $0.active = nil
        }
        await store.receive(.delegate(.stopped))

        let localWrites = await recorder.localWrites
        #expect(localWrites.map(\.event?.kind) == [
            .started, .paused, .resumed, .checkpoint, .stopped
        ])
        #expect(localWrites.last?.session?.watchedSeconds == 20)
    }

    @Test("Playback launch failures retain a retryable request and a user-facing message")
    func launchFailureIsRetryable() async {
        let fixedID = UUID(uuidString: "00000000-0000-0000-0000-000000000028")!
        let sourceID = SourceID(rawValue: UUID())
        let locator = MediaLocatorID(sourceID: sourceID, providerItemID: "episode")
        let descriptor = SourcePlaybackDescriptor(
            url: URL(string: "https://example.test/video")!,
            mode: .directPlay
        )
        let request = PlaybackFeature.Request(
            locator: locator,
            title: "Episode",
            kind: .episode,
            artworkURL: nil,
            metadata: nil,
            startPositionSeconds: 42,
            variantID: nil
        )
        let store = TestStore(initialState: PlaybackFeature.State()) {
            PlaybackFeature()
        } withDependencies: {
            $0.uuid = .constant(fixedID)
            $0.mediaPlatform = MediaPlatformClient(
                descriptors: { [] },
                cachedPage: { _ in throw MediaSourceFailure.unavailable },
                refreshPage: { _ in throw MediaSourceFailure.unavailable },
                resolvePlayback: { _ in descriptor }
            )
            $0.playbackEngine = PlaybackEngineClient(
                events: { AsyncStream { $0.finish() } },
                open: { _, _, _, _ in throw PlaybackLaunchError.pluginUnavailable },
                send: { _, _ in }
            )
        }

        await store.send(.view(.play(
            locator: locator,
            title: "Episode",
            kind: .episode,
            artworkURL: nil,
            metadata: nil,
            startPositionSeconds: 42,
            variantID: nil
        ))) {
            $0.lastRequest = request
            $0.isStarting = true
            $0.pendingRequestID = fixedID
        }
        await store.receive(.internal(.descriptorResolved(
            requestID: fixedID,
            locator: locator,
            title: "Episode",
            kind: .episode,
            artworkURL: nil,
            metadata: nil,
            startPositionSeconds: 42,
            .success(descriptor)
        ))) {
            $0.pendingRequestID = nil
            $0.active = PlaybackFeature.Active(
                id: fixedID,
                locator: locator,
                mediaKey: ProfileMediaKey(locator: locator),
                title: "Episode",
                kind: .episode,
                positionSeconds: 42,
                durationSeconds: 0,
                isPaused: false
            )
        }
        await store.receive(.internal(.openCompleted(
            fixedID,
            .failure(.unavailable(
                "The CineLark IINA Bridge did not connect. In IINA, choose Plugins > CineLark Bridge > Reconnect CineLark Bridge, then retry."
            ))
        ))) {
            $0.isStarting = false
            $0.active = nil
            $0.failure = .unavailable(
                "The CineLark IINA Bridge did not connect. In IINA, choose Plugins > CineLark Bridge > Reconnect CineLark Bridge, then retry."
            )
        }
        #expect(store.state.canRetry)

        await store.send(.view(.dismissFailure)) {
            $0.failure = nil
        }
    }

    @Test("A queued player command cannot remain in preparing indefinitely")
    func fileLoadTimeoutIsRetryable() async {
        let clock = TestClock()
        let playbackID = UUID(uuidString: "00000000-0000-0000-0000-000000000029")!
        let locator = MediaLocatorID(
            sourceID: SourceID(rawValue: UUID()),
            providerItemID: "episode"
        )
        let request = PlaybackFeature.Request(
            locator: locator,
            title: "Episode",
            kind: .episode,
            artworkURL: nil,
            metadata: nil,
            startPositionSeconds: 0,
            variantID: "source-1"
        )
        var initialState = PlaybackFeature.State()
        initialState.active = PlaybackFeature.Active(
            id: playbackID,
            locator: locator,
            mediaKey: ProfileMediaKey(locator: locator),
            title: "Episode",
            kind: .episode,
            positionSeconds: 0,
            durationSeconds: 0,
            isPaused: false
        )
        initialState.lastRequest = request
        initialState.isStarting = true
        let store = TestStore(initialState: initialState) {
            PlaybackFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }

        await store.send(.internal(.openCompleted(playbackID, .success(true))))
        await clock.advance(by: .seconds(20))
        await store.receive(.internal(.startupTimedOut(playbackID))) {
            $0.active = nil
            $0.isStarting = false
            $0.failure = .unavailable(
                "IINA did not load the media in time. Reconnect the CineLark Bridge, then retry."
            )
        }
        #expect(store.state.canRetry)
    }
}

private func playbackSnapshot(
    state: PlaybackSnapshot.State,
    position: Double
) -> PlaybackSnapshot {
    PlaybackSnapshot(
        state: state,
        positionSeconds: position,
        durationSeconds: 120,
        speed: 1,
        volume: 50,
        muted: false,
        fullscreen: false
    )
}
