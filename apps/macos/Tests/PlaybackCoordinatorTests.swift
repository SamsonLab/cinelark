import Foundation
import XCTest
import CineLarkDomain
import CineLarkPlayback
@testable import CineLark

@MainActor
final class PlaybackCoordinatorTests: XCTestCase {
    func testPreparationFailureDoesNotMintAPlaybackURL() async throws {
        let provider = PlaybackProviderStub(episodeCount: 1)
        let launcher = PlaybackLauncherSpy()
        launcher.preparationError = PlaybackLaunchError.pluginSetupRequiresIINAQuit
        let coordinator = PlaybackCoordinator(provider: provider, launcher: launcher)

        do {
            try await coordinator.playFirst(
                item: PlayableItem(id: "episode-1", kind: .episode),
                title: "Episode 1"
            )
            XCTFail("Expected player preparation to fail")
        } catch PlaybackLaunchError.pluginSetupRequiresIINAQuit {
            // Expected.
        }

        XCTAssertEqual(launcher.preparationCount, 1)
        let playbackURLRequestCount = await provider.playbackURLRequestCount()
        XCTAssertEqual(playbackURLRequestCount, 0)
    }

    func testRemoteCanMoveToNextAndPreviousEpisodes() async throws {
        let provider = PlaybackProviderStub(episodeCount: 3)
        let launcher = PlaybackLauncherSpy()
        let coordinator = PlaybackCoordinator(provider: provider, launcher: launcher)

        try await coordinator.playFirst(
            item: PlayableItem(id: "episode-1", kind: .episode),
            title: "Episode 1",
            seriesID: "series-1"
        )
        let queueReady = await eventually {
            coordinator.remoteSnapshot?.canPlayNext == true
        }
        XCTAssertTrue(queueReady)

        try await coordinator.playNextEpisode()
        XCTAssertEqual(launcher.opened.map(\.title), ["Episode 1", "Episode 2"])
        XCTAssertEqual(coordinator.remoteSnapshot?.canPlayPrevious, true)
        XCTAssertEqual(coordinator.remoteSnapshot?.canPlayNext, true)

        try await coordinator.playPreviousEpisode()
        XCTAssertEqual(
            launcher.opened.map(\.title),
            ["Episode 1", "Episode 2", "Episode 1"]
        )
        XCTAssertEqual(coordinator.remoteSnapshot?.canPlayPrevious, false)
        XCTAssertEqual(coordinator.remoteSnapshot?.canPlayNext, true)
    }

