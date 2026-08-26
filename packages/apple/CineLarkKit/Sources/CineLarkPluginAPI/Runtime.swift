import Foundation
import CineLarkDomain

public struct DiscoveredSource: Codable, Hashable, Sendable {
    public let name: String
    public let address: URL
    public let serverID: String?

    public init(name: String, address: URL, serverID: String? = nil) {
        self.name = name
        self.address = address
        self.serverID = serverID
    }
}

public struct AuthenticatedSource: Equatable, Sendable {
    public let configuration: SourceConfiguration
    public let token: String

    public init(configuration: SourceConfiguration, token: String) {
        self.configuration = configuration
        self.token = token
    }
}

public struct SourcePlaybackDescriptor: Codable, Hashable, Sendable {
    public let url: URL
    public let headers: [String: String]
    public let mode: PlaybackMode
    public let mediaSourceID: String?

    public init(
        url: URL,
        headers: [String: String] = [:],
        mode: PlaybackMode,
        mediaSourceID: String? = nil
    ) {
        self.url = url
        self.headers = headers
        self.mode = mode
        self.mediaSourceID = mediaSourceID
    }
}

public enum MediaSourceChange: Codable, Hashable, Sendable {
    case invalidated
    case itemsChanged(Set<MediaLocatorID>)
    case remoteStateChanged(Set<MediaLocatorID>)
}

public enum PlaybackEvent: Codable, Hashable, Sendable {
    case started(locator: MediaLocatorID, positionSeconds: Double)
    case progress(locator: MediaLocatorID, positionSeconds: Double, isPaused: Bool)
    case stopped(locator: MediaLocatorID, positionSeconds: Double, reachedEOF: Bool)
}

public enum MediaSourceFailure: Error, Codable, Hashable, Sendable {
    case unavailable
    case unauthorized
    case invalidResponse
    case unsupported(String)
    case transport(String)
}

public typealias MediaSourceChangeStream = AsyncThrowingStream<MediaSourceChange, Error>

public struct DiscoveryClient: Sendable {
    public var discover: @Sendable () async throws -> [DiscoveredSource]
    public init(discover: @escaping @Sendable () async throws -> [DiscoveredSource]) {
        self.discover = discover
    }
}

public struct AuthenticationClient: Sendable {
    public var authenticate: @Sendable (SourceCredentials) async throws -> AuthenticatedSource
    public init(authenticate: @escaping @Sendable (SourceCredentials) async throws -> AuthenticatedSource) {
        self.authenticate = authenticate
    }
}

public struct BrowseClient: Sendable {
    public var page: @Sendable (MediaQuery) async throws -> MediaPage
    public init(page: @escaping @Sendable (MediaQuery) async throws -> MediaPage) {
        self.page = page
    }
}

public struct SearchClient: Sendable {
    public var search: @Sendable (String, MediaQuery) async throws -> MediaPage
    public init(search: @escaping @Sendable (String, MediaQuery) async throws -> MediaPage) {
        self.search = search
    }
}

public struct HierarchyClient: Sendable {
    public var collections: @Sendable () async throws -> [MediaCollection]
    public var latest: @Sendable (MediaQuery) async throws -> MediaPage
    public var resume: @Sendable (MediaQuery) async throws -> MediaPage
    public var detail: @Sendable (MediaLocatorID, MediaSummary) async throws -> MediaDetail
    public var seasons: @Sendable (MediaLocatorID) async throws -> [Season]
    public var episodes: @Sendable (
        MediaLocatorID,
        String,
        PageRequest
    ) async throws -> Page<Episode>
    public var person: @Sendable (String) async throws -> PersonDetail
    public var works: @Sendable (String, MediaQuery) async throws -> MediaPage

    public init(
        collections: @escaping @Sendable () async throws -> [MediaCollection],
        latest: @escaping @Sendable (MediaQuery) async throws -> MediaPage,
        resume: @escaping @Sendable (MediaQuery) async throws -> MediaPage,
        detail: @escaping @Sendable (MediaLocatorID, MediaSummary) async throws -> MediaDetail,
        seasons: @escaping @Sendable (MediaLocatorID) async throws -> [Season],
        episodes: @escaping @Sendable (
            MediaLocatorID,
            String,
            PageRequest
        ) async throws -> Page<Episode>,
        person: @escaping @Sendable (String) async throws -> PersonDetail,
        works: @escaping @Sendable (String, MediaQuery) async throws -> MediaPage
    ) {
        self.collections = collections
        self.latest = latest
        self.resume = resume
        self.detail = detail
        self.seasons = seasons
        self.episodes = episodes
        self.person = person
        self.works = works
    }
}

public struct ArtworkClient: Sendable {
    public var resolve: @Sendable (MediaLocatorID, String) async throws -> ArtworkDescriptor?
    public init(resolve: @escaping @Sendable (MediaLocatorID, String) async throws -> ArtworkDescriptor?) {
        self.resolve = resolve
    }
}

