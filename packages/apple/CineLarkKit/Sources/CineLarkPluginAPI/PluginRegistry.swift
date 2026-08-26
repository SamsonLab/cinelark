import Foundation

public enum PluginRegistryError: Error, Equatable {
    case duplicate(PluginID)
    case notFound(PluginID)
}

public actor PluginRegistry {
    private var factories: [PluginID: any MediaSourcePluginFactory] = [:]

    public init() {}

    public init(factories: [any MediaSourcePluginFactory]) throws {
        for factory in factories {
            let id = factory.descriptor.id
            guard self.factories[id] == nil else { throw PluginRegistryError.duplicate(id) }
            self.factories[id] = factory
        }
    }

    public func register(_ factory: any MediaSourcePluginFactory) throws {
        let id = factory.descriptor.id
        guard factories[id] == nil else { throw PluginRegistryError.duplicate(id) }
        factories[id] = factory
    }

    public func descriptors() -> [CineLarkPluginDescriptor] {
        factories.values.map(\.descriptor).sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public func factory(for id: PluginID) throws -> any MediaSourcePluginFactory {
        guard let factory = factories[id] else { throw PluginRegistryError.notFound(id) }
        return factory
    }
}
