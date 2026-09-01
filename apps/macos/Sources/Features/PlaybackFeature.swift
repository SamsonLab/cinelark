import ComposableArchitecture
import Foundation
import CineLarkDomain
import CineLarkPlayback
import CineLarkPluginAPI
import CineLarkProfile

@Reducer
struct PlaybackFeature {
    struct Request: Equatable {
        let locator: MediaLocatorID
        let title: String
        let kind: MediaKind
        let artworkURL: URL?
        let metadata: ProfileMediaMetadataSnapshot?
        let startPositionSeconds: Double
        let variantID: String?
    }

    struct Active: Equatable {
        let id: UUID
        let locator: MediaLocatorID
        let mediaKey: ProfileMediaKey
        let title: String
        let kind: MediaKind
        var artworkURL: URL? = nil
        var metadata: ProfileMediaMetadataSnapshot? = nil
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

        var message: String {
            switch self {
            case let .unavailable(message): message
            }
        }
    }

    @ObservableState
    struct State: Equatable {
        var profileID: ProfileID?
        var active: Active?
        var pendingRequestID: UUID?
        var performanceInterval: CineLarkPerformanceInterval?
        var lastRequest: Request?
        var isStarting = false
        var failure: Failure?

        var canRetry: Bool {
            failure != nil && lastRequest != nil && active == nil && !isStarting
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.profileID == rhs.profileID
                && lhs.active == rhs.active
                && lhs.pendingRequestID == rhs.pendingRequestID
                && lhs.lastRequest == rhs.lastRequest
                && lhs.isStarting == rhs.isStarting
                && lhs.failure == rhs.failure
        }
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
                artworkURL: URL?,
                metadata: ProfileMediaMetadataSnapshot?,
                startPositionSeconds: Double,
                variantID: String?
            )
            case control(PlaybackControlCommand)
            case retry
            case dismissFailure
            case stop
        }

        enum Internal: Equatable {
            case descriptorResolved(
                requestID: UUID,
                locator: MediaLocatorID,
                title: String,
                kind: MediaKind,
                artworkURL: URL?,
                metadata: ProfileMediaMetadataSnapshot?,
                startPositionSeconds: Double,
                Result<SourcePlaybackDescriptor, Failure>
            )
            case openCompleted(UUID, Result<Bool, Failure>)
            case startupTimedOut(UUID)
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
        case startup
    }

    @Dependency(\.mediaPlatform) private var mediaPlatform
    @Dependency(\.playbackEngine) private var engine
    @Dependency(\.profiles) private var profiles
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.date.now) private var now
    @Dependency(\.uuid) private var uuid
    @Dependency(\.performance) private var performance

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

            case let .view(.play(
                locator,
                title,
                kind,
                artworkURL,
                metadata,
                startPosition,
                variantID
            )):
                let request = Request(
                    locator: locator,
                    title: title,
                    kind: kind,
                    artworkURL: artworkURL,
                    metadata: metadata,
                    startPositionSeconds: startPosition,
                    variantID: variantID
                )
                state.lastRequest = request
                state.isStarting = true
                state.failure = nil
                if let interval = state.performanceInterval {
                    performance.finish(interval, .cancelled)
                }
                state.performanceInterval = performance.start(.playbackFileLoad)
                let requestID = uuid()
                state.pendingRequestID = requestID
                return .merge(
                    .cancel(id: CancelID.startup),
                    resolve(request, requestID: requestID)
                        .cancellable(id: CancelID.resolution, cancelInFlight: true)
                )

            case .view(.retry):
                guard let request = state.lastRequest, !state.isStarting else { return .none }
                state.isStarting = true
                state.failure = nil
                if let interval = state.performanceInterval {
                    performance.finish(interval, .cancelled)
                }
                state.performanceInterval = performance.start(.playbackFileLoad)
                let requestID = uuid()
                state.pendingRequestID = requestID
                return .merge(
                    .cancel(id: CancelID.startup),
                    resolve(request, requestID: requestID)
                        .cancellable(id: CancelID.resolution, cancelInFlight: true)
                )

            case .view(.dismissFailure):
                state.failure = nil
                return .none

            case let .internal(.descriptorResolved(
                requestID,
                locator,
                title,
                kind,
                artworkURL,
                metadata,
                start,
                .success(descriptor)
            )):
                guard state.pendingRequestID == requestID else { return .none }
                state.pendingRequestID = nil
                let playbackID = uuid()
                state.active = Active(
                    id: playbackID,
                    locator: locator,
                    mediaKey: ProfileMediaKey(locator: locator),
                    title: title,
                    kind: kind,
                    artworkURL: artworkURL,
                    metadata: metadata,
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

            case let .internal(.descriptorResolved(requestID, _, _, _, _, _, _, .failure(failure))):
                guard state.pendingRequestID == requestID else { return .none }
                state.pendingRequestID = nil
                state.isStarting = false
                state.failure = failure
                finishPerformance(&state, outcome: .failure)
                return .none

            case let .internal(.openCompleted(id, .success)):
                guard state.active?.id == id else { return .none }
                return .run { send in
                    try await clock.sleep(for: .seconds(20))
                    await send(.internal(.startupTimedOut(id)))
                }
                .cancellable(id: CancelID.startup, cancelInFlight: true)

            case let .internal(.openCompleted(id, .failure(failure))):
                guard state.active?.id == id else { return .none }
                state.isStarting = false
                state.active = nil
                state.failure = failure
                finishPerformance(&state, outcome: .failure)
                return .none

            case let .internal(.startupTimedOut(id)):
                guard state.isStarting,
                      state.active?.id == id,
                      state.active?.didReportStarted == false else { return .none }
                state.isStarting = false
                state.active = nil
                state.failure = .unavailable(
                    "IINA did not load the media in time. Reconnect the CineLark Bridge, then retry."
                )
                finishPerformance(&state, outcome: .failure)
                return .none

            case let .internal(.controlFailed(id, failure)):
                guard state.active?.id == id else { return .none }
                state.failure = failure
                return .none

            case let .internal(.engineEvent(.fileLoaded(playbackID, resumedAt))):
                guard state.active?.id == playbackID, var active = state.active else { return .none }
                state.lastRequest = nil
                state.isStarting = false
                finishPerformance(&state, outcome: .success)
                active.positionSeconds = resumedAt
                active.didReportStarted = true
                active.sessionStartedAt = now
                active.sessionStartPositionSeconds = resumedAt
                active.lastAccountedPositionSeconds = resumedAt
                state.active = active
                return .merge(
                    .cancel(id: CancelID.startup),
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
                if state.isStarting, state.active?.didReportStarted != true {
                    state.active = nil
                    state.isStarting = false
                    finishPerformance(&state, outcome: .failure)
                }
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
                state.lastRequest = nil
                state.isStarting = false
                finishPerformance(&state, outcome: .cancelled)
                guard var active = state.active else {
                    return .concatenate(
                        .cancel(id: CancelID.resolution),
                        .cancel(id: CancelID.startup),
                        .send(.delegate(.stopped))
                    )
                }
                accountWatchTime(&active)
                let stoppedPlayback = active
                state.active = nil
                return .concatenate(
                    .cancel(id: CancelID.resolution),
                    .cancel(id: CancelID.startup),
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

    private func resolve(_ request: Request, requestID: UUID) -> Effect<Action> {
        .run { send in
            do {
                let descriptor = try await mediaPlatform.resolvePlaybackVariant(
                    request.locator,
                    request.variantID
                )
                await send(.internal(.descriptorResolved(
                    requestID: requestID,
                    locator: request.locator,
                    title: request.title,
                    kind: request.kind,
                    artworkURL: request.artworkURL,
                    metadata: request.metadata,
                    startPositionSeconds: request.startPositionSeconds,
                    .success(descriptor)
                )))
            } catch {
                await send(.internal(.descriptorResolved(
                    requestID: requestID,
                    locator: request.locator,
                    title: request.title,
                    kind: request.kind,
                    artworkURL: request.artworkURL,
                    metadata: request.metadata,
                    startPositionSeconds: request.startPositionSeconds,
                    .failure(Self.normalize(error))
                )))
            }
        }
    }

    private func finishPerformance(
        _ state: inout State,
        outcome: CineLarkPerformanceOutcome
    ) {
        guard let interval = state.performanceInterval else { return }
        performance.finish(interval, outcome)
        state.performanceInterval = nil
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
            .cancel(id: CancelID.startup),
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
            artworkURL: active.artworkURL,
            metadata: active.metadata,
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
        .unavailable(
            (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        )
    }
}
