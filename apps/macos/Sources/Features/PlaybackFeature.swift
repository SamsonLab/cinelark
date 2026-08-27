import ComposableArchitecture
import Foundation
import CineLarkDomain
import CineLarkPlayback
import CineLarkPluginAPI
import CineLarkProfile

@Reducer
struct PlaybackFeature {
    struct Active: Equatable {
        let id: UUID
        let locator: MediaLocatorID
        let mediaKey: ProfileMediaKey
        let title: String
        let kind: MediaKind
        var positionSeconds: Double
        var durationSeconds: Double
        var isPaused: Bool
        var speed: Double = 1
        var volume: Double = 0
        var muted = false
        var fullscreen = false
        var audioTracks: [BridgeTrack] = []
        var subtitleTracks: [BridgeTrack] = []
        var didReportStarted = false
        var sessionStartedAt: Date?
        var sessionStartPositionSeconds: Double = 0
        var lastAccountedPositionSeconds: Double?
        var watchedSeconds: Double = 0
    }

    enum Failure: Error, Equatable {
        case unavailable(String)
    }

    @ObservableState
    struct State: Equatable {
        var profileID: ProfileID?
        var active: Active?
        var pendingRequestID: UUID?
        var isStarting = false
        var failure: Failure?
    }

    enum Action: Equatable {
        case view(View)
        case `internal`(Internal)
        case delegate(Delegate)

        enum View: Equatable {
            case appeared
            case contextChanged(ProfileID?)
            case play(
                locator: MediaLocatorID,
                title: String,
                kind: MediaKind,
                startPositionSeconds: Double
            )
            case control(PlaybackControlCommand)
            case stop
        }

        enum Internal: Equatable {
            case descriptorResolved(
                requestID: UUID,
                locator: MediaLocatorID,
                title: String,
                kind: MediaKind,
                startPositionSeconds: Double,
                Result<SourcePlaybackDescriptor, Failure>
            )
            case openCompleted(UUID, Result<Bool, Failure>)
            case controlFailed(UUID, Failure)
            case engineEvent(CineLarkPlayback.PlaybackEvent)
            case progressTick
        }

        enum Delegate: Equatable {
            case stopped
        }
    }

    private enum CancelID {
        case resolution
        case events
        case progress
    }

