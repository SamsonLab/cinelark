import Foundation
import Observation
import OSLog
import CineLarkDomain
import CineLarkPlayback

@Observable
@MainActor
final class PlaybackCoordinator {
    private static let logger = Logger(
        subsystem: "com.samsonlab.cinelark",
        category: "Playback"
    )

    var onStoppedReported: (@MainActor @Sendable () async -> Void)?
    var onRemoteStateChanged: (@MainActor @Sendable () -> Void)?
    private(set) var playbackStateRevision = 0
    private(set) var remotePlaybackRevision: UInt64 = 0

    struct RemoteSnapshot: Equatable {
        let playbackID: UUID
        let state: PlaybackSnapshot.State
        let title: String
        let positionSeconds: Double
        let durationSeconds: Double
        let speed: Double
        let volume: Double
        let muted: Bool
        let fullscreen: Bool
        let canPlayPrevious: Bool
        let canPlayNext: Bool
        let audioTracks: [BridgeTrack]
        let subtitleTracks: [BridgeTrack]
    }

    private(set) var remoteSnapshot: RemoteSnapshot?

    struct RecentPlayback: Equatable {
        let item: PlayableItem
        let seriesID: String?
        let title: String
        let positionSeconds: Double
        let durationSeconds: Double
        let played: Bool
        let updatedAt: Date

        var userState: UserPlaybackState {
            UserPlaybackState(
                played: played,
                positionSeconds: positionSeconds,
                progress: durationSeconds > 0 ? positionSeconds / durationSeconds : 0,
                lastPlayedAt: updatedAt
            )
        }
    }

    private(set) var recentPlayback: RecentPlayback?

    private struct ActivePlayback {
        let playbackID: UUID
        let item: PlayableItem
        let assetID: String
        let seriesID: String?
        let title: String
        var positionSeconds: Double
        var durationSeconds: Double

        func synchronizationSnapshot() -> PlaybackSynchronizationSnapshot {
            PlaybackSynchronizationSnapshot(
                playbackID: playbackID,
                update: PlaybackUpdate(
                    item: item,
                    assetID: assetID,
                    positionSeconds: positionSeconds,
                    seriesID: seriesID
                )
            )
        }
    }

    private struct EpisodeQueueCandidate {
        let item: PlayableItem
        let title: String
        let startPositionSeconds: Double
        let durationSeconds: Double
    }

    @ObservationIgnored private let provider: any MediaLibraryProvider
    @ObservationIgnored private let launcher: any PlaybackLaunching
    @ObservationIgnored private let progressSynchronizer: PlaybackProgressSynchronizer
    @ObservationIgnored private let eventSilenceInterval: Duration
    @ObservationIgnored private let progressSynchronizationInterval: Duration
    @ObservationIgnored private var activePlayback: ActivePlayback?
    @ObservationIgnored private var playbackSessionID: UUID?
    @ObservationIgnored private var playbackSeriesID: String?
    @ObservationIgnored private var previousEpisodes: [EpisodeQueueCandidate] = []
    @ObservationIgnored private var pendingEpisodes: [EpisodeQueueCandidate] = []
    @ObservationIgnored private var lastEndedPlaybackID: UUID?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var eventWatchdogTask: Task<Void, Never>?
    @ObservationIgnored private var queueDiscoveryTask: Task<Void, Never>?
    @ObservationIgnored private var terminalReportTask: Task<Void, Never>?
    @ObservationIgnored private var appRefreshTask: Task<Void, Never>?

    init(
        provider: any MediaLibraryProvider,
        launcher: any PlaybackLaunching,
        eventSilenceInterval: Duration = .seconds(4),
        progressSynchronizationInterval: Duration = .seconds(10)
    ) {
        self.provider = provider
        self.launcher = launcher
        self.progressSynchronizer = PlaybackProgressSynchronizer(provider: provider)
        self.eventSilenceInterval = eventSilenceInterval
        self.progressSynchronizationInterval = progressSynchronizationInterval
        let events = launcher.events
        self.eventTask = Task { @MainActor [weak self] in
            for await event in events {
                await self?.handle(event)
            }
        }
    }

