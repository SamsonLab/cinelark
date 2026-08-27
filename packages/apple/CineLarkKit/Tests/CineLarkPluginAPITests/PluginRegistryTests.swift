import Foundation
import Testing
@testable import CineLarkPluginAPI

private struct StubFactory: MediaSourcePluginFactory {
    let descriptor: CineLarkPluginDescriptor

    func validate(baseURL: URL) async throws -> SourceInstanceIdentity {
        SourceInstanceIdentity(pluginID: descriptor.id, serverID: baseURL.absoluteString)
    }

    func makeRuntime(configuration: SourceConfiguration) async throws -> MediaSourceRuntime {
        MediaSourceRuntime(sourceID: configuration.sourceID, descriptor: descriptor)
    }
}

private struct MigratingFactory: MediaSourcePluginFactory {
    let descriptor: CineLarkPluginDescriptor
    let legacyPluginIDs: Set<PluginID>

    func validate(baseURL: URL) async throws -> SourceInstanceIdentity {
        SourceInstanceIdentity(pluginID: descriptor.id, serverID: baseURL.absoluteString)
    }

    func makeRuntime(configuration: SourceConfiguration) async throws -> MediaSourceRuntime {
        MediaSourceRuntime(sourceID: configuration.sourceID, descriptor: descriptor)
    }

    func migrationProposal(
        from legacyPluginID: PluginID,
        configuration: SourceConfiguration
    ) -> SourceMigrationProposal? {
        guard legacyPluginIDs.contains(legacyPluginID) else { return nil }
        return SourceMigrationProposal(
            sourceID: configuration.sourceID,
            legacyPluginID: legacyPluginID,
            targetPluginID: descriptor.id,
            suggestedBaseURL: configuration.baseURL,
            displayName: configuration.displayName
        )
    }
}

@Test func registryRejectsDuplicateStablePluginIDs() async throws {
    let descriptor = CineLarkPluginDescriptor(
        id: "test.media",
        contractVersion: 1,
        displayName: "Test",
        roles: [.mediaSource],
        setupModes: [.manualURL],
        authenticationModes: [.none],
        capabilities: CapabilityDescriptor(
            itemKinds: [.movie],
            sortFields: [.title],
            filters: [],
            pagination: .opaqueCursor,
            playbackModes: [.directPlay],
            mutations: []
        )
    )
    let registry = PluginRegistry()
    try await registry.register(StubFactory(descriptor: descriptor))

    await #expect(throws: PluginRegistryError.duplicate("test.media")) {
        try await registry.register(StubFactory(descriptor: descriptor))
    }
}

@Test func registryRoutesLegacySourcesWithoutListingAnotherDescriptor() async throws {
    let canonical = descriptor(id: "test.canonical", name: "Canonical")
    let legacyID: PluginID = "test.legacy"
    let sourceID = SourceID(rawValue: UUID())
    let registry = try PluginRegistry(factories: [
        MigratingFactory(descriptor: canonical, legacyPluginIDs: [legacyID])
    ])
    let configuration = SourceConfiguration(
        sourceID: sourceID,
        baseURL: URL(string: "https://example.test/legacy")!,
        serverIdentity: SourceInstanceIdentity(
            pluginID: legacyID,
            serverID: "legacy-server"
        ),
        displayName: "Legacy"
    )

    #expect(await registry.descriptors().map(\.id) == [canonical.id])
    let proposal = await registry.migrationProposal(
        pluginID: legacyID,
        configuration: configuration
    )
    #expect(proposal?.sourceID == sourceID)
    #expect(proposal?.legacyPluginID == legacyID)
    #expect(proposal?.targetPluginID == canonical.id)

    let inconsistent = SourceConfiguration(
        sourceID: sourceID,
        baseURL: configuration.baseURL,
        serverIdentity: SourceInstanceIdentity(
            pluginID: canonical.id,
            serverID: "canonical-server"
        ),
        displayName: configuration.displayName
    )
    #expect(await registry.migrationProposal(
        pluginID: legacyID,
        configuration: inconsistent
    ) == nil)
}

@Test func registryRejectsDuplicateLegacyPluginOwnership() throws {
    let legacyID: PluginID = "test.legacy"

    #expect(throws: PluginRegistryError.duplicate(legacyID)) {
        _ = try PluginRegistry(factories: [
            MigratingFactory(
                descriptor: descriptor(id: "test.first", name: "First"),
                legacyPluginIDs: [legacyID]
            ),
            MigratingFactory(
                descriptor: descriptor(id: "test.second", name: "Second"),
                legacyPluginIDs: [legacyID]
            )
        ])
    }
}

@Test func registryRejectsCanonicalIDDeclaredAsItsOwnLegacyAlias() throws {
    let pluginID: PluginID = "test.self-alias"

    #expect(throws: PluginRegistryError.duplicate(pluginID)) {
        _ = try PluginRegistry(factories: [
            MigratingFactory(
                descriptor: descriptor(id: pluginID, name: "Self Alias"),
                legacyPluginIDs: [pluginID]
            )
        ])
    }
}

private func descriptor(id: PluginID, name: String) -> CineLarkPluginDescriptor {
    CineLarkPluginDescriptor(
        id: id,
        contractVersion: 1,
        displayName: name,
        roles: [.mediaSource],
        setupModes: [.manualURL],
        authenticationModes: [.none],
        capabilities: CapabilityDescriptor(
            itemKinds: [.movie],
            sortFields: [.title],
            filters: [],
            pagination: .opaqueCursor,
            playbackModes: [.directPlay],
            mutations: []
        )
    )
}
