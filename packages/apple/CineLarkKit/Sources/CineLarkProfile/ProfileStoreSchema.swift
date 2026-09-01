@preconcurrency import CoreData
import Foundation

enum ProfileStoreSchema {
    enum StoreConfiguration {
        static let cloud = "Cloud"
        static let local = "Local"
    }

    enum Entity {
        static let profile = "Profile"
        static let favorite = "FavoriteState"
        static let playback = "PlaybackState"
        static let snapshot = "MediaSnapshot"
        static let importMarker = "ImportMarker"
        static let profileMergeMarker = "ProfileMergeMarker"
        static let deviceRecord = "DeviceRecord"
        static let viewingSession = "ViewingSession"
        static let playbackEvent = "ProfilePlaybackEvent"
        static let source = "ProfileSourceRecord"
        static let binding = "ProfileSourceBinding"
        static let activeSelection = "ActiveProfileSelection"
        static let mirrorQueue = "MirrorQueueEntry"
        static let mutationClock = "MutationClockState"
        static let provisionalProfile = "ProvisionalProfile"
        static let provisionalFavorite = "ProvisionalFavoriteState"
        static let provisionalPlayback = "ProvisionalPlaybackState"
        static let provisionalSnapshot = "ProvisionalMediaSnapshot"
        static let provisionalImportMarker = "ProvisionalImportMarker"
        static let provisionalDeviceRecord = "ProvisionalDeviceRecord"
        static let provisionalViewingSession = "ProvisionalViewingSession"
        static let provisionalPlaybackEvent = "ProvisionalPlaybackEvent"
    }

    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let profile = entity(Entity.profile, attributes: [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("modifiedAt", .dateAttributeType),
            attribute("deviceID", .stringAttributeType),
            attribute("mutationPhysicalMillisecondsUTC", .integer64AttributeType),
            attribute("mutationLogicalCounter", .integer64AttributeType),
            attribute("mutationClientID", .stringAttributeType),
            attribute("deletedAt", .dateAttributeType),
            attribute("mergedIntoProfileID", .UUIDAttributeType)
        ])
        let favorite = entity(Entity.favorite, attributes: stateAttributes())
        let playback = entity(Entity.playback, attributes: stateAttributes())
        let snapshot = entity(Entity.snapshot, attributes: [
            attribute("key", .stringAttributeType),
            attribute("modifiedAt", .dateAttributeType),
            attribute("deviceID", .stringAttributeType),
            attribute("mutationPhysicalMillisecondsUTC", .integer64AttributeType),
            attribute("mutationLogicalCounter", .integer64AttributeType),
            attribute("mutationClientID", .stringAttributeType),
            attribute("payload", .binaryDataAttributeType)
        ])
        let importMarker = entity(Entity.importMarker, attributes: [
            attribute("key", .stringAttributeType),
            attribute("profileID", .UUIDAttributeType),
            attribute("sourceID", .UUIDAttributeType),
            attribute("remoteUserID", .stringAttributeType),
            attribute("marker", .stringAttributeType),
            attribute("importedAt", .dateAttributeType)
        ])
        let profileMergeMarker = entity(Entity.profileMergeMarker, attributes: [
            attribute("operationID", .UUIDAttributeType),
            attribute("sourceProfileID", .UUIDAttributeType),
            attribute("targetProfileID", .UUIDAttributeType),
            attribute("mergedAt", .dateAttributeType),
            attribute("payload", .binaryDataAttributeType)
        ])
        let deviceRecord = entity(Entity.deviceRecord, attributes: deviceRecordAttributes())
        let viewingSession = entity(
            Entity.viewingSession,
            attributes: viewingSessionAttributes()
        )
        let playbackEvent = entity(
            Entity.playbackEvent,
            attributes: playbackEventAttributes()
        )
        let source = entity(Entity.source, attributes: [
            requiredAttribute("sourceID", .UUIDAttributeType),
            requiredAttribute("pluginID", .stringAttributeType),
            requiredAttribute("displayName", .stringAttributeType),
            requiredAttribute("configuration", .binaryDataAttributeType),
            requiredAttribute("updatedAt", .dateAttributeType)
        ])
        let binding = entity(Entity.binding, attributes: [
            requiredAttribute("key", .stringAttributeType),
            requiredAttribute("profileID", .UUIDAttributeType),
            requiredAttribute("sourceID", .UUIDAttributeType),
            attribute("remoteUserID", .stringAttributeType),
            requiredAttribute("mirrorsRemoteState", .booleanAttributeType, defaultValue: false)
        ])
        let active = entity(Entity.activeSelection, attributes: [
            requiredAttribute("deviceID", .stringAttributeType),
            attribute("profileID", .UUIDAttributeType),
            attribute("sourceID", .UUIDAttributeType)
        ])
        let mirror = entity(Entity.mirrorQueue, attributes: [
            requiredAttribute("id", .UUIDAttributeType),
            requiredAttribute("profileID", .UUIDAttributeType),
            requiredAttribute("sourceID", .UUIDAttributeType),
            requiredAttribute("remoteUserID", .stringAttributeType),
            requiredAttribute("nextAttemptAt", .dateAttributeType),
            requiredAttribute("payload", .binaryDataAttributeType)
        ])
        let mutationClock = entity(Entity.mutationClock, attributes: [
            requiredAttribute("clientID", .stringAttributeType),
            requiredAttribute("physicalMillisecondsUTC", .integer64AttributeType),
            requiredAttribute("logicalCounter", .integer64AttributeType)
        ])
        let provisionalProfile = entity(Entity.provisionalProfile, attributes: [
            requiredAttribute("clientID", .stringAttributeType),
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("modifiedAt", .dateAttributeType),
            attribute("deviceID", .stringAttributeType),
            attribute("mutationPhysicalMillisecondsUTC", .integer64AttributeType),
            attribute("mutationLogicalCounter", .integer64AttributeType),
            attribute("mutationClientID", .stringAttributeType),
            attribute("deletedAt", .dateAttributeType),
            attribute("mergedIntoProfileID", .UUIDAttributeType)
        ])
        let provisionalFavorite = entity(
            Entity.provisionalFavorite,
            attributes: stateAttributes()
        )
        let provisionalPlayback = entity(
            Entity.provisionalPlayback,
            attributes: stateAttributes()
        )
        let provisionalSnapshot = entity(Entity.provisionalSnapshot, attributes: [
            attribute("key", .stringAttributeType),
            attribute("modifiedAt", .dateAttributeType),
            attribute("deviceID", .stringAttributeType),
            attribute("mutationPhysicalMillisecondsUTC", .integer64AttributeType),
            attribute("mutationLogicalCounter", .integer64AttributeType),
            attribute("mutationClientID", .stringAttributeType),
            attribute("payload", .binaryDataAttributeType)
        ])
        let provisionalImportMarker = entity(Entity.provisionalImportMarker, attributes: [
            attribute("key", .stringAttributeType),
            attribute("profileID", .UUIDAttributeType),
            attribute("sourceID", .UUIDAttributeType),
            attribute("remoteUserID", .stringAttributeType),
            attribute("marker", .stringAttributeType),
            attribute("importedAt", .dateAttributeType)
        ])
        let provisionalDeviceRecord = entity(
            Entity.provisionalDeviceRecord,
            attributes: deviceRecordAttributes()
        )
        let provisionalViewingSession = entity(
            Entity.provisionalViewingSession,
            attributes: viewingSessionAttributes()
        )
        let provisionalPlaybackEvent = entity(
            Entity.provisionalPlaybackEvent,
            attributes: playbackEventAttributes()
        )