    func assets(for item: PlayableItem) async throws -> [MediaAsset] {
        try await provider.assets(for: item)
    }

    func playFirst(
        item: PlayableItem,
        title: String,
        startPositionSeconds: Double = 0,
        seriesID: String? = nil
    ) async throws {
        guard let asset = try await assets(for: item).first else {
            throw ProviderError.notFound
        }
        try await play(
            item: item,
            asset: asset,
            title: title,
            startPositionSeconds: startPositionSeconds,
            seriesID: seriesID
        )
    }

    func playbackURL(for asset: MediaAsset) async throws -> URL {
        try await provider.playbackURL(for: asset)
    }

    func downloadURL(for asset: MediaAsset) async throws -> URL {
        try await provider.downloadURL(for: asset)
    }

    func play(
        item: PlayableItem,
        asset: MediaAsset,
        title: String,
        startPositionSeconds: Double = 0,
        seriesID: String? = nil
    ) async throws {
        try await launcher.prepare()
        if playbackSessionID != nil || activePlayback != nil {
            await stop()
        }
        let url = try await provider.playbackURL(for: asset)
        let descriptor = PlaybackDescriptor(
            url: url,
            title: title,
            startPositionSeconds: startPositionSeconds
        )
        activePlayback = ActivePlayback(
            playbackID: descriptor.id,
            item: item,
            assetID: asset.id,
            seriesID: seriesID,
            title: title,
            positionSeconds: descriptor.startPositionSeconds,
            durationSeconds: asset.durationSeconds ?? 0
        )
        playbackSessionID = descriptor.id
        playbackSeriesID = seriesID
        previousEpisodes = []
        pendingEpisodes = []
        lastEndedPlaybackID = nil
        remoteSnapshot = RemoteSnapshot(
            playbackID: descriptor.id,
            state: .paused,
            title: title,
            positionSeconds: descriptor.startPositionSeconds,
            durationSeconds: asset.durationSeconds ?? 0,
            speed: 1,
            volume: 0,
            muted: false,
            fullscreen: descriptor.startsInFullscreen,
            canPlayPrevious: false,
            canPlayNext: false,
            audioTracks: [],
            subtitleTracks: []
        )
        publishRemoteState()
        Self.logger.info(
            "Opening playback session=\(descriptor.id.uuidString, privacy: .public) continuation=\(seriesID != nil)"
        )
        do {
            try await launcher.open(descriptor)
        } catch {
            activePlayback = nil
            remoteSnapshot = nil
            publishRemoteState()
            clearContinuationState()
            throw error
        }
        if item.kind == .episode, let seriesID {
            discoverEpisodeQueue(
                seriesID: seriesID,
                afterEpisodeID: item.id,
                sessionID: descriptor.id
            )
        }
    }

    func send(_ command: PlaybackControlCommand) async throws {
        guard let sessionID = playbackSessionID else {
            throw PlaybackLaunchError.bridgeUnavailable
        }
        try await launcher.send(command, sessionID: sessionID)
    }

    func playNextEpisode() async throws {
        await queueDiscoveryTask?.value
        guard let sessionID = playbackSessionID,
              let activePlayback,
              pendingEpisodes.first != nil else {
            throw ProviderError.notFound
        }
        previousEpisodes.append(candidate(from: activePlayback))
        await finalizeActivePlayback()
        await replaceWithNextEpisode(afterSessionID: sessionID)
    }

    func playPreviousEpisode() async throws {
        await queueDiscoveryTask?.value
        guard let sessionID = playbackSessionID,
              let activePlayback,
              let candidate = previousEpisodes.popLast() else {
            throw ProviderError.notFound
        }
        pendingEpisodes.insert(self.candidate(from: activePlayback), at: 0)
        await finalizeActivePlayback()
        guard await replaceEpisode(candidate, afterSessionID: sessionID) else {
            throw PlaybackLaunchError.launchFailed
        }
        updateRemoteEpisodeAvailability()
    }

    func stop() async {
        queueDiscoveryTask?.cancel()
        if let sessionID = playbackSessionID {
            try? await launcher.send(.stop, sessionID: sessionID)
        }
        await finalizeActivePlayback()
        await terminalReportTask?.value
        terminalReportTask = nil
        clearContinuationState()
    }

