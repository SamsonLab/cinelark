import Foundation
import CineLarkDomain
import CineLarkPluginAPI

public struct ClientID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue.uuidString.lowercased()
    }
}

public struct DeviceRecordID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(clientID: ClientID) {
        rawValue = clientID.rawValue
    }
}

public struct ViewingSessionID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct ProfilePlaybackEventID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct ProfileID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct MutationStamp: Codable, Hashable, Sendable, Comparable {
    public let physicalMillisecondsUTC: Int64
    public let logicalCounter: UInt32
    public let clientID: String

    public init(
        physicalMillisecondsUTC: Int64,
        logicalCounter: UInt32,
        clientID: String
    ) {
        self.physicalMillisecondsUTC = physicalMillisecondsUTC
        self.logicalCounter = logicalCounter
        self.clientID = clientID
    }

    public init(date: Date, logicalCounter: UInt32 = 0, clientID: String) {
        self.init(
            physicalMillisecondsUTC: Int64((date.timeIntervalSince1970 * 1_000).rounded()),
            logicalCounter: logicalCounter,
            clientID: clientID
        )
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.physicalMillisecondsUTC != rhs.physicalMillisecondsUTC {
            return lhs.physicalMillisecondsUTC < rhs.physicalMillisecondsUTC
        }
        if lhs.logicalCounter != rhs.logicalCounter {
            return lhs.logicalCounter < rhs.logicalCounter
        }
        return lhs.clientID < rhs.clientID
    }
}

public struct MutationClockState: Codable, Hashable, Sendable {
    public let clientID: ClientID
    public private(set) var lastStamp: MutationStamp?

    public init(clientID: ClientID, lastStamp: MutationStamp? = nil) {
        self.clientID = clientID
        self.lastStamp = lastStamp
    }

    public mutating func tick(at wallTime: Date) -> MutationStamp {
        let wallMilliseconds = Int64((wallTime.timeIntervalSince1970 * 1_000).rounded())
        var physicalMilliseconds = max(
            wallMilliseconds,
            lastStamp?.physicalMillisecondsUTC ?? wallMilliseconds
        )
        let logicalCounter: UInt32
        if let lastStamp, physicalMilliseconds == lastStamp.physicalMillisecondsUTC {
            if lastStamp.logicalCounter == .max {
                physicalMilliseconds += 1
                logicalCounter = 0
            } else {
                logicalCounter = lastStamp.logicalCounter + 1
            }
        } else {
            logicalCounter = 0
        }
        let next = MutationStamp(
            physicalMillisecondsUTC: physicalMilliseconds,
            logicalCounter: logicalCounter,
            clientID: clientID.description
        )
        lastStamp = next
        return next
    }

    public mutating func observe(_ remote: MutationStamp) {
        guard let lastStamp else {
            self.lastStamp = remote
            return
        }
        if remote > lastStamp {
            self.lastStamp = remote
        }
    }
}

public struct Profile: Codable, Hashable, Sendable, Identifiable {
    public let id: ProfileID
    public let name: String
    public let createdAt: Date
    public let modifiedAt: Date
    public let deviceID: String
    public let mutationStamp: MutationStamp?
    public let deletedAt: Date?
    public let mergedIntoProfileID: ProfileID?

    public init(
        id: ProfileID,
        name: String,
        createdAt: Date,
        modifiedAt: Date,
        deviceID: String,
        mutationStamp: MutationStamp? = nil,
        deletedAt: Date? = nil,
        mergedIntoProfileID: ProfileID? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deviceID = deviceID
        self.mutationStamp = mutationStamp
        self.deletedAt = deletedAt
        self.mergedIntoProfileID = mergedIntoProfileID
    }

    public var effectiveMutationStamp: MutationStamp {
        mutationStamp ?? MutationStamp(date: modifiedAt, clientID: deviceID)
    }

