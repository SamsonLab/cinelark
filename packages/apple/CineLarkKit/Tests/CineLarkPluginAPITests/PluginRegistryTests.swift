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