    func testNaturalEOFFullyReplacesContentWithoutEnqueueingFutureEpisodes() async throws {
        let provider = PlaybackProviderStub(episodeCount: 5)
        let launcher = PlaybackLauncherSpy()
        let coordinator = PlaybackCoordinator(
            provider: provider,
            launcher: launcher,
            eventSilenceInterval: .milliseconds(10)
        )

        let firstItem = PlayableItem(id: "episode-1", kind: .episode)
        try await coordinator.playFirst(
            item: firstItem,
            title: "Episode 1",
            seriesID: "series-1"
        )

        let firstPlaybackID = try XCTUnwrap(launcher.opened.first?.id)
        launcher.emit(.fileLoaded(playbackID: firstPlaybackID, resumedAtSeconds: 0))
        let firstProgressUploaded = await eventually {
            await provider.progressItemIDs().contains("episode-1")
        }
        XCTAssertTrue(firstProgressUploaded)
        let firstProgressCount = await provider.progressUpdates(for: "episode-1").count
        XCTAssertEqual(firstProgressCount, 1, "fileLoaded must upload exactly once")

        // Let both liveness intervals expire without returning a request-state
        // event. Sequential continuation must remain intact.
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(launcher.commands.contains { $0.command == .requestState })

        for episodeIndex in 0..<4 {
            let playbackID = launcher.opened[episodeIndex].id
            launcher.emit(
                .positionChanged(
                    playbackID: playbackID,
                    positionSeconds: 99.75,
                    durationSeconds: 100
                )
            )
            launcher.emit(.ended(playbackID: playbackID, reason: "eof"))

            let nextContentOpened = await eventually {
                launcher.opened.count == episodeIndex + 2
            }
            XCTAssertTrue(nextContentOpened)
            XCTAssertTrue(launcher.enqueued.isEmpty)
            XCTAssertTrue(
                launcher.commands.contains {
                    $0.command == .stop && $0.sessionID == playbackID
                },
                "Automatic replacement must match manual stop-then-play behavior"
            )

            let nextPlaybackID = launcher.opened[episodeIndex + 1].id
            launcher.emit(.fileLoaded(playbackID: nextPlaybackID, resumedAtSeconds: 0))
        }

        let laterTransitionsSynced = await eventually {
            let progress = await provider.progressItemIDs()
            let stopped = await provider.stoppedItemIDs()
            let stoppedPositions = await provider.stoppedPositions()
            return Set(progress).isSuperset(
                of: ["episode-1", "episode-2", "episode-3", "episode-4", "episode-5"]
            )
                && Set(stopped).isSuperset(
                    of: ["episode-1", "episode-2", "episode-3", "episode-4"]
                )
                && stoppedPositions.allSatisfy { $0 == 100 }
        }
        XCTAssertTrue(laterTransitionsSynced)
        XCTAssertEqual(
            launcher.opened.map(\.title),
            ["Episode 1", "Episode 2", "Episode 3", "Episode 4", "Episode 5"]
        )
        XCTAssertTrue(launcher.enqueued.isEmpty)
        XCTAssertEqual(
            launcher.commands.filter { $0.command == .stop }.map(\.sessionID),
            Array(launcher.opened.prefix(4).map(\.id))
        )

        let calls = await provider.synchronizationCalls()
        for episodeNumber in 1...4 {
            let currentID = "episode-\(episodeNumber)"
            let nextID = "episode-\(episodeNumber + 1)"
            let initialProgressIndex = try XCTUnwrap(
                calls.firstIndex { $0.isProgress(for: currentID) }
            )
            let stoppedIndex = try XCTUnwrap(
                calls.firstIndex { $0.isStopped(for: currentID) }
            )
            let nextProgressIndex = try XCTUnwrap(
                calls.firstIndex { $0.isProgress(for: nextID) }
            )
            XCTAssertLessThan(initialProgressIndex, stoppedIndex)
            XCTAssertLessThan(
                stoppedIndex,
                nextProgressIndex,
                "Outgoing stopped must be reserved before replacement progress"
            )
        }
        XCTAssertEqual(coordinator.recentPlayback?.positionSeconds, 100)
        XCTAssertEqual(coordinator.recentPlayback?.played, true)
    }

    func testStoppedFailureDoesNotAdvanceAppSynchronizationState() async throws {
        let provider = PlaybackProviderStub(episodeCount: 1)
        await provider.failNextStoppedReport()
        let launcher = PlaybackLauncherSpy()
        let coordinator = PlaybackCoordinator(provider: provider, launcher: launcher)
        let callback = PlaybackRefreshCallbackSpy()
        coordinator.onStoppedReported = {
            callback.record()
        }

        try await coordinator.playFirst(
            item: PlayableItem(id: "episode-1", kind: .episode),
            title: "Episode 1"
        )
        let playbackID = try XCTUnwrap(launcher.opened.first?.id)
        launcher.emit(.fileLoaded(playbackID: playbackID, resumedAtSeconds: 0))
        launcher.emit(
            .positionChanged(
                playbackID: playbackID,
                positionSeconds: 99.5,
                durationSeconds: 100
            )
        )
        launcher.emit(.ended(playbackID: playbackID, reason: "eof"))

        let stoppedAttempted = await eventually {
            await provider.stoppedAttemptCount() == 1
        }
        XCTAssertTrue(stoppedAttempted)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(coordinator.playbackStateRevision, 0)
        XCTAssertEqual(callback.count, 0)
        XCTAssertEqual(coordinator.recentPlayback?.positionSeconds, 100)
        XCTAssertEqual(coordinator.recentPlayback?.played, true)
    }

