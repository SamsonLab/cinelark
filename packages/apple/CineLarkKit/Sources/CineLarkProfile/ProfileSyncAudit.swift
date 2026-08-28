import CryptoKit
import Foundation

public struct ProfileSyncAuditSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let capturedAt: Date
    public let syncPhase: ProfileCloudSyncPhase
    public let activeOperations: [ProfileCloudSyncOperation]
    public let lastSuccessfulSyncAt: Date?
    public let hasSyncFailure: Bool
    public let deviceCount: Int
    public let profileSetDigest: String
    public let profiles: [ProfileSyncAuditProfile]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        capturedAt: Date,
        syncPhase: ProfileCloudSyncPhase,
        activeOperations: [ProfileCloudSyncOperation],
        lastSuccessfulSyncAt: Date?,
        hasSyncFailure: Bool,
        deviceCount: Int,
        profileSetDigest: String,
        profiles: [ProfileSyncAuditProfile]
    ) {
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.syncPhase = syncPhase
        self.activeOperations = activeOperations
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.hasSyncFailure = hasSyncFailure
        self.deviceCount = deviceCount
        self.profileSetDigest = profileSetDigest
        self.profiles = profiles
    }

    public static func capture(
        repository: any ProfileRepository,
        capturedAt: Date
    ) async throws -> Self {
        async let profileValues = repository.profiles()
        async let deviceValues = repository.deviceRecords()
        async let syncValue = repository.cloudSyncStatus()
        let (profiles, devices, syncStatus) = try await (
            profileValues,
            deviceValues,
            syncValue
        )

        var audits: [ProfileSyncAuditProfile] = []
        for profile in profiles.sorted(by: Self.profileOrder) {
            async let favoriteValues = repository.favorites(profileID: profile.id)
            async let playbackValues = repository.playbackStates(profileID: profile.id)
            async let sessionValues = repository.viewingSessions(profileID: profile.id)
            async let eventValues = repository.playbackEvents(profileID: profile.id)
            let (favorites, playback, sessions, events) = try await (
                favoriteValues,
                playbackValues,
                sessionValues,
                eventValues
            )
            let sortedFavorites = favorites.sorted { $0.mediaKey.rawValue < $1.mediaKey.rawValue }
            let sortedPlayback = playback.sorted { $0.mediaKey.rawValue < $1.mediaKey.rawValue }
            let sortedSessions = sessions.sorted {
                $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
            }
            let sortedEvents = events.sorted {
                $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
            }
            let mediaKeys = Set(
                sortedFavorites.map(\.mediaKey)
                    + sortedPlayback.map(\.mediaKey)
                    + sortedSessions.map(\.mediaKey)
                    + sortedEvents.map(\.mediaKey)
            )
            let snapshots = try await repository.mediaSnapshots(keys: mediaKeys).sorted {
                $0.key.rawValue < $1.key.rawValue
            }
            let envelope = ProfileAuditFactEnvelope(
                profile: profile,
                favorites: sortedFavorites,
                playback: sortedPlayback,
                snapshots: snapshots,
                sessions: sortedSessions,
                events: sortedEvents
            )
            let mutationMilliseconds = Self.latestMutationMilliseconds(
                profile: profile,
                favorites: sortedFavorites,
                playback: sortedPlayback,
                snapshots: snapshots,
                sessions: sortedSessions,
                events: sortedEvents
            )
            audits.append(ProfileSyncAuditProfile(
                profileFingerprint: try Self.digest(profile.id.rawValue.uuidString.lowercased()),
                favoriteStateCount: sortedFavorites.count,
                playbackStateCount: sortedPlayback.count,
                mediaSnapshotCount: snapshots.count,
                viewingSessionCount: sortedSessions.count,
                playbackEventCount: sortedEvents.count,
                latestMutationMillisecondsUTC: mutationMilliseconds,
                factDigest: try Self.digest(envelope)
            ))
        }

        return try Self(
            capturedAt: capturedAt,
            syncPhase: syncStatus.phase,
            activeOperations: syncStatus.activeOperations.sorted { $0.rawValue < $1.rawValue },
            lastSuccessfulSyncAt: syncStatus.lastSuccessfulAt,
            hasSyncFailure: syncStatus.failureDescription != nil,
            deviceCount: devices.count,
            profileSetDigest: digest(audits),
            profiles: audits
        )
    }

    public func encodedData() throws -> Data {
        let encoder = Self.encoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    private static func profileOrder(_ lhs: Profile, _ rhs: Profile) -> Bool {
        lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }

    private static func latestMutationMilliseconds(
        profile: Profile,
        favorites: [ProfileFavoriteState],
        playback: [ProfilePlaybackState],
        snapshots: [ProfileMediaSnapshot],
        sessions: [ViewingSession],
        events: [ProfilePlaybackEvent]
    ) -> Int64 {
        var values = [profile.effectiveMutationStamp.physicalMillisecondsUTC]
        values += favorites.map { $0.effectiveMutationStamp.physicalMillisecondsUTC }
        values += playback.map { $0.effectiveMutationStamp.physicalMillisecondsUTC }
        values += snapshots.map { $0.effectiveMutationStamp.physicalMillisecondsUTC }
        values += sessions.map { $0.effectiveMutationStamp.physicalMillisecondsUTC }
        values += events.map { $0.effectiveMutationStamp.physicalMillisecondsUTC }
        return values.max() ?? 0
    }

    private static func digest<Value: Encodable>(_ value: Value) throws -> String {
        let hash = SHA256.hash(data: try encoder().encode(value))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
}

public struct ProfileSyncAuditProfile: Codable, Equatable, Sendable {
    public let profileFingerprint: String
    public let favoriteStateCount: Int
    public let playbackStateCount: Int
    public let mediaSnapshotCount: Int
    public let viewingSessionCount: Int
    public let playbackEventCount: Int
    public let latestMutationMillisecondsUTC: Int64
    public let factDigest: String

    public init(
        profileFingerprint: String,
        favoriteStateCount: Int,
        playbackStateCount: Int,
        mediaSnapshotCount: Int,
        viewingSessionCount: Int,
        playbackEventCount: Int,
        latestMutationMillisecondsUTC: Int64,
        factDigest: String
    ) {
        self.profileFingerprint = profileFingerprint
        self.favoriteStateCount = favoriteStateCount
        self.playbackStateCount = playbackStateCount
        self.mediaSnapshotCount = mediaSnapshotCount
        self.viewingSessionCount = viewingSessionCount
        self.playbackEventCount = playbackEventCount
        self.latestMutationMillisecondsUTC = latestMutationMillisecondsUTC
        self.factDigest = factDigest
    }
}

private struct ProfileAuditFactEnvelope: Encodable {
    let profile: Profile
    let favorites: [ProfileFavoriteState]
    let playback: [ProfilePlaybackState]
    let snapshots: [ProfileMediaSnapshot]
    let sessions: [ViewingSession]
    let events: [ProfilePlaybackEvent]
}
