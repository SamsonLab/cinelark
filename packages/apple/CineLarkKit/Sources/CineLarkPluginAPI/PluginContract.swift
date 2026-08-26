import Foundation
import CineLarkDomain

public enum PluginRole: String, Codable, Hashable, Sendable {
    case mediaSource
    case metadataResolver
    case subtitleProvider
    case stateSync
}

public enum SourceSetupMode: String, Codable, Hashable, Sendable {
    case manualURL
    case localDiscovery
    case fileSystem
}

public enum AuthenticationMode: String, Codable, Hashable, Sendable {
    case none
    case usernamePassword
    case token
    case web
}

public enum PaginationModel: String, Codable, Hashable, Sendable {
    case offset
    case page
    case opaqueCursor
}

public enum PlaybackMode: String, Codable, Hashable, Sendable {
    case directPlay
    case directStream
    case transcoding
}

public enum MediaMutation: String, Codable, Hashable, Sendable {
    case favorite
    case played
    case progress
}

public struct CapabilityDescriptor: Codable, Hashable, Sendable {
    public let itemKinds: Set<MediaKind>
    public let sortFields: Set<MediaSort.Field>
    public let filters: Set<String>
    public let pagination: PaginationModel
    public let playbackModes: Set<PlaybackMode>
    public let mutations: Set<MediaMutation>

    public init(
        itemKinds: Set<MediaKind>,
        sortFields: Set<MediaSort.Field>,
        filters: Set<String>,
        pagination: PaginationModel,
        playbackModes: Set<PlaybackMode>,
        mutations: Set<MediaMutation>
    ) {
        self.itemKinds = itemKinds
        self.sortFields = sortFields
        self.filters = filters
        self.pagination = pagination
        self.playbackModes = playbackModes
        self.mutations = mutations
    }
}

public struct CineLarkPluginDescriptor: Codable, Hashable, Sendable {
    public let id: PluginID
    public let contractVersion: Int
    public let displayName: String
    public let roles: Set<PluginRole>
    public let setupModes: Set<SourceSetupMode>
    public let authenticationModes: Set<AuthenticationMode>
    public let capabilities: CapabilityDescriptor

    public init(
        id: PluginID,
        contractVersion: Int,
        displayName: String,
        roles: Set<PluginRole>,
        setupModes: Set<SourceSetupMode>,
        authenticationModes: Set<AuthenticationMode>,
        capabilities: CapabilityDescriptor
    ) {
        self.id = id
        self.contractVersion = contractVersion
        self.displayName = displayName
        self.roles = roles
        self.setupModes = setupModes
        self.authenticationModes = authenticationModes
        self.capabilities = capabilities
    }
}

public struct SourceConfiguration: Codable, Hashable, Sendable {
    public let sourceID: SourceID
    public let baseURL: URL
    public let serverIdentity: SourceInstanceIdentity
    public let displayName: String
    public let remoteUserID: String?

    public init(
        sourceID: SourceID,
        baseURL: URL,
        serverIdentity: SourceInstanceIdentity,
        displayName: String,
        remoteUserID: String? = nil
    ) {
        self.sourceID = sourceID
        self.baseURL = baseURL
        self.serverIdentity = serverIdentity
        self.displayName = displayName
        self.remoteUserID = remoteUserID
    }
}

public struct SourceCredentials: Sendable, Equatable {
    public let username: String?
    public let password: String?
    public let token: String?

    public init(username: String? = nil, password: String? = nil, token: String? = nil) {
        self.username = username
        self.password = password
        self.token = token
    }
}