        model.entities = [
            profile, favorite, playback, snapshot, importMarker, profileMergeMarker,
            deviceRecord, viewingSession, playbackEvent,
            source, binding, active, mirror, mutationClock, provisionalProfile,
            provisionalFavorite, provisionalPlayback, provisionalSnapshot,
            provisionalImportMarker, provisionalDeviceRecord, provisionalViewingSession,
            provisionalPlaybackEvent
        ]
        model.setEntities(
            [
                profile, favorite, playback, snapshot, importMarker, profileMergeMarker,
                deviceRecord, viewingSession, playbackEvent
            ],
            forConfigurationName: StoreConfiguration.cloud
        )
        model.setEntities(
            [
                source, binding, active, mirror, mutationClock, provisionalProfile,
                provisionalFavorite, provisionalPlayback, provisionalSnapshot,
                provisionalImportMarker, provisionalDeviceRecord,
                provisionalViewingSession, provisionalPlaybackEvent
            ],
            forConfigurationName: StoreConfiguration.local
        )
        return model
    }

    private static func stateAttributes() -> [NSAttributeDescription] {
        [
            attribute("key", .stringAttributeType),
            attribute("profileID", .UUIDAttributeType),
            attribute("mediaKey", .stringAttributeType),
            attribute("modifiedAt", .dateAttributeType),
            attribute("deviceID", .stringAttributeType),
            attribute("mutationPhysicalMillisecondsUTC", .integer64AttributeType),
            attribute("mutationLogicalCounter", .integer64AttributeType),
            attribute("mutationClientID", .stringAttributeType),
            attribute("payload", .binaryDataAttributeType)
        ]
    }

    private static func deviceRecordAttributes() -> [NSAttributeDescription] {
        [
            attribute("id", .UUIDAttributeType),
            attribute("clientID", .stringAttributeType),
            attribute("displayName", .stringAttributeType),
            attribute("platform", .stringAttributeType),
            attribute("lastSeenAt", .dateAttributeType),
            attribute("mutationPhysicalMillisecondsUTC", .integer64AttributeType),
            attribute("mutationLogicalCounter", .integer64AttributeType),
            attribute("mutationClientID", .stringAttributeType),
            attribute("payload", .binaryDataAttributeType)
        ]
    }

    private static func viewingSessionAttributes() -> [NSAttributeDescription] {
        [
            attribute("key", .stringAttributeType),
            attribute("id", .UUIDAttributeType),
            attribute("profileID", .UUIDAttributeType),
            attribute("mediaKey", .stringAttributeType),
            attribute("deviceRecordID", .UUIDAttributeType),
            attribute("startedAt", .dateAttributeType),
            attribute("endedAt", .dateAttributeType),
            attribute("watchedSeconds", .doubleAttributeType),
            attribute("modifiedAt", .dateAttributeType),
            attribute("deviceID", .stringAttributeType),
            attribute("mutationPhysicalMillisecondsUTC", .integer64AttributeType),
            attribute("mutationLogicalCounter", .integer64AttributeType),
            attribute("mutationClientID", .stringAttributeType),
            attribute("payload", .binaryDataAttributeType)
        ]
    }

    private static func playbackEventAttributes() -> [NSAttributeDescription] {
        [
            attribute("key", .stringAttributeType),
            attribute("id", .UUIDAttributeType),
            attribute("sessionID", .UUIDAttributeType),
            attribute("profileID", .UUIDAttributeType),
            attribute("mediaKey", .stringAttributeType),
            attribute("deviceRecordID", .UUIDAttributeType),
            attribute("kind", .stringAttributeType),
            attribute("observedAt", .dateAttributeType),
            attribute("deviceID", .stringAttributeType),
            attribute("mutationPhysicalMillisecondsUTC", .integer64AttributeType),
            attribute("mutationLogicalCounter", .integer64AttributeType),
            attribute("mutationClientID", .stringAttributeType),
            attribute("payload", .binaryDataAttributeType)
        ]
    }

    private static func entity(
        _ name: String,
        attributes: [NSAttributeDescription]
    ) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = "NSManagedObject"
        entity.properties = attributes
        return entity
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        return attribute
    }

    private static func requiredAttribute(
        _ name: String,
        _ type: NSAttributeType,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = false
        attribute.defaultValue = defaultValue
        return attribute
    }
}
