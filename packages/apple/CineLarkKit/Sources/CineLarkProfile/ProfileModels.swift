import Foundation
import CineLarkDomain
import CineLarkPluginAPI

public struct ProfileID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct Profile: Codable, Hashable, Sendable, Identifiable {
    public let id: ProfileID
    public let name: String
    public let createdAt: Date
    public let modifiedAt: Date
    public let deviceID: String

    public init(
        id: ProfileID,
        name: String,
        createdAt: Date,
        modifiedAt: Date,
        deviceID: String
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deviceID = deviceID
    }
}

public struct ProfileMediaKey: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(locator: MediaLocatorID) {
        rawValue = "locator:\(locator.sourceID.rawValue.uuidString):\(locator.providerItemID)"
    }
}

public struct ProfileMediaSnapshot: Codable, Hashable, Sendable {
    public let key: ProfileMediaKey
    public let locator: MediaLocatorID
    public let title: String
    public let kind: MediaKind
    public let artworkURL: URL?
    public let modifiedAt: Date
    public let deviceID: String

    public init(
        key: ProfileMediaKey,
        locator: MediaLocatorID,
        title: String,
        kind: MediaKind,
        artworkURL: URL?,
        modifiedAt: Date,
        deviceID: String
    ) {
        self.key = key
        self.locator = locator
        self.title = title
        self.kind = kind
        self.artworkURL = artworkURL
        self.modifiedAt = modifiedAt
        self.deviceID = deviceID
    }
}

public struct ProfileFavoriteState: Codable, Hashable, Sendable {
    public let profileID: ProfileID
    public let mediaKey: ProfileMediaKey
    public let isFavorite: Bool
    public let modifiedAt: Date
    public let deviceID: String

    public init(
        profileID: ProfileID,
        mediaKey: ProfileMediaKey,
        isFavorite: Bool,
        modifiedAt: Date,
        deviceID: String
    ) {
        self.profileID = profileID
        self.mediaKey = mediaKey
        self.isFavorite = isFavorite
        self.modifiedAt = modifiedAt
        self.deviceID = deviceID
    }
}

public struct ProfilePlaybackState: Codable, Hashable, Sendable {
    public let profileID: ProfileID
    public let mediaKey: ProfileMediaKey
    public let state: UserPlaybackState
    public let modifiedAt: Date
    public let deviceID: String

    public init(
        profileID: ProfileID,
        mediaKey: ProfileMediaKey,
        state: UserPlaybackState,
        modifiedAt: Date,
        deviceID: String
    ) {
        self.profileID = profileID
        self.mediaKey = mediaKey
        self.state = state
        self.modifiedAt = modifiedAt
        self.deviceID = deviceID
    }
}

public struct ProfileSourceBinding: Codable, Hashable, Sendable {
    public let profileID: ProfileID
    public let sourceID: SourceID
    public let remoteUserID: String?
    public let mirrorsRemoteState: Bool

    public init(
        profileID: ProfileID,
        sourceID: SourceID,
        remoteUserID: String?,
        mirrorsRemoteState: Bool
    ) {
        self.profileID = profileID
        self.sourceID = sourceID
        self.remoteUserID = remoteUserID
        self.mirrorsRemoteState = mirrorsRemoteState
    }
}

public struct PersistedMediaSource: Codable, Hashable, Sendable, Identifiable {
    public var id: SourceID { configuration.sourceID }
    public let pluginID: PluginID
    public let configuration: SourceConfiguration

    public init(pluginID: PluginID, configuration: SourceConfiguration) {
        self.pluginID = pluginID
        self.configuration = configuration
    }
}

public struct ActiveProfileSelection: Codable, Hashable, Sendable {
    public let profileID: ProfileID?
    public let sourceID: SourceID?

    public init(profileID: ProfileID?, sourceID: SourceID?) {
        self.profileID = profileID
        self.sourceID = sourceID
    }
}

public struct RemoteStateImportBatch: Codable, Hashable, Sendable {
    public let marker: String
    public let profileID: ProfileID
    public let sourceID: SourceID
    public let remoteUserID: String
    public let snapshots: [ProfileMediaSnapshot]
    public let favorites: [ProfileFavoriteState]
    public let playback: [ProfilePlaybackState]

    public init(
        marker: String,
        profileID: ProfileID,
        sourceID: SourceID,
        remoteUserID: String,
        snapshots: [ProfileMediaSnapshot],
        favorites: [ProfileFavoriteState],
        playback: [ProfilePlaybackState]
    ) {
        self.marker = marker
        self.profileID = profileID
        self.sourceID = sourceID
        self.remoteUserID = remoteUserID
        self.snapshots = snapshots
        self.favorites = favorites
        self.playback = playback
    }
}

public enum MirrorMutation: Codable, Hashable, Sendable {
    case favorite(ProfileFavoriteState)
    case playback(ProfilePlaybackState)
}

public struct MirrorQueueEntry: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let profileID: ProfileID
    public let sourceID: SourceID
    public let remoteUserID: String
    public let locator: MediaLocatorID?
    public let mutation: MirrorMutation
    public let attempts: Int
    public let nextAttemptAt: Date

    public init(
        id: UUID,
        profileID: ProfileID,
        sourceID: SourceID,
        remoteUserID: String,
        locator: MediaLocatorID? = nil,
        mutation: MirrorMutation,
        attempts: Int = 0,
        nextAttemptAt: Date
    ) {
        self.id = id
        self.profileID = profileID
        self.sourceID = sourceID
        self.remoteUserID = remoteUserID
        self.locator = locator
        self.mutation = mutation
        self.attempts = attempts
        self.nextAttemptAt = nextAttemptAt
    }
}

public enum ProfileRepositoryChange: Equatable, Sendable {
    case profiles
    case activeSelection(ActiveProfileSelection)
    case sources
    case userState(ProfileID)
    case mirrorQueue
    case external
}

public enum ProfileRepositoryError: Error, Equatable, Sendable {
    case profileNotFound(ProfileID)
    case sourceNotFound(SourceID)
    case mirrorOwnerConflict(existing: ProfileID)
    case invalidRecord
}