    func testCancelledEpisodeTimerCannotWriteIntoReplacementEpisode() async throws {
        let provider = PlaybackProviderStub(episodeCount: 2)
        let launcher = PlaybackLauncherSpy()
        let coordinator = PlaybackCoordinator(
            provider: provider,
            launcher: launcher,
            progressSynchronizationInterval: .milliseconds(40)
        )

        try await coordinator.playFirst(
            item: PlayableItem(id: "episode-1", kind: .episode),
            title: "Episode 1",
            seriesID: "series-1"
        )
        let firstPlaybackID = try XCTUnwrap(launcher.opened.first?.id)
        launcher.emit(.fileLoaded(playbackID: firstPlaybackID, resumedAtSeconds: 0))
        launcher.emit(
            .positionChanged(
                playbackID: firstPlaybackID,
                positionSeconds: 10,
                durationSeconds: 100
            )
        )
        launcher.emit(.ended(playbackID: firstPlaybackID, reason: "eof"))

        let replacementOpened = await eventually { launcher.opened.count == 2 }
        XCTAssertTrue(replacementOpened)
        let secondPlaybackID = launcher.opened[1].id
        launcher.emit(.fileLoaded(playbackID: secondPlaybackID, resumedAtSeconds: 0))
        launcher.emit(
            .positionChanged(
                playbackID: secondPlaybackID,
                positionSeconds: 25,
                durationSeconds: 100
            )
        )

        let replacementTimerUploaded = await eventually {
            await provider.progressUpdates(for: "episode-2").contains {
                $0.positionSeconds == 25
            }
        }
        XCTAssertTrue(replacementTimerUploaded)
        let replacementPositions = await provider.progressUpdates(for: "episode-2")
            .map(\.positionSeconds)
        XCTAssertEqual(replacementPositions, [0, 25])
    }

    func testSuccessfulStoppedSyncRefreshesContinueWatchingInApp() async throws {
        let provider = PlaybackProviderStub(episodeCount: 1)
        let launcher = PlaybackLauncherSpy()
        let model = AppModel(provider: provider, launcher: launcher)
        await model.bootstrap()
        XCTAssertTrue(model.continueWatching.isEmpty)

        try await model.playback.playFirst(
            item: PlayableItem(id: "episode-1", kind: .episode),
            title: "Episode 1"
        )
        let playbackID = try XCTUnwrap(launcher.opened.first?.id)
        launcher.emit(.fileLoaded(playbackID: playbackID, resumedAtSeconds: 0))
        launcher.emit(
            .positionChanged(
                playbackID: playbackID,
                positionSeconds: 42,
                durationSeconds: 100
            )
        )
        launcher.emit(.closed(playbackID: playbackID, reason: "window_closed"))

        let appRefreshed = await eventually {
            let shelfRequestCount = await provider.playbackShelfRequestCount()
            return model.continueWatching.first?.id == "episode-1"
                && shelfRequestCount >= 2
        }
        XCTAssertTrue(appRefreshed)
        XCTAssertEqual(model.continueWatching.first?.userState.positionSeconds, 42)
        XCTAssertEqual(model.playback.playbackStateRevision, 1)
    }

    func testSlowProgressUploadsCoalesceToLatestPendingPosition() async throws {
        let provider = PlaybackProviderStub(
            episodeCount: 1,
            progressReportDelay: .milliseconds(100)
        )
        let launcher = PlaybackLauncherSpy()
        let coordinator = PlaybackCoordinator(
            provider: provider,
            launcher: launcher,
            progressSynchronizationInterval: .milliseconds(8)
        )

        try await coordinator.playFirst(
            item: PlayableItem(id: "episode-1", kind: .episode),
            title: "Episode 1"
        )
        let playbackID = try XCTUnwrap(launcher.opened.first?.id)
        launcher.emit(.fileLoaded(playbackID: playbackID, resumedAtSeconds: 0))

        for position in 1...12 {
            launcher.emit(
                .positionChanged(
                    playbackID: playbackID,
                    positionSeconds: Double(position),
                    durationSeconds: 100
                )
            )
            try await Task.sleep(for: .milliseconds(10))
        }

        let latestPositionUploaded = await eventually {
            await provider.progressUpdates(for: "episode-1").last?.positionSeconds == 12
        }
        XCTAssertTrue(latestPositionUploaded)
        let uploadedPositions = await provider.progressUpdates(for: "episode-1")
            .map(\.positionSeconds)
        XCTAssertEqual(uploadedPositions.last, 12)
        XCTAssertLessThanOrEqual(
            uploadedPositions.count,
            4,
            "A slow provider must not create one queued write per timer tick"
        )
    }

    private func eventually(
        timeout: Duration = .seconds(2),
        _ condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }
}