    public func withMutationStamp(_ stamp: MutationStamp) -> Self {
        Self(
            id: id,
            name: name,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            deviceID: deviceID,
            mutationStamp: stamp,
            deletedAt: deletedAt,
            mergedIntoProfileID: mergedIntoProfileID
        )
    }

    public func merged(into targetProfileID: ProfileID, at date: Date, stamp: MutationStamp) -> Self {
        Self(
            id: id,
            name: name,
            createdAt: createdAt,
            modifiedAt: date,
            deviceID: stamp.clientID,
            mutationStamp: stamp,
            deletedAt: deletedAt,
            mergedIntoProfileID: targetProfileID
        )
    }

    public func tombstoned(at date: Date, stamp: MutationStamp) -> Self {
        Self(
            id: id,
            name: name,
            createdAt: createdAt,
            modifiedAt: date,
            deviceID: stamp.clientID,
            mutationStamp: stamp,
            deletedAt: date,
            mergedIntoProfileID: mergedIntoProfileID
        )
    }
}

public struct ProfileManifest: Codable, Hashable, Sendable, Identifiable {
    public var id: ProfileID { profile.id }
    public let profile: Profile
    public let lastActivityAt: Date?
    public let lastDeviceName: String?
    public let titleCount: Int
    public let viewingSessionCount: Int
    public let favoriteCount: Int
    public let totalWatchSeconds: Int64

    public init(
        profile: Profile,
        lastActivityAt: Date?,
        lastDeviceName: String?,
        titleCount: Int,
        viewingSessionCount: Int,
        favoriteCount: Int,
        totalWatchSeconds: Int64
    ) {
        self.profile = profile
        self.lastActivityAt = lastActivityAt
        self.lastDeviceName = lastDeviceName
        self.titleCount = titleCount
        self.viewingSessionCount = viewingSessionCount
        self.favoriteCount = favoriteCount
        self.totalWatchSeconds = totalWatchSeconds
    }

    public var hasMeaningfulData: Bool {
        titleCount > 0 || viewingSessionCount > 0 || favoriteCount > 0 || totalWatchSeconds > 0
    }
}

public enum CloudProfileAvailability: Codable, Hashable, Sendable {
    case unavailable
    case pendingInitialImport
    case available
}

public struct ProfileBootstrapInput: Codable, Hashable, Sendable {
    public let provisionalProfile: ProfileManifest?
    public let cloudProfiles: [ProfileManifest]
    public let activeProfileID: ProfileID?
    public let cloudAvailability: CloudProfileAvailability

    public init(
        provisionalProfile: ProfileManifest?,
        cloudProfiles: [ProfileManifest],
        activeProfileID: ProfileID?,
        cloudAvailability: CloudProfileAvailability
    ) {
        self.provisionalProfile = provisionalProfile
        self.cloudProfiles = cloudProfiles
        self.activeProfileID = activeProfileID
        self.cloudAvailability = cloudAvailability
    }
}

public enum ProfileBootstrapResolution: Codable, Hashable, Sendable {
    case localOnly(ProfileManifest)
    case waitingForCloud(ProfileManifest?)
    case promoteProvisional(ProfileManifest)
    case synchronize(ProfileManifest)
    case requiresChoice(provisional: ProfileManifest, cloudProfiles: [ProfileManifest])
}

