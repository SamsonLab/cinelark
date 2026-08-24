import Foundation
import Observation
import OSLog
import CineLarkDomain
import CineLarkPlayback

@Observable
@MainActor
final class PlaybackCoordinator {
    private static let futureQueueDepth = 2
    private static let logger = Logger(
        subsystem: "com.samsonlab.cinelark",
        category: "Playback"
    )

    var onStoppedReported: (@MainActor @Sendable () -> Void)?
    private(set) var playbackStateRevision = 0

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
    }

    private struct EpisodeQueueCandidate {
        let item: PlayableItem
        let title: String
        let startPositionSeconds: Double
        let durationSeconds: Double
    }

    @ObservationIgnored private let provider: any MediaLibraryProvider
    @ObservationIgnored private let launcher: any PlaybackLaunching
    @ObservationIgnored private let progressReporter: PlaybackProgressReporter
    @ObservationIgnored private var activePlayback: ActivePlayback?
    @ObservationIgnored private var playbackSessionID: UUID?
    @ObservationIgnored private var playbackSeriesID: String?
    @ObservationIgnored private var queuedPlaybacks: [UUID: ActivePlayback] = [:]
    @ObservationIgnored private var pendingEpisodes: [EpisodeQueueCandidate] = []
    @ObservationIgnored private var lastEndedPlaybackID: UUID?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var eventWatchdogTask: Task<Void, Never>?
    @ObservationIgnored private var queueDiscoveryTask: Task<Void, Never>?
    @ObservationIgnored private var queueFillTask: Task<Void, Never>?
    @ObservationIgnored private var terminalReportTask: Task<Void, Never>?

    init(provider: any MediaLibraryProvider, launcher: any PlaybackLaunching) {
        self.provider = provider
        self.launcher = launcher
        self.progressReporter = PlaybackProgressReporter(provider: provider)
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
        lastEndedPlaybackID = nil
        do {
            try await launcher.open(descriptor)
        } catch {
            activePlayback = nil
            clearQueueState()
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

    func stop() async {
        queueDiscoveryTask?.cancel()
        queueFillTask?.cancel()
        if let sessionID = playbackSessionID {
            try? await launcher.send(.stop, sessionID: sessionID)
        }
        finalizeActivePlayback()
        await terminalReportTask?.value
        terminalReportTask = nil
        clearQueueState()
    }

    private func handle(_ event: PlaybackEvent) async {
        switch event {
        case .positionChanged(let playbackID, let positionSeconds, let durationSeconds):
            guard activePlayback?.playbackID == playbackID else { return }
            activePlayback?.positionSeconds = max(positionSeconds, 0)
            activePlayback?.durationSeconds = max(durationSeconds, 0)
            resetEventWatchdog(for: playbackID)
            scheduleProgressReport()
        case .stateChanged(let playbackID, let snapshot):
            guard activePlayback?.playbackID == playbackID else { return }
            if snapshot.durationSeconds > 0 {
                activePlayback?.durationSeconds = snapshot.durationSeconds
            }
            resetEventWatchdog(for: playbackID)
            // mpv transitions through an idle/stopped snapshot immediately before
            // emitting end-file. Keep the playback active so the terminal event can
            // distinguish natural EOF from an explicit stop.
        case .ended(let playbackID, let reason):
            guard activePlayback?.playbackID == playbackID else { return }
            lastEndedPlaybackID = playbackID
            finalizeActivePlayback(completed: reason == "eof")
            if reason != "eof" {
                clearQueueState()
            }
        case .closed(let playbackID, _):
            guard activePlayback?.playbackID == playbackID
                    || lastEndedPlaybackID == playbackID
                    || queuedPlaybacks[playbackID] != nil else { return }
            if activePlayback?.playbackID == playbackID {
                finalizeActivePlayback()
            }
            clearQueueState()
        case .fileLoaded(let playbackID, _):
            if activePlayback?.playbackID != playbackID {
                guard let queuedPlayback = queuedPlaybacks.removeValue(forKey: playbackID) else {
                    return
                }
                activePlayback = queuedPlayback
                lastEndedPlaybackID = nil
            }
            resetEventWatchdog(for: playbackID)
            scheduleQueueFill()
        case .bridgeReady,
             .tracksChanged,
             .bridgeError:
            break
        }
    }

    private func resetEventWatchdog(for playbackID: UUID) {
        eventWatchdogTask?.cancel()
        eventWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled,
                  let self,
                  activePlayback?.playbackID == playbackID,
                  let sessionID = playbackSessionID else { return }
            do {
                try await launcher.send(.requestState, sessionID: sessionID)
            } catch {
                Self.logger.notice("IINA event stream probe failed")
            }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled,
                  activePlayback?.playbackID == playbackID else { return }
            Self.logger.notice("IINA event stream stopped; finalizing the last sampled position")
            finalizeActivePlayback()
            clearQueueState()
        }
    }

    private func scheduleProgressReport() {
        guard progressTask == nil else { return }
        progressTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            await self?.flushProgress()
        }
    }

    private func flushProgress() async {
        progressTask = nil
        guard let activePlayback else { return }
        let update = PlaybackUpdate(
            item: activePlayback.item,
            assetID: activePlayback.assetID,
            positionSeconds: activePlayback.positionSeconds,
            seriesID: activePlayback.seriesID
        )
        await progressReporter.reportProgress(update)
    }

    @discardableResult
    private func finalizeActivePlayback(completed: Bool = false) -> ActivePlayback? {
        progressTask?.cancel()
        progressTask = nil
        eventWatchdogTask?.cancel()
        eventWatchdogTask = nil
        guard let activePlayback else { return nil }
        self.activePlayback = nil
        recentPlayback = RecentPlayback(
            item: activePlayback.item,
            seriesID: activePlayback.seriesID,
            title: activePlayback.title,
            positionSeconds: activePlayback.positionSeconds,
            durationSeconds: activePlayback.durationSeconds,
            played: completed,
            updatedAt: Date()
        )
        let previous = terminalReportTask
        terminalReportTask = Task { @MainActor [weak self] in
            await previous?.value
            await self?.reportStopped(activePlayback)
        }
        return activePlayback
    }

    private func reportStopped(_ playback: ActivePlayback) async {
        let update = PlaybackUpdate(
            item: playback.item,
            assetID: playback.assetID,
            positionSeconds: playback.positionSeconds,
            seriesID: playback.seriesID
        )
        do {
            try await progressReporter.reportStopped(update)
            Self.logger.info("Stopped playback state reported successfully")
        } catch {
            Self.logger.error("Stopped playback state report failed")
        }
        playbackStateRevision &+= 1
        onStoppedReported?()
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
                let episodes = try await remainingEpisodes(
                    seriesID: seriesID,
                    afterEpisodeID: afterEpisodeID
                )
                guard !Task.isCancelled, playbackSessionID == sessionID else { return }
                pendingEpisodes = episodes
                Self.logger.info("Prepared logical episode queue with \(episodes.count) remaining items")
                scheduleQueueFill()
            } catch is CancellationError {
                return
            } catch {
                Self.logger.error(
                    "Episode queue discovery failed with \(String(reflecting: type(of: error)), privacy: .public)"
                )
            }
        }
    }

    private func remainingEpisodes(
        seriesID: String,
        afterEpisodeID: String
    ) async throws -> [EpisodeQueueCandidate] {
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
        guard let currentIndex = episodes.firstIndex(where: { $0.id == afterEpisodeID }) else {
            return []
        }
        return episodes.suffix(from: episodes.index(after: currentIndex)).map { episode in
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

    private func scheduleQueueFill() {
        guard queueFillTask == nil,
              let sessionID = playbackSessionID,
              queuedPlaybacks.count < Self.futureQueueDepth,
              !pendingEpisodes.isEmpty else { return }
        queueFillTask = Task { @MainActor [weak self] in
            await self?.fillQueue()
            guard self?.playbackSessionID == sessionID else { return }
            self?.queueFillTask = nil
        }
    }

    private func fillQueue() async {
        guard let sessionID = playbackSessionID else { return }
        while queuedPlaybacks.count < Self.futureQueueDepth,
              let candidate = pendingEpisodes.first {
            do {
                guard let asset = try await provider.assets(for: candidate.item).first else {
                    throw ProviderError.notFound
                }
                let url = try await provider.playbackURL(for: asset)
                guard !Task.isCancelled, playbackSessionID == sessionID else { return }
                let descriptor = PlaybackDescriptor(
                    url: url,
                    title: candidate.title,
                    startPositionSeconds: candidate.startPositionSeconds
                )
                try await launcher.enqueue(descriptor, sessionID: sessionID)
                guard !Task.isCancelled, playbackSessionID == sessionID else { return }
                pendingEpisodes.removeFirst()
                queuedPlaybacks[descriptor.id] = ActivePlayback(
                    playbackID: descriptor.id,
                    item: candidate.item,
                    assetID: asset.id,
                    seriesID: playbackSeriesID,
                    title: candidate.title,
                    positionSeconds: descriptor.startPositionSeconds,
                    durationSeconds: asset.durationSeconds ?? candidate.durationSeconds
                )
                Self.logger.info(
                    "Enqueued future episode; \(self.queuedPlaybacks.count) items ready"
                )
            } catch is CancellationError {
                return
            } catch {
                Self.logger.error(
                    "Episode queue refill failed with \(String(reflecting: type(of: error)), privacy: .public)"
                )
                return
            }
        }
    }

    private func clearQueueState() {
        queueDiscoveryTask?.cancel()
        queueDiscoveryTask = nil
        queueFillTask?.cancel()
        queueFillTask = nil
        playbackSessionID = nil
        playbackSeriesID = nil
        queuedPlaybacks = [:]
        pendingEpisodes = []
        lastEndedPlaybackID = nil
    }
}

private actor PlaybackProgressReporter {
    private let provider: any MediaLibraryProvider
    private var tail: Task<Void, Never>?

    init(provider: any MediaLibraryProvider) {
        self.provider = provider
    }

    func reportProgress(_ update: PlaybackUpdate) {
        enqueueProgress(update)
    }

    func reportStopped(_ update: PlaybackUpdate) async throws {
        let previous = tail
        let provider = provider
        let reportingTask = Task {
            await previous?.value
            return try await provider.reportStopped(update)
        }
        tail = Task {
            _ = try? await reportingTask.value
        }
        _ = try await reportingTask.value
    }

    private func enqueueProgress(_ update: PlaybackUpdate) {
        let previous = tail
        let provider = provider
        let task = Task {
            await previous?.value
            _ = try? await provider.reportProgress(update)
        }
        tail = task
    }
}