    private func handle(_ event: PlaybackEvent) async {
        switch event {
        case .positionChanged(let playbackID, let positionSeconds, let durationSeconds):
            guard activePlayback?.playbackID == playbackID else { return }
            activePlayback?.positionSeconds = max(positionSeconds, 0)
            activePlayback?.durationSeconds = max(durationSeconds, 0)
            updateRemoteSnapshot(playbackID: playbackID) { snapshot in
                snapshot = RemoteSnapshot(
                    playbackID: snapshot.playbackID,
                    state: snapshot.state,
                    title: snapshot.title,
                    positionSeconds: max(positionSeconds, 0),
                    durationSeconds: max(durationSeconds, 0),
                    speed: snapshot.speed,
                    volume: snapshot.volume,
                    muted: snapshot.muted,
                    fullscreen: snapshot.fullscreen,
                    canPlayPrevious: snapshot.canPlayPrevious,
                    canPlayNext: snapshot.canPlayNext,
                    audioTracks: snapshot.audioTracks,
                    subtitleTracks: snapshot.subtitleTracks
                )
            }
            resetEventWatchdog(for: playbackID)
            scheduleProgressReport(for: playbackID)
        case .stateChanged(let playbackID, let snapshot):
            guard activePlayback?.playbackID == playbackID else { return }
            if snapshot.durationSeconds > 0 {
                activePlayback?.durationSeconds = snapshot.durationSeconds
            }
            updateRemoteSnapshot(playbackID: playbackID) { current in
                current = RemoteSnapshot(
                    playbackID: current.playbackID,
                    state: snapshot.state,
                    title: current.title,
                    positionSeconds: snapshot.positionSeconds,
                    durationSeconds: snapshot.durationSeconds,
                    speed: snapshot.speed,
                    volume: snapshot.volume,
                    muted: snapshot.muted,
                    fullscreen: snapshot.fullscreen,
                    canPlayPrevious: current.canPlayPrevious,
                    canPlayNext: current.canPlayNext,
                    audioTracks: current.audioTracks,
                    subtitleTracks: current.subtitleTracks
                )
            }
            resetEventWatchdog(for: playbackID)
            // mpv transitions through an idle/stopped snapshot immediately before
            // emitting end-file. Keep the playback active so the terminal event can
            // distinguish natural EOF from an explicit stop.
        case .ended(let playbackID, let reason):
            guard activePlayback?.playbackID == playbackID else {
                Self.logger.notice(
                    "Ignored terminal event for stale playback=\(playbackID.uuidString, privacy: .public) reason=\(reason, privacy: .public)"
                )
                return
            }
            Self.logger.info(
                "Received terminal event playback=\(playbackID.uuidString, privacy: .public) reason=\(reason, privacy: .public) pendingEpisodes=\(self.pendingEpisodes.count)"
            )
            let completedEpisode = activePlayback.map(candidate(from:))
            lastEndedPlaybackID = playbackID
            await finalizeActivePlayback(completed: reason == "eof")
            if reason == "eof" {
                if let completedEpisode, playbackSeriesID != nil {
                    previousEpisodes.append(completedEpisode)
                }
                Self.logger.info("Natural EOF confirmed; resolving replacement episode")
                await replaceWithNextEpisode(afterSessionID: playbackID)
            } else {
                Self.logger.notice(
                    "Playback ended without natural EOF; clearing sequential continuation"
                )
                clearContinuationState()
            }
        case .closed(let playbackID, _):
            guard activePlayback?.playbackID == playbackID
                    || lastEndedPlaybackID == playbackID else { return }
            if activePlayback?.playbackID == playbackID {
                await finalizeActivePlayback()
            }
            clearContinuationState()
        case .fileLoaded(let playbackID, let resumedAtSeconds):
            guard activePlayback?.playbackID == playbackID else {
                Self.logger.notice(
                    "Ignored file-loaded event for stale playback=\(playbackID.uuidString, privacy: .public)"
                )
                return
            }
            Self.logger.info(
                "Playback file loaded session=\(playbackID.uuidString, privacy: .public)"
            )
            activePlayback?.positionSeconds = max(resumedAtSeconds, 0)
            updateRemoteSnapshot(playbackID: playbackID) { snapshot in
                snapshot = RemoteSnapshot(
                    playbackID: snapshot.playbackID,
                    state: .playing,
                    title: snapshot.title,
                    positionSeconds: max(resumedAtSeconds, 0),
                    durationSeconds: snapshot.durationSeconds,
                    speed: snapshot.speed,
                    volume: snapshot.volume,
                    muted: snapshot.muted,
                    fullscreen: snapshot.fullscreen,
                    canPlayPrevious: snapshot.canPlayPrevious,
                    canPlayNext: snapshot.canPlayNext,
                    audioTracks: snapshot.audioTracks,
                    subtitleTracks: snapshot.subtitleTracks
                )
            }
            resetEventWatchdog(for: playbackID)
            await uploadProgress(for: playbackID)
        case .tracksChanged(let playbackID, let audio, let subtitles, _):
            updateRemoteSnapshot(playbackID: playbackID) { snapshot in
                snapshot = RemoteSnapshot(
                    playbackID: snapshot.playbackID,
                    state: snapshot.state,
                    title: snapshot.title,
                    positionSeconds: snapshot.positionSeconds,
                    durationSeconds: snapshot.durationSeconds,
                    speed: snapshot.speed,
                    volume: snapshot.volume,
                    muted: snapshot.muted,
                    fullscreen: snapshot.fullscreen,
                    canPlayPrevious: snapshot.canPlayPrevious,
                    canPlayNext: snapshot.canPlayNext,
                    audioTracks: audio,
                    subtitleTracks: subtitles
                )
            }
        case .bridgeReady,
             .bridgeError:
            break
        }
    }