public enum ProfileBootstrapResolver {
    public static func resolve(_ input: ProfileBootstrapInput) -> ProfileBootstrapResolution {
        let visibleCloudProfiles = input.cloudProfiles.filter {
            $0.profile.deletedAt == nil && $0.profile.mergedIntoProfileID == nil
        }
        let activeCloudProfile = input.activeProfileID.flatMap { activeProfileID in
            visibleCloudProfiles.first { $0.id == activeProfileID }
        }
        switch input.cloudAvailability {
        case .unavailable:
            if let activeCloudProfile {
                return .localOnly(activeCloudProfile)
            }
            if let provisionalProfile = input.provisionalProfile {
                return .localOnly(provisionalProfile)
            }
            return .waitingForCloud(nil)
        case .pendingInitialImport:
            if let activeCloudProfile {
                return .synchronize(activeCloudProfile)
            }
            return .waitingForCloud(input.provisionalProfile)
        case .available:
            if let activeCloudProfile {
                return .synchronize(activeCloudProfile)
            }
            if visibleCloudProfiles.isEmpty {
                if let provisionalProfile = input.provisionalProfile {
                    return .promoteProvisional(provisionalProfile)
                }
                return .waitingForCloud(nil)
            }
            if let provisionalProfile = input.provisionalProfile,
               let matching = visibleCloudProfiles.first(where: {
                   $0.id == provisionalProfile.id
               }) {
                return .synchronize(matching)
            }
            guard let provisionalProfile = input.provisionalProfile else {
                return .waitingForCloud(nil)
            }
            return .requiresChoice(
                provisional: provisionalProfile,
                cloudProfiles: visibleCloudProfiles.sorted {
                    ($0.lastActivityAt ?? $0.profile.modifiedAt) >
                        ($1.lastActivityAt ?? $1.profile.modifiedAt)
                }
            )
        }
    }
}

public enum ProfileResolutionChoice: Codable, Hashable, Sendable {
    case useCloud(ProfileID)
    case mergeIntoCloud(ProfileID)
    case keepSeparate
}

public struct ProfileMergeRequest: Codable, Hashable, Sendable {
    public let operationID: UUID
    public let sourceProfileID: ProfileID
    public let targetProfileID: ProfileID
    public let mergedAt: Date
    public let mutationStamp: MutationStamp

    public init(
        operationID: UUID,
        sourceProfileID: ProfileID,
        targetProfileID: ProfileID,
        mergedAt: Date,
        mutationStamp: MutationStamp
    ) {
        self.operationID = operationID
        self.sourceProfileID = sourceProfileID
        self.targetProfileID = targetProfileID
        self.mergedAt = mergedAt
        self.mutationStamp = mutationStamp
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
    public let mutationStamp: MutationStamp?

    public init(
        key: ProfileMediaKey,
        locator: MediaLocatorID,
        title: String,
        kind: MediaKind,
        artworkURL: URL?,
        modifiedAt: Date,
        deviceID: String,
        mutationStamp: MutationStamp? = nil
    ) {
        self.key = key
        self.locator = locator
        self.title = title
        self.kind = kind
        self.artworkURL = artworkURL
        self.modifiedAt = modifiedAt
        self.deviceID = deviceID
        self.mutationStamp = mutationStamp
    }

    public var effectiveMutationStamp: MutationStamp {
        mutationStamp ?? MutationStamp(date: modifiedAt, clientID: deviceID)
    }

    public func withMutationStamp(_ stamp: MutationStamp) -> Self {
        Self(
            key: key,
            locator: locator,
            title: title,
            kind: kind,
            artworkURL: artworkURL,
            modifiedAt: modifiedAt,
            deviceID: deviceID,
            mutationStamp: stamp
        )
    }
}

public struct ProfileFavoriteState: Codable, Hashable, Sendable {
    public let profileID: ProfileID
    public let mediaKey: ProfileMediaKey
    public let isFavorite: Bool
    public let modifiedAt: Date
    public let deviceID: String
    public let mutationStamp: MutationStamp?

    public init(
        profileID: ProfileID,
        mediaKey: ProfileMediaKey,
        isFavorite: Bool,
        modifiedAt: Date,
        deviceID: String,
        mutationStamp: MutationStamp? = nil
    ) {
        self.profileID = profileID
        self.mediaKey = mediaKey
        self.isFavorite = isFavorite
        self.modifiedAt = modifiedAt
        self.deviceID = deviceID
        self.mutationStamp = mutationStamp
    }

    public var effectiveMutationStamp: MutationStamp {
        mutationStamp ?? MutationStamp(date: modifiedAt, clientID: deviceID)
    }

