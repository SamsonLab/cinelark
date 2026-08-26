import Foundation

public struct PluginID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}

public struct SourceID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }
    public init(stringLiteral value: String) {
        guard let value = UUID(uuidString: value) else {
            preconditionFailure("Invalid SourceID literal: \(value)")
        }
        self.rawValue = value
    }
}

public struct SourceInstanceIdentity: Codable, Hashable, Sendable {
    public let pluginID: PluginID
    public let serverID: String

    public init(pluginID: PluginID, serverID: String) {
        self.pluginID = pluginID
        self.serverID = serverID
    }
}

public struct MediaLocatorID: Codable, Hashable, Sendable {
    public let sourceID: SourceID
    public let providerItemID: String

    public init(sourceID: SourceID, providerItemID: String) {
        self.sourceID = sourceID
        self.providerItemID = providerItemID
    }
}

public struct CatalogItemID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public enum ContentKey: Codable, Hashable, Sendable {
    case tmdb(String)
    case imdb(String)
    case episode(series: String, season: Int, episode: Int)
}