    @Dependency(\.mediaPlatform) private var mediaPlatform
    @Dependency(\.playbackEngine) private var engine
    @Dependency(\.profiles) private var profiles
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.date.now) private var now
    @Dependency(\.uuid) private var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.appeared):
                return .run { send in
                    for await event in engine.events() {
                        await send(.internal(.engineEvent(event)))
                    }
                }
                .cancellable(id: CancelID.events, cancelInFlight: true)

            case let .view(.contextChanged(profileID)):
                state.profileID = profileID
                return .none

            case let .view(.play(locator, title, kind, startPosition)):
                state.isStarting = true
                state.failure = nil
                let requestID = uuid()
                state.pendingRequestID = requestID
                return .run { send in
                    do {
                        let descriptor = try await mediaPlatform.resolvePlayback(locator)
                        await send(.internal(.descriptorResolved(
                            requestID: requestID,
                            locator: locator,
                            title: title,
                            kind: kind,
                            startPositionSeconds: startPosition,
                            .success(descriptor)
                        )))
                    } catch {
                        await send(.internal(.descriptorResolved(
                            requestID: requestID,
                            locator: locator,
                            title: title,
                            kind: kind,
                            startPositionSeconds: startPosition,
                            .failure(Self.normalize(error))
                        )))
                    }
                }
                .cancellable(id: CancelID.resolution, cancelInFlight: true)

            case let .internal(.descriptorResolved(requestID, locator, title, kind, start, .success(descriptor))):
                guard state.pendingRequestID == requestID else { return .none }
                state.pendingRequestID = nil
                let playbackID = uuid()
                state.active = Active(
                    id: playbackID,
                    locator: locator,
                    mediaKey: ProfileMediaKey(locator: locator),
                    title: title,
                    kind: kind,
                    positionSeconds: start,
                    durationSeconds: 0,
                    isPaused: false
                )
                return .run { send in
                    do {
                        try await engine.open(playbackID, descriptor, title, start)
                        await send(.internal(.openCompleted(playbackID, .success(true))))
                    } catch {
                        await send(.internal(.openCompleted(
                            playbackID,
                            .failure(Self.normalize(error))
                        )))
                    }
                }

            case let .internal(.descriptorResolved(requestID, _, _, _, _, .failure(failure))):
                guard state.pendingRequestID == requestID else { return .none }
                state.pendingRequestID = nil
                state.isStarting = false
                state.failure = failure
                return .none

            case let .internal(.openCompleted(id, .success)):
                guard state.active?.id == id else { return .none }
                state.isStarting = false
                return .none

            case let .internal(.openCompleted(id, .failure(failure))):
                guard state.active?.id == id else { return .none }
                state.isStarting = false
                state.active = nil
                state.failure = failure
                return .none

            case let .internal(.controlFailed(id, failure)):
                guard state.active?.id == id else { return .none }
                state.failure = failure
                return .none

            case let .internal(.engineEvent(.fileLoaded(playbackID, resumedAt))):
                guard state.active?.id == playbackID, var active = state.active else { return .none }
                active.positionSeconds = resumedAt
                active.didReportStarted = true
                active.sessionStartedAt = now
                active.sessionStartPositionSeconds = resumedAt
                active.lastAccountedPositionSeconds = resumedAt
                state.active = active
                return .merge(
                    report(
                        .started(locator: active.locator, positionSeconds: resumedAt),
                        active: active,
                        profileID: state.profileID,
                        localKind: .started,
                        sessionStatus: .active,
                        endedAt: nil
                    ),
                    progressTimer()
                )

            case let .internal(.engineEvent(.positionChanged(playbackID, position, duration))):
                guard state.active?.id == playbackID else { return .none }
                state.active?.positionSeconds = position
                state.active?.durationSeconds = duration
                return .none

            case let .internal(.engineEvent(.stateChanged(playbackID, snapshot))):
                guard state.active?.id == playbackID, var active = state.active else { return .none }
                let wasPaused = active.isPaused
                active.positionSeconds = snapshot.positionSeconds
                active.durationSeconds = snapshot.durationSeconds
                accountWatchTime(&active)
                active.isPaused = snapshot.state == .paused
                active.speed = snapshot.speed
                active.volume = snapshot.volume
                active.muted = snapshot.muted
                active.fullscreen = snapshot.fullscreen
                state.active = active
                guard active.didReportStarted, wasPaused != active.isPaused else { return .none }
                return persist(
                    active: active,
                    played: false,
                    reportRemote: true,
                    profileID: state.profileID,
                    localKind: active.isPaused ? .paused : .resumed,
                    sessionStatus: .active,
                    endedAt: nil
                )

            case let .internal(.engineEvent(.tracksChanged(playbackID, audio, subtitles, _))):
                guard state.active?.id == playbackID else { return .none }
                state.active?.audioTracks = audio
                state.active?.subtitleTracks = subtitles
                return .none

            case let .internal(.engineEvent(.ended(playbackID, reason))):
                guard var active = state.active, active.id == playbackID else { return .none }
                accountWatchTime(&active)
                state.active = nil
                let eof = reason == "eof" || reason == "end-of-file" || reason == "playlist_ended"
                return finish(active: active, reachedEOF: eof, profileID: state.profileID)

            case let .internal(.engineEvent(.closed(playbackID, _))):
                guard var active = state.active, active.id == playbackID else { return .none }
                accountWatchTime(&active)
                state.active = nil
                return finish(active: active, reachedEOF: false, profileID: state.profileID)

            case .internal(.engineEvent(.bridgeError(_, let message))):
                state.failure = .unavailable(message)
                return .none

            case .internal(.engineEvent):
                return .none

            case .internal(.progressTick):
                guard var active = state.active, active.didReportStarted else { return .none }
                accountWatchTime(&active)
                state.active = active
                return persist(
                    active: active,
                    played: false,
                    reportRemote: true,
                    profileID: state.profileID,
                    localKind: .checkpoint,
                    sessionStatus: .active,
                    endedAt: nil
                )

            case let .view(.control(command)):
                guard let id = state.active?.id else { return .none }
                return .run { send in
                    do {
                        try await engine.send(command, id)
                    } catch {
                        await send(.internal(.controlFailed(id, Self.normalize(error))))
                    }
                }

            case .view(.stop):
                state.pendingRequestID = nil
                state.isStarting = false
                guard var active = state.active else {
                    return .concatenate(
                        .cancel(id: CancelID.resolution),
                        .send(.delegate(.stopped))
                    )
                }
                accountWatchTime(&active)
                let stoppedPlayback = active
                state.active = nil
                return .concatenate(
                    .cancel(id: CancelID.resolution),
                    .cancel(id: CancelID.progress),
                    .run { _ in try? await engine.send(.stop, stoppedPlayback.id) },
                    finish(
                        active: stoppedPlayback,
                        reachedEOF: false,
                        profileID: state.profileID
                    )
                )

            case .delegate:
                return .none
            }
        }
    }

    private func progressTimer() -> Effect<Action> {
        .run { send in
            for await _ in clock.timer(interval: .seconds(10)) {
                await send(.internal(.progressTick))
            }
        }
        .cancellable(id: CancelID.progress, cancelInFlight: true)
    }

    private func finish(
        active: Active,
        reachedEOF: Bool,
        profileID: ProfileID?
    ) -> Effect<Action> {
        let endedAt = now
        return .concatenate(
            .cancel(id: CancelID.progress),
            report(
                .stopped(
                    locator: active.locator,
                    positionSeconds: active.positionSeconds,
                    reachedEOF: reachedEOF
                ),
                active: active,
                played: reachedEOF,
                profileID: profileID,
                localKind: reachedEOF ? .completed : .stopped,
                sessionStatus: reachedEOF ? .completed : .stopped,
                endedAt: endedAt
            ),
            .send(.delegate(.stopped))
        )
    }

    private func report(
        _ event: CineLarkPluginAPI.PlaybackEvent,
        active: Active,
        played: Bool = false,
        profileID: ProfileID?,
        localKind: ProfilePlaybackEventKind,
        sessionStatus: ViewingSessionStatus,
        endedAt: Date?
    ) -> Effect<Action> {
        let timestamp = now
        let eventID = ProfilePlaybackEventID(rawValue: uuid())
        return .run { _ in
            await saveLocal(
                active: active,
                played: played,
                profileID: profileID,
                eventID: eventID,
                eventKind: localKind,
                sessionStatus: sessionStatus,
                timestamp: timestamp,
                endedAt: endedAt
            )
            try? await mediaPlatform.reportPlayback(active.locator.sourceID, event)
        }
    }

    private func persist(
        active: Active,
        played: Bool,
        reportRemote: Bool,
        profileID: ProfileID?,
        localKind: ProfilePlaybackEventKind,
        sessionStatus: ViewingSessionStatus,
        endedAt: Date?
    ) -> Effect<Action> {
        let timestamp = now
        let eventID = ProfilePlaybackEventID(rawValue: uuid())
        return .run { _ in
            await saveLocal(
                active: active,
                played: played,
                profileID: profileID,
                eventID: eventID,
                eventKind: localKind,
                sessionStatus: sessionStatus,
                timestamp: timestamp,
                endedAt: endedAt
            )
            if reportRemote {
                try? await mediaPlatform.reportPlayback(
                    active.locator.sourceID,
                    .progress(
                        locator: active.locator,
                        positionSeconds: active.positionSeconds,
                        isPaused: active.isPaused
                    )
                )
            }
        }
    }

    private func saveLocal(
        active: Active,
        played: Bool,
        profileID: ProfileID?,
        eventID: ProfilePlaybackEventID,
        eventKind: ProfilePlaybackEventKind,
        sessionStatus: ViewingSessionStatus,
        timestamp: Date,
        endedAt: Date?
    ) async {
        guard let profileID else { return }
        let duration = max(active.durationSeconds, 0)
        let progress = duration > 0 ? active.positionSeconds / duration : 0
        let deviceID = profiles.deviceID()
        let deviceRecordID = profiles.deviceRecordID()
        let sessionID = ViewingSessionID(rawValue: active.id)
        let state = ProfilePlaybackState(
            profileID: profileID,
            mediaKey: active.mediaKey,
            state: UserPlaybackState(
                played: played,
                positionSeconds: played ? 0 : active.positionSeconds,
                progress: played ? 1 : progress,
                lastPlayedAt: timestamp
            ),
            modifiedAt: timestamp,
            deviceID: deviceID
        )
        let snapshot = ProfileMediaSnapshot(
            key: active.mediaKey,
            locator: active.locator,
            title: active.title,
            kind: active.kind,
            artworkURL: nil,
            modifiedAt: timestamp,
            deviceID: deviceID
        )
        let session = ViewingSession(
            id: sessionID,
            profileID: profileID,
            mediaKey: active.mediaKey,
            deviceRecordID: deviceRecordID,
            startedAt: active.sessionStartedAt ?? timestamp,
            endedAt: endedAt,
            startPositionSeconds: active.sessionStartPositionSeconds,
            endPositionSeconds: active.positionSeconds,
            watchedSeconds: active.watchedSeconds,
            status: sessionStatus,
            modifiedAt: timestamp,
            deviceID: deviceID
        )
        let event = ProfilePlaybackEvent(
            id: eventID,
            sessionID: sessionID,
            profileID: profileID,
            mediaKey: active.mediaKey,
            deviceRecordID: deviceRecordID,
            kind: eventKind,
            observedAt: timestamp,
            positionSeconds: active.positionSeconds,
            durationSeconds: duration,
            isPaused: active.isPaused,
            deviceID: deviceID
        )
        try? await profiles.savePlayback(ProfilePlaybackWrite(
            state: state,
            snapshot: snapshot,
            session: session,
            event: event,
            deviceRecord: nil
        ))
    }

    private func accountWatchTime(_ active: inout Active) {
        guard let previous = active.lastAccountedPositionSeconds else {
            active.lastAccountedPositionSeconds = active.positionSeconds
            return
        }
        defer { active.lastAccountedPositionSeconds = active.positionSeconds }
        guard !active.isPaused else { return }
        let delta = active.positionSeconds - previous
        guard delta > 0, delta <= 30 else { return }
        active.watchedSeconds += delta
    }

    private static func normalize(_ error: Error) -> Failure {
        .unavailable(String(describing: error))
    }
}
