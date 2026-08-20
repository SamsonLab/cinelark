import Foundation

public protocol ProviderSessionStore: Sendable {
    func load() async throws -> ProviderSession?
    func save(_ session: ProviderSession) async throws
    func clear() async throws
}

public protocol MediaLibraryProvider: Sendable {
    func restoreSession() async throws -> ProviderSession?
    func signIn(credentials: ProviderCredentials) async throws -> ProviderSession
    func signOut() async

    func hot(page: PageRequest) async throws -> Page<MediaSummary>
    func collections() async throws -> [MediaCollection]
    func items(
        in collectionID: String,
        page: PageRequest,
        sort: MediaSort?
    ) async throws -> Page<MediaSummary>
    func search(_ query: String, page: PageRequest) async throws -> Page<MediaSummary>

    func detail(for item: MediaSummary) async throws -> MediaDetail
    func seasons(seriesID: String) async throws -> [Season]
    func episodes(
        seriesID: String,
        seasonID: String,
        page: PageRequest
    ) async throws -> Page<Episode>

    func assets(for item: PlayableItem) async throws -> [MediaAsset]
    func playbackURL(for asset: MediaAsset) async throws -> URL
    func playbackShelf(limit: Int) async throws -> PlaybackShelf

    func reportProgress(_ update: PlaybackUpdate) async throws -> UserPlaybackState
    func reportStopped(_ update: PlaybackUpdate) async throws -> UserPlaybackState
}

public struct MediaSort: Sendable, Equatable {
    public enum Field: String, Sendable {
        case releaseDate = "release_date"
        case updatedAt = "updated_at"
        case assetUpdatedAt = "asset_updated_at"
        case title
        case rating
        case popularity = "hot"
    }

    public enum Order: String, Sendable {
        case ascending = "asc"
        case descending = "desc"
    }

    public let field: Field
    public let order: Order

    public init(field: Field, order: Order) {
        self.field = field
        self.order = order
    }

    public static let newest = MediaSort(field: .releaseDate, order: .descending)
}