    public func withMutationStamp(_ stamp: MutationStamp, profileID: ProfileID? = nil) -> Self {
        Self(
            profileID: profileID ?? self.profileID,
            mediaKey: mediaKey,
            isFavorite: isFavorite,
            modifiedAt: modifiedAt,
            deviceID: deviceID,
            mutationStamp: stamp
        )
    }
}

public struct ProfilePlaybackState: Codable, Hashable, Sendable {
    public let profileID: ProfileID
    public let mediaKey: ProfileMediaKey
    public let state: UserPlaybackState
    public let modifiedAt: Date
    public let deviceID: String
    public let mutationStamp: MutationStamp?

    public init(
        profileID: ProfileID,
        mediaKey: ProfileMediaKey,
        state: UserPlaybackState,
        modifiedAt: Date,
        deviceID: String,
        mutationStamp: MutationStamp? = nil
    ) {
        self.profileID = profileID
        self.mediaKey = mediaKey
        self.state = state
        self.modifiedAt = modifiedAt
        self.deviceID = deviceID
        self.mutationStamp = mutationStamp
    }

    public var effectiveMutationStamp: MutationStamp {
        mutationStamp ?? MutationStamp(date: modifiedAt, clientID: deviceID)
    }

    public func withMutationStamp(_ stamp: MutationStamp, profileID: ProfileID? = nil) -> Self {
        Self(
            profileID: profileID ?? self.profileID,
            mediaKey: mediaKey,
            state: state,
            modifiedAt: modifiedAt,
            deviceID: deviceID,
            mutationStamp: stamp
        )
    }
}

public struct DeviceRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: DeviceRecordID
    public let clientID: ClientID
    public let displayName: String
    public let platform: String
    public let lastSeenAt: Date
    public let mutationStamp: MutationStamp?

    public init(
        id: DeviceRecordID,
        clientID: ClientID,
        displayName: String,
        platform: String,
        lastSeenAt: Date,
        mutationStamp: MutationStamp? = nil
    ) {
        self.id = id
        self.clientID = clientID
        self.displayName = displayName
        self.platform = platform
        self.lastSeenAt = lastSeenAt
        self.mutationStamp = mutationStamp
    }

    public var effectiveMutationStamp: MutationStamp {
        mutationStamp ?? MutationStamp(date: lastSeenAt, clientID: clientID.description)
    }

    public func withMutationStamp(_ stamp: MutationStamp) -> Self {
        Self(
            id: id,
            clientID: clientID,
            displayName: displayName,
            platform: platform,
            lastSeenAt: lastSeenAt,
            mutationStamp: stamp
        )
    }
}

public enum ViewingSessionStatus: String, Codable, Hashable, Sendable {
    case active
    case stopped
    case completed
}

public struct ViewingSession: Codable, Hashable, Sendable, Identifiable {
    public let id: ViewingSessionID
    public let profileID: ProfileID
    public let mediaKey: ProfileMediaKey
    public let deviceRecordID: DeviceRecordID
    public let startedAt: Date
    public let endedAt: Date?
    public let startPositionSeconds: Double
    public let endPositionSeconds: Double
    public let watchedSeconds: Double
    public let status: ViewingSessionStatus
    public let modifiedAt: Date
    public let deviceID: String
    public let mutationStamp: MutationStamp?

    public init(
        id: ViewingSessionID,
        profileID: ProfileID,
        mediaKey: ProfileMediaKey,
        deviceRecordID: DeviceRecordID,
        startedAt: Date,
        endedAt: Date?,
        startPositionSeconds: Double,
        endPositionSeconds: Double,
        watchedSeconds: Double,
        status: ViewingSessionStatus,
        modifiedAt: Date,
        deviceID: String,
        mutationStamp: MutationStamp? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.mediaKey = mediaKey
        self.deviceRecordID = deviceRecordID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.startPositionSeconds = startPositionSeconds
        self.endPositionSeconds = endPositionSeconds
        self.watchedSeconds = watchedSeconds
        self.status = status
        self.modifiedAt = modifiedAt
        self.deviceID = deviceID
        self.mutationStamp = mutationStamp
    }