    private func resetEventWatchdog(for playbackID: UUID) {
        eventWatchdogTask?.cancel()
        let eventSilenceInterval = eventSilenceInterval
        eventWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: eventSilenceInterval)
            guard !Task.isCancelled,
                  let self,
                  activePlayback?.playbackID == playbackID,
                  let sessionID = playbackSessionID else { return }
            do {
                try await launcher.send(.requestState, sessionID: sessionID)
            } catch {
                Self.logger.notice("IINA event stream probe failed")
            }
            try? await Task.sleep(for: eventSilenceInterval)
            guard !Task.isCancelled,
                  activePlayback?.playbackID == playbackID else { return }
            Self.logger.notice("IINA telemetry remains silent; preserving the active playback session")
        }
    }

    private func scheduleProgressReport(for playbackID: UUID) {
        guard progressTask == nil else { return }
        let interval = progressSynchronizationInterval
        progressTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await self?.flushProgress(for: playbackID)
        }
    }

    private func flushProgress(for playbackID: UUID) async {
        guard let activePlayback, activePlayback.playbackID == playbackID else {
            Self.logger.notice(
                "Ignored periodic progress flush for stale playback=\(playbackID.uuidString, privacy: .public)"
            )
            return
        }
        progressTask = nil
        await enqueueProgress(activePlayback.synchronizationSnapshot())
    }

    private func uploadProgress(for playbackID: UUID) async {
        guard let activePlayback, activePlayback.playbackID == playbackID else { return }
        await enqueueProgress(activePlayback.synchronizationSnapshot())
    }

    private func enqueueProgress(_ snapshot: PlaybackSynchronizationSnapshot) async {
        await progressSynchronizer.enqueueProgress(snapshot)
    }

    @discardableResult
    private func finalizeActivePlayback(completed: Bool = false) async -> ActivePlayback? {
        progressTask?.cancel()
        progressTask = nil
        eventWatchdogTask?.cancel()
        eventWatchdogTask = nil
        guard var playback = activePlayback else { return nil }
        if completed, playback.durationSeconds > 0 {
            playback.positionSeconds = playback.durationSeconds
        }
        activePlayback = nil
        remoteSnapshot = nil
        publishRemoteState()
        recentPlayback = RecentPlayback(
            item: playback.item,
            seriesID: playback.seriesID,
            title: playback.title,
            positionSeconds: playback.positionSeconds,
            durationSeconds: playback.durationSeconds,
            played: completed,
            updatedAt: Date()
        )
        let receipt = await progressSynchronizer.enqueueStopped(
            playback.synchronizationSnapshot()
        )
        let previous = terminalReportTask
        terminalReportTask = Task { @MainActor [weak self] in
            await previous?.value
            guard await receipt.value(), let self else { return }
            playbackStateRevision &+= 1
            Self.logger.info(
                "Applying synchronized playback state playback=\(playback.playbackID.uuidString, privacy: .public) revision=\(self.playbackStateRevision)"
            )
            let previousRefresh = appRefreshTask
            appRefreshTask = Task { @MainActor [weak self] in
                await previousRefresh?.value
                guard let self else { return }
                await onStoppedReported?()
                Self.logger.info(
                    "Finished App playback refresh playback=\(playback.playbackID.uuidString, privacy: .public) revision=\(self.playbackStateRevision)"
                )
            }
        }
        return playback
    }

    private func discoverEpisodeQueue(
        seriesID: String,
        afterEpisodeID: String,
        sessionID: UUID
    ) {
        queueDiscoveryTask?.cancel()
        queueDiscoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let episodes = try await episodeSequence(seriesID: seriesID)
                guard !Task.isCancelled, playbackSessionID == sessionID else { return }
                guard let currentIndex = episodes.firstIndex(where: {
                    $0.item.id == afterEpisodeID
                }) else {
                    previousEpisodes = []
                    pendingEpisodes = []
                    updateRemoteEpisodeAvailability()
                    return
                }
                previousEpisodes = Array(episodes[..<currentIndex])
                pendingEpisodes = Array(episodes.dropFirst(currentIndex + 1))
                updateRemoteEpisodeAvailability()
                Self.logger.info("Prepared sequential continuation with \(self.pendingEpisodes.count) remaining items")
            } catch is CancellationError {
                return
            } catch {
                Self.logger.error(
                    "Episode queue discovery failed with \(String(reflecting: type(of: error)), privacy: .public)"
                )
            }
        }
    }

    private func episodeSequence(seriesID: String) async throws -> [EpisodeQueueCandidate] {
        let seasons = try await provider.seasons(seriesID: seriesID)
            .sorted { lhs, rhs in
                if lhs.number != rhs.number { return lhs.number < rhs.number }
                return lhs.id < rhs.id
            }
        var episodes: [Episode] = []
        for season in seasons {
            var pageNumber = 1
            while true {
                try Task.checkCancellation()
                let page = try await provider.episodes(
                    seriesID: seriesID,
                    seasonID: season.id,
                    page: PageRequest(number: pageNumber, size: 100)
                )
                episodes.append(
                    contentsOf: page.items.sorted { lhs, rhs in
                        if lhs.number != rhs.number { return lhs.number < rhs.number }
                        return lhs.id < rhs.id
                    }
                )
                guard page.number * page.size < page.total, !page.items.isEmpty else { break }
                pageNumber += 1
            }
        }
        return episodes.map { episode in
            EpisodeQueueCandidate(
                item: PlayableItem(id: episode.id, kind: .episode),
                title: episode.title,
                startPositionSeconds: episode.userState.played
                    ? 0
                    : episode.userState.positionSeconds,
                durationSeconds: episode.durationSeconds ?? 0
            )
        }
    }

    private func replaceWithNextEpisode(afterSessionID sessionID: UUID) async {
        Self.logger.info(
            "Waiting for continuation metadata after session=\(sessionID.uuidString, privacy: .public)"
        )
        await queueDiscoveryTask?.value
        guard playbackSessionID == sessionID else {
            Self.logger.notice("Cancelled replacement because the playback session changed")
            return
        }
        guard activePlayback == nil else {
            Self.logger.notice("Cancelled replacement because another playback became active")
            return
        }
        guard let candidate = pendingEpisodes.first else {
            Self.logger.info("No remaining episode is available for automatic replacement")
            if playbackSessionID == sessionID {
                clearContinuationState()
            }
            return
        }
        if await replaceEpisode(candidate, afterSessionID: sessionID) {
            pendingEpisodes.removeFirst()
            updateRemoteEpisodeAvailability()
            Self.logger.info(
                "Advanced sequential playback; remainingCandidates=\(self.pendingEpisodes.count)"
            )
        }
    }

    private func replaceEpisode(
        _ candidate: EpisodeQueueCandidate,
        afterSessionID sessionID: UUID
    ) async -> Bool {
        do {
            Self.logger.info("Resolving replacement episode asset")
            guard let asset = try await provider.assets(for: candidate.item).first else {
                throw ProviderError.notFound
            }
            let url = try await provider.playbackURL(for: asset)
            guard !Task.isCancelled,
                  playbackSessionID == sessionID,
                  activePlayback == nil else { return false }
            do {
                try await launcher.send(.stop, sessionID: sessionID)
            } catch {
                Self.logger.notice("Outgoing session stop was unavailable before replacement")
            }
            guard !Task.isCancelled,
                  playbackSessionID == sessionID,
                  activePlayback == nil else { return false }
            let descriptor = PlaybackDescriptor(
                url: url,
                title: candidate.title,
                startPositionSeconds: candidate.startPositionSeconds
            )
            activePlayback = ActivePlayback(
                playbackID: descriptor.id,
                item: candidate.item,
                assetID: asset.id,
                seriesID: playbackSeriesID,
                title: candidate.title,
                positionSeconds: descriptor.startPositionSeconds,
                durationSeconds: asset.durationSeconds ?? candidate.durationSeconds
            )
            playbackSessionID = descriptor.id
            lastEndedPlaybackID = nil
            remoteSnapshot = RemoteSnapshot(
                playbackID: descriptor.id,
                state: .paused,
                title: candidate.title,
                positionSeconds: descriptor.startPositionSeconds,
                durationSeconds: asset.durationSeconds ?? candidate.durationSeconds,
                speed: 1,
                volume: 0,
                muted: false,
                fullscreen: descriptor.startsInFullscreen,
                canPlayPrevious: !previousEpisodes.isEmpty,
                canPlayNext: !pendingEpisodes.isEmpty,
                audioTracks: [],
                subtitleTracks: []
            )
            publishRemoteState()
            do {
                try await launcher.open(descriptor)
            } catch {
                activePlayback = nil
                remoteSnapshot = nil
                publishRemoteState()
                clearContinuationState()
                throw error
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            Self.logger.error(
                "Episode replacement failed with \(String(reflecting: type(of: error)), privacy: .public)"
            )
            return false
        }
    }

    private func clearContinuationState() {
        queueDiscoveryTask?.cancel()
        queueDiscoveryTask = nil
        playbackSessionID = nil
        playbackSeriesID = nil
        previousEpisodes = []
        pendingEpisodes = []
        lastEndedPlaybackID = nil
    }

    private func updateRemoteSnapshot(
        playbackID: UUID,
        _ update: (inout RemoteSnapshot) -> Void
    ) {
        guard var snapshot = remoteSnapshot,
              snapshot.playbackID == playbackID else { return }
        update(&snapshot)
        remoteSnapshot = snapshot
        publishRemoteState()
    }

    private func publishRemoteState() {
        remotePlaybackRevision &+= 1
        onRemoteStateChanged?()
    }

    private func candidate(from playback: ActivePlayback) -> EpisodeQueueCandidate {
        EpisodeQueueCandidate(
            item: playback.item,
            title: playback.title,
            startPositionSeconds: playback.positionSeconds,
            durationSeconds: playback.durationSeconds
        )
    }

    private func updateRemoteEpisodeAvailability() {
        guard let playbackID = activePlayback?.playbackID else { return }
        updateRemoteSnapshot(playbackID: playbackID) { snapshot in
            snapshot = RemoteSnapshot(
                playbackID: snapshot.playbackID,
                state: snapshot.state,
                title: snapshot.title,
                positionSeconds: snapshot.positionSeconds,
                durationSeconds: snapshot.durationSeconds,
                speed: snapshot.speed,
                volume: snapshot.volume,
                muted: snapshot.muted,
                fullscreen: snapshot.fullscreen,
                canPlayPrevious: !previousEpisodes.isEmpty,
                canPlayNext: !pendingEpisodes.isEmpty,
                audioTracks: snapshot.audioTracks,
                subtitleTracks: snapshot.subtitleTracks
            )
        }
    }
}

