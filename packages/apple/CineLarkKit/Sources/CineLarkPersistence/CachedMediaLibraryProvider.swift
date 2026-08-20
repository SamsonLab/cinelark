import Foundation
import CineLarkDomain

public struct MediaMetadataCachePolicy: Sendable, Equatable {
    public let hotTimeToLive: TimeInterval
    public let collectionsTimeToLive: TimeInterval
    public let collectionItemsTimeToLive: TimeInterval
    public let searchTimeToLive: TimeInterval
    public let detailTimeToLive: TimeInterval
    public let seasonsTimeToLive: TimeInterval
    public let episodesTimeToLive: TimeInterval
    public let personTimeToLive: TimeInterval
    public let personWorksTimeToLive: TimeInterval
    public let favoritesTimeToLive: TimeInterval
    public let assetsTimeToLive: TimeInterval
    public let playbackShelfTimeToLive: TimeInterval

    public init(
        hotTimeToLive: TimeInterval = 15 * 60,
        collectionsTimeToLive: TimeInterval = 6 * 60 * 60,
        collectionItemsTimeToLive: TimeInterval = 60 * 60,
        searchTimeToLive: TimeInterval = 10 * 60,
        detailTimeToLive: TimeInterval = 24 * 60 * 60,
        seasonsTimeToLive: TimeInterval = 6 * 60 * 60,
        episodesTimeToLive: TimeInterval = 60 * 60,
        personTimeToLive: TimeInterval = 24 * 60 * 60,
        personWorksTimeToLive: TimeInterval = 6 * 60 * 60,
        favoritesTimeToLive: TimeInterval = 60,
        assetsTimeToLive: TimeInterval = 60 * 60,
        playbackShelfTimeToLive: TimeInterval = 60
    ) {
        self.hotTimeToLive = max(hotTimeToLive, 0)
        self.collectionsTimeToLive = max(collectionsTimeToLive, 0)
        self.collectionItemsTimeToLive = max(collectionItemsTimeToLive, 0)
        self.searchTimeToLive = max(searchTimeToLive, 0)
        self.detailTimeToLive = max(detailTimeToLive, 0)
        self.seasonsTimeToLive = max(seasonsTimeToLive, 0)
        self.episodesTimeToLive = max(episodesTimeToLive, 0)
        self.personTimeToLive = max(personTimeToLive, 0)
        self.personWorksTimeToLive = max(personWorksTimeToLive, 0)
        self.favoritesTimeToLive = max(favoritesTimeToLive, 0)
        self.assetsTimeToLive = max(assetsTimeToLive, 0)
        self.playbackShelfTimeToLive = max(playbackShelfTimeToLive, 0)
    }

    public static let `default` = MediaMetadataCachePolicy()
}

public struct CachedMediaLibraryProvider: MediaLibraryProvider, Sendable {
    private let upstream: any MediaLibraryProvider
    private let cache: any MetadataCaching
    private let namespace: String
    private let policy: MediaMetadataCachePolicy
    private let now: @Sendable () -> Date

    public init(
        upstream: any MediaLibraryProvider,
        cache: any MetadataCaching,
        namespace: String,
        policy: MediaMetadataCachePolicy = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.upstream = upstream
        self.cache = cache
        self.namespace = namespace
        self.policy = policy
        self.now = now
    }

    public func restoreSession() async throws -> ProviderSession? {
        _ = try? await cache.performMaintenance()
        let session = try await upstream.restoreSession()
        if session == nil {
            try await cache.removeAll()
        }
        return session
    }

    public func signIn(credentials: ProviderCredentials) async throws -> ProviderSession {
        try await cache.removeAll()
        return try await upstream.signIn(credentials: credentials)
    }

    public func signOut() async {
        await upstream.signOut()
        try? await cache.removeAll()
    }

    public func hot(page: PageRequest) async throws -> Page<MediaSummary> {
        try await cached(
            resource: "hot",
            components: [String(page.number), String(page.size)],
            timeToLive: policy.hotTimeToLive
        ) {
            try await upstream.hot(page: page)
        }
    }

    public func collections() async throws -> [MediaCollection] {
        try await cached(
            resource: "collections",
            timeToLive: policy.collectionsTimeToLive
        ) {
            try await upstream.collections()
        }
    }

    public func items(
        in collectionID: String,
        page: PageRequest,
        sort: MediaSort?
    ) async throws -> Page<MediaSummary> {
        try await cached(
            resource: "collection-items",
            components: [
                collectionID,
                String(page.number),
                String(page.size),
                sort?.field.rawValue ?? "",
                sort?.order.rawValue ?? ""
            ],
            timeToLive: policy.collectionItemsTimeToLive,
            tags: [tag("collection", collectionID)]
        ) {
            try await upstream.items(in: collectionID, page: page, sort: sort)
        }
    }

    public func search(_ query: String, page: PageRequest) async throws -> Page<MediaSummary> {
        try await cached(
            resource: "search",
            components: [query, String(page.number), String(page.size)],
            timeToLive: policy.searchTimeToLive
        ) {
            try await upstream.search(query, page: page)
        }
    }

    public func detail(for item: MediaSummary) async throws -> MediaDetail {
        try await cached(
            resource: "detail",
            components: [item.kind.rawValue, item.id],
            timeToLive: policy.detailTimeToLive,
            tags: [mediaTag(id: item.id)]
        ) {
            try await upstream.detail(for: item)
        }
    }

    public func seasons(seriesID: String) async throws -> [Season] {
        try await cached(
            resource: "seasons",
            components: [seriesID],
            timeToLive: policy.seasonsTimeToLive,
            tags: [mediaTag(id: seriesID)]
        ) {
            try await upstream.seasons(seriesID: seriesID)
        }
    }