@MainActor
private final class PlaybackRefreshCallbackSpy {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

@MainActor
private final class PlaybackLauncherSpy: PlaybackLaunching {
    struct EnqueuedItem {
        let descriptor: PlaybackDescriptor
        let sessionID: UUID
    }

    struct SentCommand {
        let command: PlaybackControlCommand
        let sessionID: UUID
    }

    let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    private(set) var opened: [PlaybackDescriptor] = []
    private(set) var enqueued: [EnqueuedItem] = []
    private(set) var commands: [SentCommand] = []
    private(set) var preparationCount = 0
    var preparationError: Error?

    init() {
        let pair = AsyncStream<PlaybackEvent>.makeStream()
        events = pair.stream
        continuation = pair.continuation
    }

    func prepare() async throws {
        preparationCount += 1
        if let preparationError { throw preparationError }
    }

    func open(_ descriptor: PlaybackDescriptor) async throws {
        opened.append(descriptor)
    }

    func enqueue(_ descriptor: PlaybackDescriptor, sessionID: UUID) async throws {
        enqueued.append(EnqueuedItem(descriptor: descriptor, sessionID: sessionID))
    }

    func send(_ command: PlaybackControlCommand, sessionID: UUID) async throws {
        commands.append(SentCommand(command: command, sessionID: sessionID))
    }

    func emit(_ event: PlaybackEvent) {
        continuation.yield(event)
    }
}

private enum PlaybackSynchronizationCall: Equatable {
    case progress(itemID: String, positionSeconds: Double)
    case stopped(itemID: String, positionSeconds: Double)

    func isProgress(for itemID: String) -> Bool {
        guard case .progress(let value, _) = self else { return false }
        return value == itemID
    }

