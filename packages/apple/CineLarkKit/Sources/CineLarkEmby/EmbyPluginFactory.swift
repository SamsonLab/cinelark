import Foundation
import CineLarkDomain
import CineLarkPluginAPI

public struct EmbyPluginFactory: MediaSourcePluginFactory {
    public static let pluginID: PluginID = "com.samsonlab.cinelark.emby"

    public let descriptor = CineLarkPluginDescriptor(
        id: Self.pluginID,
        contractVersion: 1,
        displayName: "Emby",
        roles: [.mediaSource],
        setupModes: [.manualURL, .localDiscovery],
        authenticationModes: [.usernamePassword, .token],
        capabilities: CapabilityDescriptor(
            itemKinds: [.movie, .series],
            sortFields: Set(MediaSort.Field.allCases),
            filters: ["favorite", "played", "resumable", "genre"],
            pagination: .offset,
            playbackModes: [.directPlay, .directStream],
            mutations: [.favorite, .played, .progress]
        )
    )

    private let device: EmbyDeviceIdentity
    private let http: EmbyHTTPClient
    private let tokenVault: EmbyTokenVault
    private let discovery: EmbyDiscoveryClient

    public init(
        device: EmbyDeviceIdentity,
        http: EmbyHTTPClient = .live,
        tokenVault: EmbyTokenVault = .ephemeral,
        discovery: EmbyDiscoveryClient = .live
    ) {
        self.device = device
        self.http = http
        self.tokenVault = tokenVault
        self.discovery = discovery
    }

    public func discover() async throws -> [DiscoveredSource] {
        try await discovery.discover(.seconds(2))
    }

    public func validate(baseURL: URL) async throws -> SourceInstanceIdentity {
        let builder = EmbyRequestBuilder(baseURL: baseURL, device: device)
        let request = try builder.request(path: "System/Info/Public")
        do {
            let response = try await http.send(request)
            guard (200..<300).contains(response.response.statusCode) else {
                throw MediaSourceFailure.unavailable
            }
            let info = try JSONDecoder().decode(PublicSystemInfo.self, from: response.data)
            return SourceInstanceIdentity(pluginID: Self.pluginID, serverID: info.id)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as MediaSourceFailure {
            throw failure
        } catch {
            throw MediaSourceFailure.transport(String(describing: error))
        }
    }

    public func makeRuntime(configuration: SourceConfiguration) async throws -> MediaSourceRuntime {
        let service = EmbyService(
            configuration: configuration,
            device: device,
            http: http,
            tokenVault: tokenVault
        )
        return MediaSourceRuntime(
            sourceID: configuration.sourceID,
            descriptor: descriptor,
            authentication: AuthenticationClient { credentials in
                try await service.authenticate(credentials)
            },
            browse: BrowseClient { query in
                try await service.page(query: query)
            },
            search: SearchClient { term, query in
                try await service.page(query: query, searchTerm: term)
            },
            hierarchy: HierarchyClient(
                collections: { try await service.collections() },
                latest: { try await service.latest(query: $0) },
                resume: { try await service.resume(query: $0) },
                detail: { locator, _ in try await service.detail(locator: locator) },
                seasons: { try await service.seasons(series: $0) },
                episodes: { try await service.episodes(series: $0, seasonID: $1, page: $2) },
                person: { try await service.person(id: $0) },
                works: { try await service.works(personID: $0, query: $1) }
            ),
            artwork: ArtworkClient { locator, kind in
                try await service.artwork(locator: locator, kind: kind)
            },
            playback: PlaybackResolutionClient { locator in
                try await service.playback(locator: locator)
            },
            playbackSession: PlaybackSessionClient { event in
                try await service.report(event)
            },
            remoteStateImport: RemoteStateClient(
                importState: { try await service.importRemoteState() },
                mirrorState: { try await service.mirrorRemoteState(userID: $0, mutation: $1) }
            ),
            remoteStateMirror: RemoteStateClient(
                importState: { try await service.importRemoteState() },
                mirrorState: { try await service.mirrorRemoteState(userID: $0, mutation: $1) }
            )
        )
    }
}