    public func episodes(
        seriesID: String,
        seasonID: String,
        page: PageRequest
    ) async throws -> Page<Episode> {
        try await cached(
            resource: "episodes",
            components: [seriesID, seasonID, String(page.number), String(page.size)],
            timeToLive: policy.episodesTimeToLive,
            tags: [mediaTag(id: seriesID), tag("season", seasonID)]
        ) {
            try await upstream.episodes(
                seriesID: seriesID,
                seasonID: seasonID,
                page: page
            )
        }
    }

    public func person(id: String) async throws -> PersonDetail {
        try await cached(
            resource: "person",
            components: [id],
            timeToLive: policy.personTimeToLive,
            tags: [personTag(id: id)]
        ) {
            try await upstream.person(id: id)
        }
    }

    public func works(
        forPersonID personID: String,
        page: PageRequest,
        sort: MediaSort?
    ) async throws -> Page<MediaSummary> {
        try await cached(
            resource: "person-works",
            components: [
                personID,
                String(page.number),
                String(page.size),
                sort?.field.rawValue ?? "",
                sort?.order.rawValue ?? ""
            ],
            timeToLive: policy.personWorksTimeToLive,
            tags: [personTag(id: personID)]
        ) {
            try await upstream.works(forPersonID: personID, page: page, sort: sort)
        }
    }

    public func favoriteMedia(
        kind: MediaKind,
        page: PageRequest
    ) async throws -> Page<MediaSummary> {
        try await cached(
            resource: "favorite-media",
            components: [kind.rawValue, String(page.number), String(page.size)],
            timeToLive: policy.favoritesTimeToLive,
            tags: [tag("favorites")]
        ) {
            try await upstream.favoriteMedia(kind: kind, page: page)
        }
    }

    public func favoritePeople(page: PageRequest) async throws -> Page<PersonDetail> {
        try await cached(
            resource: "favorite-people",
            components: [String(page.number), String(page.size)],
            timeToLive: policy.favoritesTimeToLive,
            tags: [tag("favorites")]
        ) {
            try await upstream.favoritePeople(page: page)
        }
    }

    public func setFavorite(_ isFavorite: Bool, target: FavoriteTarget) async throws -> Bool {
        let result = try await upstream.setFavorite(isFavorite, target: target)
        try? await cache.removeValues(tagged: tag("favorites"))
        switch target.kind {
        case .movie, .series:
            try? await cache.removeValues(tagged: mediaTag(id: target.id))
        case .person:
            try? await cache.removeValues(tagged: personTag(id: target.id))
        }
        return result
    }

    public func assets(for item: PlayableItem) async throws -> [MediaAsset] {
        try await cached(
            resource: "assets",
            components: [item.kind.rawValue, item.id],
            timeToLive: policy.assetsTimeToLive,
            tags: [mediaTag(id: item.id)]
        ) {
            try await upstream.assets(for: item)
        }
    }

    public func playbackURL(for asset: MediaAsset) async throws -> URL {
        try await upstream.playbackURL(for: asset)
    }

    public func playbackShelf(limit: Int) async throws -> PlaybackShelf {
        try await cached(
            resource: "playback-shelf",
            components: [String(limit)],
            timeToLive: policy.playbackShelfTimeToLive,
            tags: [tag("playback-shelf")]
        ) {
            try await upstream.playbackShelf(limit: limit)
        }
    }

    public func reportProgress(_ update: PlaybackUpdate) async throws -> UserPlaybackState {
        let state = try await upstream.reportProgress(update)
        await invalidatePlaybackState(for: update.item)
        return state
    }

    public func reportStopped(_ update: PlaybackUpdate) async throws -> UserPlaybackState {
        let state = try await upstream.reportStopped(update)
        await invalidatePlaybackState(for: update.item)
        return state
    }

    private func cached<Value: Codable & Sendable>(
        resource: String,
        components: [String] = [],
        timeToLive: TimeInterval,
        tags: Set<MetadataCacheTag> = [],
        load: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let key = cacheKey(resource: resource, components: components)
        let cachedValue: MetadataCacheValue<Value>? = try? await cache.value(
            for: key,
            as: Value.self
        )

        if let cachedValue, cachedValue.isFresh(at: now()) {
            return cachedValue.value
        }

        do {
            let value = try await load()
            try? await cache.insert(
                value,
                for: key,
                timeToLive: timeToLive,
                tags: tags
            )
            return value
        } catch {
            guard let cachedValue, allowsStaleFallback(for: error) else {
                throw error
            }
            return cachedValue.value
        }
    }

    private func invalidatePlaybackState(for item: PlayableItem) async {
        try? await cache.removeValues(tagged: mediaTag(id: item.id))
        try? await cache.removeValues(tagged: tag("playback-shelf"))
    }

    private func allowsStaleFallback(for error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        if error is URLError {
            return true
        }
        guard let error = error as? ProviderError else {
            return false
        }
        switch error {
        case .rateLimited, .invalidResponse, .unavailable:
            return true
        case .unauthenticated, .invalidCredentials, .sessionExpired, .forbidden,
             .notFound, .invalidRequest, .unsupported:
            return false
        }
    }

    private func cacheKey(resource: String, components: [String]) -> MetadataCacheKey {
        let values = [namespace, resource] + components
        let rawValue = values.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        return MetadataCacheKey(rawValue: rawValue)
    }

    private func tag(_ name: String, _ value: String? = nil) -> MetadataCacheTag {
        let components = [namespace, name] + (value.map { [$0] } ?? [])
        let rawValue = components.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        return MetadataCacheTag(rawValue: rawValue)
    }

    private func mediaTag(id: String) -> MetadataCacheTag {
        tag("media", id)
    }

    private func personTag(id: String) -> MetadataCacheTag {
        tag("person", id)
    }
}
