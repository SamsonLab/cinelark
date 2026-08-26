import ComposableArchitecture
import Foundation
import CineLarkCatalog
import CineLarkDomain
import CineLarkPluginAPI

struct MediaPlatformClient: Sendable {
    var descriptors: @Sendable () async -> [CineLarkPluginDescriptor]
    var discover: @Sendable (PluginID) async throws -> [DiscoveredSource]
    var validate: @Sendable (PluginID, URL) async throws -> SourceInstanceIdentity
    var install: @Sendable (PluginID, SourceConfiguration) async throws -> Void
    var authenticate: @Sendable (
        PluginID,
        SourceConfiguration,
        SourceCredentials
    ) async throws -> SourceConfiguration
    var remove: @Sendable (SourceID) async -> Void
    var cachedPage: @Sendable (MediaQuery) async throws -> MediaPage
    var refreshPage: @Sendable (MediaQuery) async throws -> MediaPage
    var search: @Sendable (String, MediaQuery) async throws -> MediaPage
    var collections: @Sendable (SourceID) async throws -> [MediaCollection]
    var latest: @Sendable (MediaQuery) async throws -> MediaPage
    var resume: @Sendable (MediaQuery) async throws -> MediaPage
    var detail: @Sendable (MediaLocatorID, MediaSummary) async throws -> MediaDetail
    var seasons: @Sendable (MediaLocatorID) async throws -> [Season]
    var episodes: @Sendable (MediaLocatorID, String, PageRequest) async throws -> Page<Episode>
    var person: @Sendable (SourceID, String) async throws -> PersonDetail
    var works: @Sendable (String, MediaQuery) async throws -> MediaPage
    var resolvePlayback: @Sendable (MediaLocatorID) async throws -> SourcePlaybackDescriptor
    var reportPlayback: @Sendable (SourceID, CineLarkPluginAPI.PlaybackEvent) async throws -> Void
    var importRemoteState: @Sendable (SourceID) async throws -> RemoteStateSnapshot
    var mirrorRemoteState: @Sendable (SourceID, String, RemoteStateMutation) async throws -> Void

    init(
        descriptors: @escaping @Sendable () async -> [CineLarkPluginDescriptor],
        discover: @escaping @Sendable (PluginID) async throws -> [DiscoveredSource] = { _ in [] },
        validate: @escaping @Sendable (PluginID, URL) async throws -> SourceInstanceIdentity = { _, _ in
            throw MediaSourceFailure.unavailable
        },
        install: @escaping @Sendable (PluginID, SourceConfiguration) async throws -> Void = { _, _ in
            throw MediaSourceFailure.unavailable
        },
        authenticate: @escaping @Sendable (
            PluginID,
            SourceConfiguration,
            SourceCredentials
        ) async throws -> SourceConfiguration = { _, _, _ in
            throw MediaSourceFailure.unavailable
        },
        remove: @escaping @Sendable (SourceID) async -> Void = { _ in },
        cachedPage: @escaping @Sendable (MediaQuery) async throws -> MediaPage,
        refreshPage: @escaping @Sendable (MediaQuery) async throws -> MediaPage,
        search: @escaping @Sendable (String, MediaQuery) async throws -> MediaPage = { _, _ in
            throw MediaSourceFailure.unavailable
        },
        collections: @escaping @Sendable (SourceID) async throws -> [MediaCollection] = { _ in
            throw MediaSourceFailure.unsupported("hierarchy")
        },
        latest: @escaping @Sendable (MediaQuery) async throws -> MediaPage = { _ in
            throw MediaSourceFailure.unsupported("latest")
        },
        resume: @escaping @Sendable (MediaQuery) async throws -> MediaPage = { _ in
            throw MediaSourceFailure.unsupported("resume")
        },
        detail: @escaping @Sendable (MediaLocatorID, MediaSummary) async throws -> MediaDetail = { _, _ in
            throw MediaSourceFailure.unsupported("detail")
        },
        seasons: @escaping @Sendable (MediaLocatorID) async throws -> [Season] = { _ in
            throw MediaSourceFailure.unsupported("seasons")
        },
        episodes: @escaping @Sendable (MediaLocatorID, String, PageRequest) async throws -> Page<Episode> = { _, _, _ in
            throw MediaSourceFailure.unsupported("episodes")
        },
        person: @escaping @Sendable (SourceID, String) async throws -> PersonDetail = { _, _ in
            throw MediaSourceFailure.unsupported("person")
        },
        works: @escaping @Sendable (String, MediaQuery) async throws -> MediaPage = { _, _ in
            throw MediaSourceFailure.unsupported("works")
        },
        resolvePlayback: @escaping @Sendable (MediaLocatorID) async throws -> SourcePlaybackDescriptor = { _ in
            throw MediaSourceFailure.unsupported("playback")
        },
        reportPlayback: @escaping @Sendable (SourceID, CineLarkPluginAPI.PlaybackEvent) async throws -> Void = { _, _ in },
        importRemoteState: @escaping @Sendable (SourceID) async throws -> RemoteStateSnapshot = { _ in
            throw MediaSourceFailure.unsupported("remoteStateImport")
        },
        mirrorRemoteState: @escaping @Sendable (SourceID, String, RemoteStateMutation) async throws -> Void = { _, _, _ in
            throw MediaSourceFailure.unsupported("remoteStateMirror")
        }
    ) {
        self.descriptors = descriptors
        self.discover = discover
        self.validate = validate
        self.install = install
        self.authenticate = authenticate
        self.remove = remove
        self.cachedPage = cachedPage
        self.refreshPage = refreshPage
        self.search = search
        self.collections = collections
        self.latest = latest
        self.resume = resume
        self.detail = detail
        self.seasons = seasons
        self.episodes = episodes
        self.person = person
        self.works = works
        self.resolvePlayback = resolvePlayback
        self.reportPlayback = reportPlayback
        self.importRemoteState = importRemoteState
        self.mirrorRemoteState = mirrorRemoteState
    }
}