private struct PlaybackSynchronizationSnapshot: Sendable {
    let playbackID: UUID
    let update: PlaybackUpdate
}

private actor PlaybackSynchronizationReceipt {
    private var result: Bool?
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    func value() async -> Bool {
        if let result { return result }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func resolve(_ result: Bool) {
        guard self.result == nil else { return }
        self.result = result
        let pendingWaiters = waiters
        waiters = []
        for waiter in pendingWaiters {
            waiter.resume(returning: result)
        }
    }
}

private actor PlaybackProgressSynchronizer {
    private enum Operation {
        case progress(PlaybackSynchronizationSnapshot)
        case stopped(
            PlaybackSynchronizationSnapshot,
            PlaybackSynchronizationReceipt
        )
    }

    private static let logger = Logger(
        subsystem: "com.samsonlab.cinelark",
        category: "PlaybackSync"
    )
    private let provider: any MediaLibraryProvider
    private var operations: [Operation] = []
    private var workerTask: Task<Void, Never>?

    init(provider: any MediaLibraryProvider) {
        self.provider = provider
    }

    func enqueueProgress(_ snapshot: PlaybackSynchronizationSnapshot) {
        if case .progress(let queued)? = operations.last,
           queued.playbackID == snapshot.playbackID {
            operations[operations.count - 1] = .progress(snapshot)
            Self.logger.debug(
                "Coalesced pending progress playback=\(snapshot.playbackID.uuidString, privacy: .public)"
            )
        } else {
            operations.append(.progress(snapshot))
        }
        startWorkerIfNeeded()
    }

    func enqueueStopped(
        _ snapshot: PlaybackSynchronizationSnapshot
    ) -> PlaybackSynchronizationReceipt {
        let receipt = PlaybackSynchronizationReceipt()
        operations.append(.stopped(snapshot, receipt))
        Self.logger.info(
            "Reserved stopped synchronization playback=\(snapshot.playbackID.uuidString, privacy: .public) queuedOperations=\(self.operations.count)"
        )
        startWorkerIfNeeded()
        return receipt
    }

    private func startWorkerIfNeeded() {
        guard workerTask == nil else { return }
        workerTask = Task { [weak self] in
            await self?.drainOperations()
        }
    }

    private func drainOperations() async {
        while !operations.isEmpty {
            let operation = operations.removeFirst()
            switch operation {
            case .progress(let snapshot):
                await uploadProgress(snapshot)
            case .stopped(let snapshot, let receipt):
                let didUpload = await uploadStopped(snapshot)
                await receipt.resolve(didUpload)
            }
        }
        workerTask = nil
        if !operations.isEmpty {
            startWorkerIfNeeded()
        }
    }

    private func uploadProgress(_ snapshot: PlaybackSynchronizationSnapshot) async {
        do {
            _ = try await provider.reportProgress(snapshot.update)
            Self.logger.info(
                "Playback progress uploaded playback=\(snapshot.playbackID.uuidString, privacy: .public) position=\(snapshot.update.positionSeconds)"
            )
        } catch {
            Self.logger.error(
                "Playback progress upload failed playback=\(snapshot.playbackID.uuidString, privacy: .public)"
            )
        }
    }

    private func uploadStopped(_ snapshot: PlaybackSynchronizationSnapshot) async -> Bool {
        do {
            _ = try await provider.reportStopped(snapshot.update)
            Self.logger.info(
                "Stopped playback state uploaded playback=\(snapshot.playbackID.uuidString, privacy: .public) position=\(snapshot.update.positionSeconds)"
            )
            return true
        } catch {
            Self.logger.error(
                "Stopped playback state upload failed playback=\(snapshot.playbackID.uuidString, privacy: .public)"
            )
            return false
        }
    }
}
