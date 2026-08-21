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

    var onStoppedReported: (@MainActor @Sendable () -> Void)?
    private(set) var playbackStateRevision = 0

    private struct ActivePlayback {
        let playbackID: UUID
        let item: PlayableItem
        let assetID: String
        let seriesID: String?
        var positionSeconds: Double
        var durationSeconds: Double
    }

    @ObservationIgnored private let provider: any MediaLibraryProvider
    @ObservationIgnored private let launcher: any PlaybackLaunching
    @ObservationIgnored private let progressReporter: PlaybackProgressReporter
    @ObservationIgnored private var activePlayback: ActivePlayback?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

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
        if activePlayback != nil {
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
            positionSeconds: descriptor.startPositionSeconds,
            durationSeconds: asset.durationSeconds ?? 0
        )
        do {
            try await launcher.open(descriptor)
        } catch {
            activePlayback = nil
            throw error
        }
    }

    func send(_ command: PlaybackControlCommand) async throws {
        guard let playbackID = activePlayback?.playbackID else {
            throw PlaybackLaunchError.bridgeUnavailable
        }
        try await launcher.send(command, playbackID: playbackID)
    }

    func stop() async {
        if let playbackID = activePlayback?.playbackID {
            try? await launcher.send(.stop, playbackID: playbackID)
        }
        await finalizeActivePlayback()
    }

    private func handle(_ event: PlaybackEvent) async {
        switch event {
        case .positionChanged(let playbackID, let positionSeconds, let durationSeconds):
            guard activePlayback?.playbackID == playbackID else { return }
            activePlayback?.positionSeconds = max(positionSeconds, 0)
            activePlayback?.durationSeconds = max(durationSeconds, 0)
            scheduleProgressReport()
        case .stateChanged(let playbackID, let snapshot):
            guard activePlayback?.playbackID == playbackID else { return }
            activePlayback?.positionSeconds = snapshot.positionSeconds
            activePlayback?.durationSeconds = snapshot.durationSeconds
            // mpv transitions through an idle/stopped snapshot immediately before
            // emitting end-file. Keep the playback active so the terminal event can
            // distinguish natural EOF from an explicit stop.
        case .ended(let playbackID, let reason):
            guard activePlayback?.playbackID == playbackID else { return }
            if let completedPlayback = await finalizeActivePlayback(),
               reason == "eof" {
                await playNextEpisode(after: completedPlayback)
            }
        case .closed(let playbackID, _):
            guard activePlayback?.playbackID == playbackID else { return }
            await finalizeActivePlayback()
        case .bridgeReady,
             .fileLoaded,
             .tracksChanged,
             .bridgeError:
            break
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
    private func finalizeActivePlayback() async -> ActivePlayback? {
        progressTask?.cancel()
        progressTask = nil
        guard let activePlayback else { return nil }
        self.activePlayback = nil
        let update = PlaybackUpdate(
            item: activePlayback.item,
            assetID: activePlayback.assetID,
            positionSeconds: activePlayback.positionSeconds,
            seriesID: activePlayback.seriesID
        )
        do {
            try await progressReporter.reportStopped(update)
            Self.logger.info("Stopped playback state reported successfully")
        } catch {
            Self.logger.error("Stopped playback state report failed")
        }
        playbackStateRevision &+= 1
        onStoppedReported?()
        return activePlayback
    }

    private func playNextEpisode(after completedPlayback: ActivePlayback) async {
        guard let seriesID = completedPlayback.seriesID else { return }
        do {
            let state = try await provider.playbackState(seriesID: seriesID)
            guard let nextEpisode = state.nextUp,
                  nextEpisode.item.id != completedPlayback.item.id else {
                Self.logger.info("Automatic next episode unavailable")
                return
            }
            Self.logger.info("Starting automatic next episode")
            try await playFirst(
                item: nextEpisode.item,
                title: nextEpisode.title,
                startPositionSeconds: nextEpisode.userState.positionSeconds,
                seriesID: seriesID
            )
        } catch {
            Self.logger.error(
                "Automatic next episode failed with \(String(reflecting: type(of: error)), privacy: .public)"
            )
        }
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