extension MediaPlatformClient: DependencyKey {
    static let liveValue = MediaPlatformClient(
        descriptors: { [] },
        cachedPage: { _ in throw MediaSourceFailure.unavailable },
        refreshPage: { _ in throw MediaSourceFailure.unavailable }
    )

    static let testValue = liveValue
}

extension DependencyValues {
    var mediaPlatform: MediaPlatformClient {
        get { self[MediaPlatformClient.self] }
        set { self[MediaPlatformClient.self] = newValue }
    }
}

extension MediaPlatformClient {
    static func live(
        platform: MediaSourcePlatform,
        catalog: any CatalogRepository
    ) -> Self {
        Self(
            descriptors: { await platform.descriptors() },
            discover: { try await platform.discover(pluginID: $0) },
            validate: { try await platform.validate(pluginID: $0, baseURL: $1) },
            install: { pluginID, configuration in
                _ = try await platform.install(
                    pluginID: pluginID,
                    configuration: configuration
                )
            },
            authenticate: { pluginID, configuration, credentials in
                try await platform.authenticate(
                    pluginID: pluginID,
                    configuration: configuration,
                    credentials: credentials
                )
            },
            remove: { await platform.remove(sourceID: $0) },
            cachedPage: { query in try await catalog.cachedPage(for: query) },
            refreshPage: { query in
                let remote = try await platform.page(for: query)
                return try await catalog.cache(remote, for: query, refreshedAt: Date())
            },
            search: { term, query in
                let remote = try await platform.search(term, query: query)
                let normalized = try await catalog.upsert(remote.items, refreshedAt: Date())
                return MediaPage(
                    items: normalized,
                    nextCursor: remote.nextCursor,
                    total: remote.total
                )
            },
            collections: { sourceID in
                try await platform.hierarchy(for: sourceID).collections()
            },
            latest: { query in
                try await normalize(
                    platform.hierarchy(for: Self.singleSourceID(query)).latest(query),
                    query: query,
                    catalog: catalog
                )
            },
            resume: { query in
                try await normalize(
                    platform.hierarchy(for: Self.singleSourceID(query)).resume(query),
                    query: query,
                    catalog: catalog
                )
            },
            detail: { locator, summary in
                try await platform.hierarchy(for: locator.sourceID).detail(locator, summary)
            },
            seasons: { locator in
                try await platform.hierarchy(for: locator.sourceID).seasons(locator)
            },
            episodes: { locator, seasonID, page in
                try await platform.hierarchy(for: locator.sourceID).episodes(locator, seasonID, page)
            },
            person: { sourceID, id in
                try await platform.hierarchy(for: sourceID).person(id)
            },
            works: { personID, query in
                try await normalize(
                    platform.hierarchy(for: Self.singleSourceID(query)).works(personID, query),
                    query: query,
                    catalog: catalog
                )
            },
            resolvePlayback: { try await platform.playback(for: $0) },
            reportPlayback: { try await platform.reportPlayback(sourceID: $0, event: $1) },
            importRemoteState: { try await platform.importRemoteState(sourceID: $0) },
            mirrorRemoteState: {
                try await platform.mirrorRemoteState(
                    sourceID: $0,
                    remoteUserID: $1,
                    mutation: $2
                )
            }
        )
    }

    private static func singleSourceID(_ query: MediaQuery) throws -> SourceID {
        guard query.scope.sourceIDs.count == 1, let id = query.scope.sourceIDs.first else {
            throw MediaSourcePlatformError.scopeRequiresSingleSource
        }
        return id
    }

    private static func normalize(
        _ page: MediaPage,
        query: MediaQuery,
        catalog: any CatalogRepository
    ) async throws -> MediaPage {
        try await catalog.cache(page, for: query, refreshedAt: Date())
    }
}
