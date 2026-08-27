import Foundation
import CineLarkDomain
import CineLarkPluginAPI

public struct EmbyPluginFactory: MediaSourcePluginFactory {
    public static let pluginID: PluginID = "com.samsonlab.cinelark.emby"
    public static let legacyUHDNowPluginID: PluginID = "com.samsonlab.cinelark.uhdnow"

    public let legacyPluginIDs: Set<PluginID> = [Self.legacyUHDNowPluginID]

    public let descriptor = CineLarkPluginDescriptor(
        id: Self.pluginID,
        contractVersion: 1,
        displayName: "Emby",
        roles: [.mediaSource],
        setupModes: [.manualURL, .localDiscovery],
        authenticationModes: [.usernamePassword, .token],
        capabilities: CapabilityDescriptor(
            itemKinds: [.movie, .series, .episode],
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

    public func migrationProposal(
        from legacyPluginID: PluginID,
        configuration: SourceConfiguration
    ) -> SourceMigrationProposal? {
        guard legacyPluginIDs.contains(legacyPluginID) else { return nil }
        return SourceMigrationProposal(
            sourceID: configuration.sourceID,
            legacyPluginID: legacyPluginID,
            targetPluginID: Self.pluginID,
            suggestedBaseURL: Self.suggestedEmbyURL(from: configuration.baseURL),
            displayName: configuration.displayName
        )
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

    private static func suggestedEmbyURL(from legacyURL: URL) -> URL {
        guard var components = URLComponents(
            url: legacyURL,
            resolvingAgainstBaseURL: false
        ) else { return legacyURL }
        var segments = components.percentEncodedPath
            .split(separator: "/")
            .map(String.init)
        if segments.count >= 2,
           segments[segments.count - 2].lowercased() == "api",
           segments[segments.count - 1].lowercased() == "v1" {
            segments.removeLast(2)
        }
        components.percentEncodedPath = segments.isEmpty ? "" : "/" + segments.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return components.url ?? legacyURL
    }
}