public struct ArtworkDescriptor: Codable, Hashable, Sendable {
    public let url: URL
    public let headers: [String: String]

    public init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
    }
}

public struct PlaybackResolutionClient: Sendable {
    public var resolve: @Sendable (MediaLocatorID) async throws -> SourcePlaybackDescriptor
    public init(resolve: @escaping @Sendable (MediaLocatorID) async throws -> SourcePlaybackDescriptor) {
        self.resolve = resolve
    }
}

public struct ChangeFeedClient: Sendable {
    public var changes: @Sendable () -> MediaSourceChangeStream
    public init(changes: @escaping @Sendable () -> MediaSourceChangeStream) {
        self.changes = changes
    }
}

public struct RemoteMediaState: Codable, Hashable, Sendable {
    public let locator: MediaLocatorID
    public let summary: MediaSummary
    public let isFavorite: Bool?
    public let playback: UserPlaybackState?

    public init(
        locator: MediaLocatorID,
        summary: MediaSummary,
        isFavorite: Bool?,
        playback: UserPlaybackState?
    ) {
        self.locator = locator
        self.summary = summary
        self.isFavorite = isFavorite
        self.playback = playback
    }
}

public struct RemoteStateSnapshot: Codable, Hashable, Sendable {
    public let marker: String
    public let remoteUserID: String
    public let items: [RemoteMediaState]

    public init(marker: String, remoteUserID: String, items: [RemoteMediaState]) {
        self.marker = marker
        self.remoteUserID = remoteUserID
        self.items = items
    }
}

public enum RemoteStateMutation: Codable, Hashable, Sendable {
    case favorite(MediaLocatorID, Bool)
    case playback(MediaLocatorID, UserPlaybackState)
}

public struct RemoteStateClient: Sendable {
    public var importState: @Sendable () async throws -> RemoteStateSnapshot
    public var mirrorState: @Sendable (String, RemoteStateMutation) async throws -> Void

    public init(
        importState: @escaping @Sendable () async throws -> RemoteStateSnapshot,
        mirrorState: @escaping @Sendable (String, RemoteStateMutation) async throws -> Void
    ) {
        self.importState = importState
        self.mirrorState = mirrorState
    }
}

public struct PlaybackSessionClient: Sendable {
    public var report: @Sendable (PlaybackEvent) async throws -> Void
    public init(report: @escaping @Sendable (PlaybackEvent) async throws -> Void) {
        self.report = report
    }
}

public struct MediaSourceRuntime: Sendable {
    public let sourceID: SourceID
    public let descriptor: CineLarkPluginDescriptor
    public let discovery: DiscoveryClient?
    public let authentication: AuthenticationClient?
    public let browse: BrowseClient?
    public let search: SearchClient?
    public let hierarchy: HierarchyClient?
    public let artwork: ArtworkClient?
    public let playback: PlaybackResolutionClient?
    public let playbackSession: PlaybackSessionClient?
    public let download: PlaybackResolutionClient?
    public let changeFeed: ChangeFeedClient?
    public let remoteStateImport: RemoteStateClient?
    public let remoteStateMirror: RemoteStateClient?

    public init(
        sourceID: SourceID,
        descriptor: CineLarkPluginDescriptor,
        discovery: DiscoveryClient? = nil,
        authentication: AuthenticationClient? = nil,
        browse: BrowseClient? = nil,
        search: SearchClient? = nil,
        hierarchy: HierarchyClient? = nil,
        artwork: ArtworkClient? = nil,
        playback: PlaybackResolutionClient? = nil,
        playbackSession: PlaybackSessionClient? = nil,
        download: PlaybackResolutionClient? = nil,
        changeFeed: ChangeFeedClient? = nil,
        remoteStateImport: RemoteStateClient? = nil,
        remoteStateMirror: RemoteStateClient? = nil
    ) {
        self.sourceID = sourceID
        self.descriptor = descriptor
        self.discovery = discovery
        self.authentication = authentication
        self.browse = browse
        self.search = search
        self.hierarchy = hierarchy
        self.artwork = artwork
        self.playback = playback
        self.playbackSession = playbackSession
        self.download = download
        self.changeFeed = changeFeed
        self.remoteStateImport = remoteStateImport
        self.remoteStateMirror = remoteStateMirror
    }
}

public protocol MediaSourcePluginFactory: Sendable {
    var descriptor: CineLarkPluginDescriptor { get }
    func discover() async throws -> [DiscoveredSource]
    func validate(baseURL: URL) async throws -> SourceInstanceIdentity
    func makeRuntime(configuration: SourceConfiguration) async throws -> MediaSourceRuntime
}

public extension MediaSourcePluginFactory {
    func discover() async throws -> [DiscoveredSource] { [] }
}