    func isStopped(for itemID: String) -> Bool {
        guard case .stopped(let value, _) = self else { return false }
        return value == itemID
    }
}

private actor PlaybackProviderStub: MediaLibraryProvider {
    private let episodesValue: [Episode]
    private let progressReportDelay: Duration
    private var progressUpdates: [PlaybackUpdate] = []
    private var stoppedUpdates: [PlaybackUpdate] = []
    private var calls: [PlaybackSynchronizationCall] = []
    private var stoppedAttempts = 0
    private var shouldFailNextStoppedReport = false
    private var playbackShelfRequests = 0
    private var playbackURLRequests = 0

    init(
        episodeCount: Int,
        progressReportDelay: Duration = .zero
    ) {
        self.progressReportDelay = progressReportDelay
        let userState = UserPlaybackState(played: false, positionSeconds: 0, progress: 0)
        episodesValue = (1...episodeCount).map { number in
            Episode(
                id: "episode-\(number)",
                seriesID: "series-1",
                seasonID: "season-1",
                number: number,
                title: "Episode \(number)",
                synopsis: nil,
                airDate: nil,
                thumbnailURL: nil,
                durationSeconds: 100,
                hasMultipleVersions: false,
                userState: userState
            )
        }
    }

    func progressItemIDs() -> [String] {
        progressUpdates.map(\.item.id)
    }

    func progressUpdates(for itemID: String) -> [PlaybackUpdate] {
        progressUpdates.filter { $0.item.id == itemID }
    }

    func stoppedItemIDs() -> [String] {
        stoppedUpdates.map(\.item.id)
    }

    func stoppedPositions() -> [Double] {
        stoppedUpdates.map(\.positionSeconds)
    }

    func synchronizationCalls() -> [PlaybackSynchronizationCall] {
        calls
    }

    func stoppedAttemptCount() -> Int {
        stoppedAttempts
    }

    func failNextStoppedReport() {
        shouldFailNextStoppedReport = true
    }

    func playbackShelfRequestCount() -> Int {
        playbackShelfRequests
    }

    func seasons(seriesID: String) async throws -> [Season] {
        [
            Season(
                id: "season-1",
                seriesID: seriesID,
                number: 1,
                title: "Season 1",
                posterURL: nil,
                episodeCount: episodesValue.count,
                userState: UserPlaybackState(played: false, positionSeconds: 0, progress: 0)
            )
        ]
    }

    func episodes(
        seriesID: String,
        seasonID: String,
        page: PageRequest
    ) async throws -> Page<Episode> {
        Page(number: 1, size: page.size, total: episodesValue.count, items: episodesValue)
    }

    func assets(for item: PlayableItem) async throws -> [MediaAsset] {
        [
            MediaAsset(
                id: "asset-\(item.id)",
                mediaID: "series-1",
                episodeID: item.id,
                displayName: item.id,
                durationSeconds: 100,
                playPath: "/play/\(item.id)"
            )
        ]
    }

    func playbackURL(for asset: MediaAsset) async throws -> URL {
        playbackURLRequests += 1
        guard let url = URL(string: "https://media.invalid/\(asset.id)") else {
            throw ProviderError.invalidRequest
        }
        return url
    }

    func playbackURLRequestCount() -> Int {
        playbackURLRequests
    }

    func reportProgress(_ update: PlaybackUpdate) async throws -> UserPlaybackState {
        if progressReportDelay > .zero {
            try await Task.sleep(for: progressReportDelay)
        }
        calls.append(
            .progress(itemID: update.item.id, positionSeconds: update.positionSeconds)
        )
        progressUpdates.append(update)
        return playbackState(positionSeconds: update.positionSeconds)
    }

    func reportStopped(_ update: PlaybackUpdate) async throws -> UserPlaybackState {
        stoppedAttempts += 1
        calls.append(
            .stopped(itemID: update.item.id, positionSeconds: update.positionSeconds)
        )
        if shouldFailNextStoppedReport {
            shouldFailNextStoppedReport = false
            throw ProviderError.invalidRequest
        }
        stoppedUpdates.append(update)
        return playbackState(positionSeconds: update.positionSeconds)
    }

    private func playbackState(positionSeconds: Double) -> UserPlaybackState {
        UserPlaybackState(
            played: positionSeconds >= 100,
            positionSeconds: positionSeconds,
            progress: positionSeconds / 100
        )
    }

    func restoreSession() async throws -> ProviderSession? {
        ProviderSession(token: "test", expiresAt: .distantFuture)
    }
    func signIn(credentials: ProviderCredentials) async throws -> ProviderSession {
        throw ProviderError.unsupported
    }
    func signOut() async {}
    func hot(page: PageRequest) async throws -> Page<MediaSummary> {
        Page(number: page.number, size: page.size, total: 0, items: [])
    }
    func collections() async throws -> [MediaCollection] { [] }
    func items(
        in collectionID: String,
        page: PageRequest,
        sort: MediaSort?
    ) async throws -> Page<MediaSummary> { throw ProviderError.unsupported }
    func search(_ query: String, page: PageRequest) async throws -> Page<MediaSummary> {
        throw ProviderError.unsupported
    }
    func detail(for item: MediaSummary) async throws -> MediaDetail { throw ProviderError.unsupported }
    func person(id: String) async throws -> PersonDetail { throw ProviderError.unsupported }
    func works(
        forPersonID personID: String,
        page: PageRequest,
        sort: MediaSort?
    ) async throws -> Page<MediaSummary> { throw ProviderError.unsupported }
    func favoriteMedia(kind: MediaKind, page: PageRequest) async throws -> Page<MediaSummary> {
        throw ProviderError.unsupported
    }
    func favoritePeople(page: PageRequest) async throws -> Page<PersonDetail> {
        throw ProviderError.unsupported
    }
    func setFavorite(_ isFavorite: Bool, target: FavoriteTarget) async throws -> Bool {
        throw ProviderError.unsupported
    }
    func downloadURL(for asset: MediaAsset) async throws -> URL { throw ProviderError.unsupported }
    func playbackShelf(limit: Int) async throws -> PlaybackShelf {
        playbackShelfRequests += 1
        guard let update = stoppedUpdates.last else {
            return PlaybackShelf(resume: [], nextUp: [])
        }
        let state = playbackState(positionSeconds: update.positionSeconds)
        let item = ContinueWatchingItem(
            id: update.item.id,
            item: update.item,
            mediaID: update.seriesID ?? update.item.id,
            title: update.item.id,
            subtitle: nil,
            posterURL: nil,
            thumbnailURL: nil,
            durationSeconds: 100,
            userState: state
        )
        return PlaybackShelf(resume: [item], nextUp: [])
    }
    func playbackState(seriesID: String) async throws -> SeriesPlaybackState {
        throw ProviderError.unsupported
    }
}