    public var effectiveMutationStamp: MutationStamp {
        mutationStamp ?? MutationStamp(date: modifiedAt, clientID: deviceID)
    }

    public func withMutationStamp(
        _ stamp: MutationStamp,
        profileID: ProfileID? = nil
    ) -> Self {
        Self(
            id: id,
            profileID: profileID ?? self.profileID,
            mediaKey: mediaKey,
            deviceRecordID: deviceRecordID,
            startedAt: startedAt,
            endedAt: endedAt,
            startPositionSeconds: startPositionSeconds,
            endPositionSeconds: endPositionSeconds,
            watchedSeconds: watchedSeconds,
            status: status,
            modifiedAt: modifiedAt,
            deviceID: deviceID,
            mutationStamp: stamp
        )
    }
}

public enum ProfilePlaybackEventKind: String, Codable, Hashable, Sendable {
    case started
    case checkpoint
    case paused
    case resumed
    case stopped
    case completed
}

public struct ProfilePlaybackEvent: Codable, Hashable, Sendable, Identifiable {
    public let id: ProfilePlaybackEventID
    public let sessionID: ViewingSessionID
    public let profileID: ProfileID
    public let mediaKey: ProfileMediaKey
    public let deviceRecordID: DeviceRecordID
    public let kind: ProfilePlaybackEventKind
    public let observedAt: Date
    public let positionSeconds: Double
    public let durationSeconds: Double
    public let isPaused: Bool
    public let deviceID: String
    public let mutationStamp: MutationStamp?

    public init(
        id: ProfilePlaybackEventID,
        sessionID: ViewingSessionID,
        profileID: ProfileID,
        mediaKey: ProfileMediaKey,
        deviceRecordID: DeviceRecordID,
        kind: ProfilePlaybackEventKind,
        observedAt: Date,
        positionSeconds: Double,
        durationSeconds: Double,
        isPaused: Bool,
        deviceID: String,
        mutationStamp: MutationStamp? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.profileID = profileID
        self.mediaKey = mediaKey
        self.deviceRecordID = deviceRecordID
        self.kind = kind
        self.observedAt = observedAt
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.isPaused = isPaused
        self.deviceID = deviceID
        self.mutationStamp = mutationStamp
    }

    public var effectiveMutationStamp: MutationStamp {
        mutationStamp ?? MutationStamp(date: observedAt, clientID: deviceID)
    }

    public func withMutationStamp(
        _ stamp: MutationStamp,
        profileID: ProfileID? = nil
    ) -> Self {
        Self(
            id: id,
            sessionID: sessionID,
            profileID: profileID ?? self.profileID,
            mediaKey: mediaKey,
            deviceRecordID: deviceRecordID,
            kind: kind,
            observedAt: observedAt,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            isPaused: isPaused,
            deviceID: deviceID,
            mutationStamp: stamp
        )
    }
}

public struct ProfilePlaybackWrite: Codable, Hashable, Sendable {
    public let state: ProfilePlaybackState
    public let snapshot: ProfileMediaSnapshot?
    public let session: ViewingSession?
    public let event: ProfilePlaybackEvent?
    public let deviceRecord: DeviceRecord?

    public init(
        state: ProfilePlaybackState,
        snapshot: ProfileMediaSnapshot?,
        session: ViewingSession?,
        event: ProfilePlaybackEvent?,
        deviceRecord: DeviceRecord?
    ) {
        self.state = state
        self.snapshot = snapshot
        self.session = session
        self.event = event
        self.deviceRecord = deviceRecord
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
    case bootstrap
}

public enum ProfileRepositoryError: Error, Equatable, Sendable {
    case profileNotFound(ProfileID)
    case provisionalProfileNotFound(ProfileID)
    case provisionalProfileHasData(ProfileID)
    case invalidProfileMerge
    case sourceNotFound(SourceID)
    case mirrorOwnerConflict(existing: ProfileID)
    case invalidRecord
}
