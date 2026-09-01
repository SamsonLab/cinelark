import Foundation

public enum MediaSourcePlatformError: Error, Equatable, Sendable {
    case sourceNotInstalled(SourceID)
    case scopeRequiresSingleSource
    case capabilityUnavailable(String)
}

public actor MediaSourcePlatform {
    private let registry: PluginRegistry
    private var runtimes: [SourceID: MediaSourceRuntime] = [:]

    public init(registry: PluginRegistry) {
        self.registry = registry
    }

    public func descriptors() async -> [CineLarkPluginDescriptor] {
        await registry.descriptors()
    }

    public func discover(pluginID: PluginID) async throws -> [DiscoveredSource] {
        try await registry.factory(for: pluginID).discover()
    }

    public func validate(pluginID: PluginID, baseURL: URL) async throws -> SourceInstanceIdentity {
        try await registry.factory(for: pluginID).validate(baseURL: baseURL)
    }

    public func migrationProposal(
        pluginID: PluginID,
        configuration: SourceConfiguration
    ) async -> SourceMigrationProposal? {
        await registry.migrationProposal(
            pluginID: pluginID,
            configuration: configuration
        )
    }

    @discardableResult
    public func install(
        pluginID: PluginID,
        configuration: SourceConfiguration
    ) async throws -> MediaSourceRuntime {
        let factory = try await registry.factory(for: pluginID)
        guard factory.descriptor.id == configuration.serverIdentity.pluginID else {
            throw MediaSourceFailure.invalidResponse
        }
        let runtime = try await factory.makeRuntime(configuration: configuration)
        runtimes[configuration.sourceID] = runtime
        return runtime
    }

    public func remove(sourceID: SourceID) {
        runtimes[sourceID] = nil
    }

    public func authenticate(
        pluginID: PluginID,
        configuration: SourceConfiguration,
        credentials: SourceCredentials
    ) async throws -> SourceConfiguration {
        let runtime = try await install(pluginID: pluginID, configuration: configuration)
        guard let authentication = runtime.authentication else {
            return configuration
        }
        let authenticated = try await authentication.authenticate(credentials)
        _ = try await install(
            pluginID: pluginID,
            configuration: authenticated.configuration
        )
        return authenticated.configuration
    }

    public func runtime(for sourceID: SourceID) throws -> MediaSourceRuntime {
        guard let runtime = runtimes[sourceID] else {
            throw MediaSourcePlatformError.sourceNotInstalled(sourceID)
        }
        return runtime
    }

    public func page(for query: MediaQuery) async throws -> MediaPage {
        guard query.scope.sourceIDs.count == 1, let sourceID = query.scope.sourceIDs.first else {
            throw MediaSourcePlatformError.scopeRequiresSingleSource
        }
        let runtime = try runtime(for: sourceID)
        guard let browse = runtime.browse else {
            throw MediaSourcePlatformError.capabilityUnavailable("browse")
        }
        return try await browse.page(query)
    }

    public func search(_ term: String, query: MediaQuery) async throws -> MediaPage {
        guard query.scope.sourceIDs.count == 1, let sourceID = query.scope.sourceIDs.first else {
            throw MediaSourcePlatformError.scopeRequiresSingleSource
        }
        let runtime = try runtime(for: sourceID)
        guard let search = runtime.search else {
            throw MediaSourcePlatformError.capabilityUnavailable("search")
        }
        return try await search.search(term, query)
    }

    public func hierarchy(for sourceID: SourceID) throws -> HierarchyClient {
        let runtime = try runtime(for: sourceID)
        guard let hierarchy = runtime.hierarchy else {
            throw MediaSourcePlatformError.capabilityUnavailable("hierarchy")
        }
        return hierarchy
    }

    public func artwork(
        for locator: MediaLocatorID,
        kind: String
    ) async throws -> ArtworkDescriptor? {
        let runtime = try runtime(for: locator.sourceID)
        guard let artwork = runtime.artwork else { return nil }
        return try await artwork.resolve(locator, kind)
    }

    public func playbackVariants(for locator: MediaLocatorID) async throws -> [PlaybackVariant] {
        let runtime = try runtime(for: locator.sourceID)
        guard let playback = runtime.playback else {
            throw MediaSourcePlatformError.capabilityUnavailable("playback")
        }
        return try await playback.variants(locator)
    }

    public func playback(
        for locator: MediaLocatorID,
        variantID: String? = nil
    ) async throws -> SourcePlaybackDescriptor {
        let runtime = try runtime(for: locator.sourceID)
        guard let playback = runtime.playback else {
            throw MediaSourcePlatformError.capabilityUnavailable("playback")
        }
        return try await playback.resolveVariant(locator, variantID)
    }

    public func reportPlayback(sourceID: SourceID, event: PlaybackEvent) async throws {
        let runtime = try runtime(for: sourceID)
        guard let session = runtime.playbackSession else { return }
        try await session.report(event)
    }

    public func importRemoteState(sourceID: SourceID) async throws -> RemoteStateSnapshot {
        let runtime = try runtime(for: sourceID)
        guard let client = runtime.remoteStateImport else {
            throw MediaSourcePlatformError.capabilityUnavailable("remoteStateImport")
        }
        return try await client.importState()
    }

    public func mirrorRemoteState(
        sourceID: SourceID,
        remoteUserID: String,
        mutation: RemoteStateMutation
    ) async throws {
        let runtime = try runtime(for: sourceID)
        guard let client = runtime.remoteStateMirror else {
            throw MediaSourcePlatformError.capabilityUnavailable("remoteStateMirror")
        }
        try await client.mirrorState(remoteUserID, mutation)
    }
}
