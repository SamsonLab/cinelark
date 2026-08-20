import Foundation
import Testing
import CineLarkDomain
@testable import CineLarkPersistence

@Suite("Cached media library provider")
struct CachedMediaLibraryProviderTests {
    @Test("fresh metadata is reused across provider and cache instances")
    func freshMetadataIsReused() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let page = samplePage()
        let firstUpstream = StubProvider(hotBehavior: .value(page))
        let firstProvider = makeProvider(
            upstream: firstUpstream,
            cache: PersistentMetadataCache(directory: directory, now: { date }),
            date: date
        )

        let first = try await firstProvider.hot(page: PageRequest(number: 1, size: 20))
        let second = try await firstProvider.hot(page: PageRequest(number: 1, size: 20))
        #expect(first.items.first?.title == "Synthetic Movie")
        #expect(second.items.first?.title == "Synthetic Movie")
        #expect(await firstUpstream.hotRequestCount() == 1)

        let offlineUpstream = StubProvider(hotBehavior: .unavailable)
        let restoredProvider = makeProvider(
            upstream: offlineUpstream,
            cache: PersistentMetadataCache(directory: directory, now: { date }),
            date: date
        )
        let restored = try await restoredProvider.hot(page: PageRequest(number: 1, size: 20))
        #expect(restored.items.first?.id == "movie-1")
        #expect(await offlineUpstream.hotRequestCount() == 0)
    }

    @Test("stale metadata is used for outages but never authentication failures")
    func staleFallbackIsBoundedByFailureType() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let writer = makeProvider(
            upstream: StubProvider(hotBehavior: .value(samplePage())),
            cache: PersistentMetadataCache(directory: directory, now: { storedAt }),
            date: storedAt,
            hotTimeToLive: 60
        )
        _ = try await writer.hot(page: PageRequest(number: 1, size: 20))

        let staleDate = storedAt.addingTimeInterval(120)
        let unavailableProvider = makeProvider(
            upstream: StubProvider(hotBehavior: .unavailable),
            cache: PersistentMetadataCache(directory: directory, now: { staleDate }),
            date: staleDate,
            hotTimeToLive: 60
        )
        let fallback = try await unavailableProvider.hot(page: PageRequest(number: 1, size: 20))
        #expect(fallback.items.first?.id == "movie-1")

        let unauthorizedProvider = makeProvider(
            upstream: StubProvider(hotBehavior: .sessionExpired),
            cache: PersistentMetadataCache(directory: directory, now: { staleDate }),
            date: staleDate,
            hotTimeToLive: 60
        )
        do {
            _ = try await unauthorizedProvider.hot(page: PageRequest(number: 1, size: 20))
            Issue.record("Expected the authentication failure to bypass stale metadata.")
        } catch let error as ProviderError {
            #expect(error == .sessionExpired)
        }
    }

    @Test("sign out removes account-scoped metadata")
    func signOutClearsMetadata() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let cache = PersistentMetadataCache(directory: directory, now: { date })
        let provider = makeProvider(
            upstream: StubProvider(hotBehavior: .value(samplePage())),
            cache: cache,
            date: date
        )

        _ = try await provider.hot(page: PageRequest(number: 1, size: 20))
        #expect(try await cache.performMaintenance().entryCount == 1)
        await provider.signOut()
        #expect(try await cache.performMaintenance().entryCount == 0)
    }

    private func makeProvider(
        upstream: StubProvider,
        cache: PersistentMetadataCache,
        date: Date,
        hotTimeToLive: TimeInterval = 600
    ) -> CachedMediaLibraryProvider {
        CachedMediaLibraryProvider(
            upstream: upstream,
            cache: cache,
            namespace: "synthetic-provider-v1",
            policy: MediaMetadataCachePolicy(hotTimeToLive: hotTimeToLive),
            now: { date }
        )
    }

    private func samplePage() -> Page<MediaSummary> {
        Page(
            number: 1,
            size: 20,
            total: 1,
            items: [
                MediaSummary(
                    id: "movie-1",
                    kind: .movie,
                    title: "Synthetic Movie"
                )
            ]
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cinelark-provider-cache-tests-\(UUID().uuidString)", isDirectory: true)
    }
}

private actor StubProvider: MediaLibraryProvider {
    enum HotBehavior: Sendable {
        case value(Page<MediaSummary>)
        case unavailable
        case sessionExpired
    }

    private let hotBehavior: HotBehavior
    private var hotRequests = 0

    init(hotBehavior: HotBehavior) {
        self.hotBehavior = hotBehavior
    }

    func hotRequestCount() -> Int {
        hotRequests
    }

    func restoreSession() async throws -> ProviderSession? {
        nil
    }

    func signIn(credentials: ProviderCredentials) async throws -> ProviderSession {
        throw ProviderError.unsupported
    }

    func signOut() async {}

    func hot(page: PageRequest) async throws -> Page<MediaSummary> {
        hotRequests += 1
        switch hotBehavior {
        case .value(let page):
            return page
        case .unavailable:
            throw ProviderError.unavailable
        case .sessionExpired:
            throw ProviderError.sessionExpired
        }
    }

    func collections() async throws -> [MediaCollection] {
        throw ProviderError.unsupported
    }

    func items(
        in collectionID: String,
        page: PageRequest,
        sort: MediaSort?
    ) async throws -> Page<MediaSummary> {
        throw ProviderError.unsupported
    }

    func search(_ query: String, page: PageRequest) async throws -> Page<MediaSummary> {
        throw ProviderError.unsupported
    }

    func detail(for item: MediaSummary) async throws -> MediaDetail {
        throw ProviderError.unsupported
    }

    func seasons(seriesID: String) async throws -> [Season] {
        throw ProviderError.unsupported
    }

    func episodes(
        seriesID: String,
        seasonID: String,
        page: PageRequest
    ) async throws -> Page<Episode> {
        throw ProviderError.unsupported
    }

    func person(id: String) async throws -> PersonDetail {
        throw ProviderError.unsupported
    }

    func works(
        forPersonID personID: String,
        page: PageRequest,
        sort: MediaSort?
    ) async throws -> Page<MediaSummary> {
        throw ProviderError.unsupported
    }

    func favoriteMedia(
        kind: MediaKind,
        page: PageRequest
    ) async throws -> Page<MediaSummary> {
        throw ProviderError.unsupported
    }

    func favoritePeople(page: PageRequest) async throws -> Page<PersonDetail> {
        throw ProviderError.unsupported
    }

    func setFavorite(_ isFavorite: Bool, target: FavoriteTarget) async throws -> Bool {
        throw ProviderError.unsupported
    }

    func assets(for item: PlayableItem) async throws -> [MediaAsset] {
        throw ProviderError.unsupported
    }

    func playbackURL(for asset: MediaAsset) async throws -> URL {
        throw ProviderError.unsupported
    }

    func playbackShelf(limit: Int) async throws -> PlaybackShelf {
        throw ProviderError.unsupported
    }

    func reportProgress(_ update: PlaybackUpdate) async throws -> UserPlaybackState {
        throw ProviderError.unsupported
    }

    func reportStopped(_ update: PlaybackUpdate) async throws -> UserPlaybackState {
        throw ProviderError.unsupported
    }
}
