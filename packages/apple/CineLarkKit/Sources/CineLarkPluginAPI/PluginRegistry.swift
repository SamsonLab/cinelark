import Foundation

public enum PluginRegistryError: Error, Equatable {
    case duplicate(PluginID)
    case notFound(PluginID)
}

public actor PluginRegistry {
    private var factories: [PluginID: any MediaSourcePluginFactory] = [:]
    private var legacyOwners: [PluginID: PluginID] = [:]

    public init() {}

    public init(factories: [any MediaSourcePluginFactory]) throws {
        for factory in factories {
            try Self.insert(
                factory,
                factories: &self.factories,
                legacyOwners: &self.legacyOwners
            )
        }
    }

    public func register(_ factory: any MediaSourcePluginFactory) throws {
        try Self.insert(
            factory,
            factories: &factories,
            legacyOwners: &legacyOwners
        )
    }

    private static func insert(
        _ factory: any MediaSourcePluginFactory,
        factories: inout [PluginID: any MediaSourcePluginFactory],
        legacyOwners: inout [PluginID: PluginID]
    ) throws {
        let id = factory.descriptor.id
        guard factories[id] == nil, legacyOwners[id] == nil else {
            throw PluginRegistryError.duplicate(id)
        }
        for legacyID in factory.legacyPluginIDs {
            guard
                legacyID != id,
                factories[legacyID] == nil,
                legacyOwners[legacyID] == nil
            else {
                throw PluginRegistryError.duplicate(legacyID)
            }
        }
        factories[id] = factory
        for legacyID in factory.legacyPluginIDs {
            legacyOwners[legacyID] = id
        }
    }

    public func descriptors() -> [CineLarkPluginDescriptor] {
        factories.values.map(\.descriptor).sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public func factory(for id: PluginID) throws -> any MediaSourcePluginFactory {
        guard let factory = factories[id] else { throw PluginRegistryError.notFound(id) }
        return factory
    }

    public func migrationProposal(
        pluginID: PluginID,
        configuration: SourceConfiguration
    ) -> SourceMigrationProposal? {
        guard
            configuration.serverIdentity.pluginID == pluginID,
            let ownerID = legacyOwners[pluginID],
            let factory = factories[ownerID]
        else { return nil }
        return factory.migrationProposal(from: pluginID, configuration: configuration)
    }
}
