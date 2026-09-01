@preconcurrency import CoreData
import Foundation
import CineLarkPluginAPI

extension CoreDataProfileRepository {
    public func provisionalProfileManifest(clientID: ClientID) async throws -> ProfileManifest? {
        guard let profile = try await provisionalProfile(clientID: clientID) else { return nil }
        return try await manifest(
            profile: profile,
            favoriteEntity: Entity.provisionalFavorite,
            playbackEntity: Entity.provisionalPlayback,
            snapshotEntity: Entity.provisionalSnapshot,
            sessionEntity: Entity.provisionalViewingSession,
            deviceEntity: Entity.provisionalDeviceRecord
        )
    }

    public func saveProvisionalProfile(_ profile: Profile, clientID: ClientID) async throws {
        try await context.perform { [context] in
            let object = try Self.fetchOne(
                entity: Entity.provisionalProfile,
                key: "clientID",
                value: clientID.description,
                context: context
            ) ?? NSEntityDescription.insertNewObject(
                forEntityName: Entity.provisionalProfile,
                into: context
            )
            if let existing = Self.decodeProfile(object),
               profile.effectiveMutationStamp <= existing.effectiveMutationStamp {
                return
            }
            object.setValue(clientID.description, forKey: "clientID")
            Self.writeProfile(profile, to: object)
            try Self.save(context)
        }
        changeHub.yield(.profiles)
    }

    public func promoteProvisionalProfile(
        clientID: ClientID,
        profileID: ProfileID
    ) async throws {
        try await context.perform { [context] in
            guard let provisionalObject = try Self.provisionalProfileObject(
                clientID: clientID,
                profileID: profileID,
                context: context
            ), let profile = Self.decodeProfile(provisionalObject) else {
                if try Self.fetchOne(
                    entity: Entity.profile,
                    key: "id",
                    value: profileID.rawValue,
                    context: context
                ) != nil {
                    return
                }
                throw ProfileRepositoryError.provisionalProfileNotFound(profileID)
            }

            let cloudProfile = try Self.fetchOne(
                entity: Entity.profile,
                key: "id",
                value: profileID.rawValue,
                context: context
            ) ?? NSEntityDescription.insertNewObject(forEntityName: Entity.profile, into: context)
            if let existing = Self.decodeProfile(cloudProfile) {
                if profile.effectiveMutationStamp > existing.effectiveMutationStamp {
                    Self.writeProfile(profile, to: cloudProfile)
                }
            } else {
                Self.writeProfile(profile, to: cloudProfile)
            }
            try Self.copyProvisionalState(
                sourceProfileID: profileID,
                targetProfileID: profileID,
                context: context
            )
            try Self.save(context)
            try Self.deleteProvisionalData(
                clientID: clientID,
                profileID: profileID,
                context: context
            )
            try Self.save(context)
        }
        changeHub.yield(.profiles)
        changeHub.yield(.userState(profileID))
    }

    public func discardProvisionalProfile(
        clientID: ClientID,
        profileID: ProfileID
    ) async throws {
        try await context.perform { [context] in
            guard try Self.provisionalProfileObject(
                clientID: clientID,
                profileID: profileID,
                context: context
            ) != nil else {
                return
            }
            guard try !Self.provisionalHasMeaningfulData(profileID: profileID, context: context) else {
                throw ProfileRepositoryError.provisionalProfileHasData(profileID)
            }
            try Self.deleteProvisionalData(
                clientID: clientID,
                profileID: profileID,
                context: context
            )
            try Self.save(context)
        }
        changeHub.yield(.profiles)
    }

    @discardableResult
    public func mergeProvisionalProfile(
        clientID: ClientID,
        request: ProfileMergeRequest
    ) async throws -> Bool {
        guard request.sourceProfileID != request.targetProfileID else {
            throw ProfileRepositoryError.invalidProfileMerge
        }
        let applied = try await context.perform { [context] in
            if try Self.fetchOne(
                entity: Entity.profileMergeMarker,
                key: "operationID",
                value: request.operationID,
                context: context
            ) != nil {
                try Self.deleteProvisionalData(
                    clientID: clientID,
                    profileID: request.sourceProfileID,
                    context: context
                )
                try Self.save(context)
                return false
            }
            guard try Self.provisionalProfileObject(
                clientID: clientID,
                profileID: request.sourceProfileID,
                context: context
            ) != nil else {
                throw ProfileRepositoryError.provisionalProfileNotFound(request.sourceProfileID)
            }
            guard try Self.fetchOne(
                entity: Entity.profile,
                key: "id",
                value: request.targetProfileID.rawValue,
                context: context
            ) != nil else {
                throw ProfileRepositoryError.profileNotFound(request.targetProfileID)
            }

            try Self.copyProvisionalState(
                sourceProfileID: request.sourceProfileID,
                targetProfileID: request.targetProfileID,
                context: context
            )
            try Self.migrateLocalProfileReferences(
                sourceProfileID: request.sourceProfileID,
                targetProfileID: request.targetProfileID,
                context: context
            )
            let marker = NSEntityDescription.insertNewObject(
                forEntityName: Entity.profileMergeMarker,
                into: context
            )
            marker.setValue(request.operationID, forKey: "operationID")
            marker.setValue(request.sourceProfileID.rawValue, forKey: "sourceProfileID")
            marker.setValue(request.targetProfileID.rawValue, forKey: "targetProfileID")
            marker.setValue(request.mergedAt, forKey: "mergedAt")
            marker.setValue(try JSONEncoder().encode(request), forKey: "payload")
            try Self.save(context)
            try Self.deleteProvisionalData(
                clientID: clientID,
                profileID: request.sourceProfileID,
                context: context
            )
            try Self.save(context)
            return true
        }
        changeHub.yield(.profiles)
        changeHub.yield(.userState(request.targetProfileID))
        return applied
    }

    public func saveProfile(_ profile: Profile) async throws {
        try await context.perform { [context] in
            let object = try Self.fetchOne(
                entity: Entity.profile,
                key: "id",
                value: profile.id.rawValue,
                context: context
            ) ?? NSEntityDescription.insertNewObject(forEntityName: Entity.profile, into: context)
            if let existing = Self.decodeProfile(object),
               profile.effectiveMutationStamp <= existing.effectiveMutationStamp {
                return
            }
            Self.writeProfile(profile, to: object)
            try Self.save(context)
        }
        changeHub.yield(.profiles)
    }

    public func tombstoneProfile(
        id: ProfileID,
        at date: Date,
        mutationStamp: MutationStamp
    ) async throws {
        try await context.perform { [context] in
            guard let object = try Self.fetchOne(
                entity: Entity.profile,
                key: "id",
                value: id.rawValue,
                context: context
            ), let profile = Self.decodeProfile(object) else {
                throw ProfileRepositoryError.profileNotFound(id)
            }
            guard mutationStamp > profile.effectiveMutationStamp else { return }
            Self.writeProfile(profile.tombstoned(at: date, stamp: mutationStamp), to: object)
            try Self.save(context)
        }
        changeHub.yield(.profiles)
    }

    @discardableResult
    public func mergeProfiles(_ request: ProfileMergeRequest) async throws -> Bool {
        guard request.sourceProfileID != request.targetProfileID else {
            throw ProfileRepositoryError.invalidProfileMerge
        }
        let applied = try await context.perform { [context] in
            guard try Self.fetchOne(
                entity: Entity.profileMergeMarker,
                key: "operationID",
                value: request.operationID,
                context: context
            ) == nil else {
                return false
            }
            guard
                let sourceObject = try Self.fetchOne(
                    entity: Entity.profile,
                    key: "id",
                    value: request.sourceProfileID.rawValue,
                    context: context
                ),
                let sourceProfile = Self.decodeProfile(sourceObject)
            else {
                throw ProfileRepositoryError.profileNotFound(request.sourceProfileID)
            }
            guard try Self.fetchOne(
                entity: Entity.profile,
                key: "id",
                value: request.targetProfileID.rawValue,
                context: context
            ) != nil else {
                throw ProfileRepositoryError.profileNotFound(request.targetProfileID)
            }

            let encoder = JSONEncoder()
            try Self.copyStates(
                entity: Entity.favorite,
                sourceProfileID: request.sourceProfileID,
                targetProfileID: request.targetProfileID,
                as: ProfileFavoriteState.self,
                encoder: encoder,
                context: context
            )
            try Self.copyStates(
                entity: Entity.playback,
                sourceProfileID: request.sourceProfileID,
                targetProfileID: request.targetProfileID,
                as: ProfilePlaybackState.self,
                encoder: encoder,
                context: context
            )
            try Self.copyViewingFacts(
                sourceProfileID: request.sourceProfileID,
                targetProfileID: request.targetProfileID,
                sourceSessionEntity: Entity.viewingSession,
                targetSessionEntity: Entity.viewingSession,
                sourceEventEntity: Entity.playbackEvent,
                targetEventEntity: Entity.playbackEvent,
                sourceDeviceEntity: Entity.deviceRecord,
                targetDeviceEntity: Entity.deviceRecord,
                context: context
            )
            try Self.copyImportMarkers(
                sourceProfileID: request.sourceProfileID,
                targetProfileID: request.targetProfileID,
                sourceEntity: Entity.importMarker,
                targetEntity: Entity.importMarker,
                context: context
            )
            try Self.migrateLocalProfileReferences(
                sourceProfileID: request.sourceProfileID,
                targetProfileID: request.targetProfileID,
                context: context
            )

            if request.mutationStamp > sourceProfile.effectiveMutationStamp {
                Self.writeProfile(
                    sourceProfile.merged(
                        into: request.targetProfileID,
                        at: request.mergedAt,
                        stamp: request.mutationStamp
                    ),
                    to: sourceObject
                )
            }

            let marker = NSEntityDescription.insertNewObject(
                forEntityName: Entity.profileMergeMarker,
                into: context
            )
            marker.setValue(request.operationID, forKey: "operationID")
            marker.setValue(request.sourceProfileID.rawValue, forKey: "sourceProfileID")
            marker.setValue(request.targetProfileID.rawValue, forKey: "targetProfileID")
            marker.setValue(request.mergedAt, forKey: "mergedAt")
            marker.setValue(try encoder.encode(request), forKey: "payload")
            try Self.save(context)
            return true
        }
        if applied {
            changeHub.yield(.profiles)
            changeHub.yield(.userState(request.targetProfileID))
        }
        return applied
    }


    static func copyStates<Value: Decodable>(
        entity: String,
        sourceProfileID: ProfileID,
        targetProfileID: ProfileID,
        as type: Value.Type,
        encoder: JSONEncoder,
        context: NSManagedObjectContext
    ) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(
            format: "profileID == %@",
            sourceProfileID.rawValue as CVarArg
        )
        let decoder = JSONDecoder()
        for object in try context.fetch(request) {
            guard let payload = object.value(forKey: "payload") as? Data else { continue }
            let value = try decoder.decode(type, from: payload)
            if let favorite = value as? ProfileFavoriteState {
                let copy = favorite.withMutationStamp(
                    favorite.effectiveMutationStamp,
                    profileID: targetProfileID
                )
                try upsertVersioned(
                    copy,
                    entity: entity,
                    key: stateKey(profileID: targetProfileID, mediaKey: copy.mediaKey),
                    profileID: targetProfileID,
                    mediaKey: copy.mediaKey,
                    modifiedAt: copy.modifiedAt,
                    deviceID: copy.deviceID,
                    mutationStamp: copy.mutationStamp,
                    encoder: encoder,
                    context: context
                )
            } else if let playback = value as? ProfilePlaybackState {
                let copy = playback.withMutationStamp(
                    playback.effectiveMutationStamp,
                    profileID: targetProfileID
                )
                try upsertVersioned(
                    copy,
                    entity: entity,
                    key: stateKey(profileID: targetProfileID, mediaKey: copy.mediaKey),
                    profileID: targetProfileID,
                    mediaKey: copy.mediaKey,
                    modifiedAt: copy.modifiedAt,
                    deviceID: copy.deviceID,
                    mutationStamp: copy.mutationStamp,
                    encoder: encoder,
                    context: context
                )
            } else {
                throw ProfileRepositoryError.invalidRecord
            }
        }
    }

    static func provisionalProfileObject(
        clientID: ClientID,
        profileID: ProfileID,
        context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.provisionalProfile)
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "clientID == %@", clientID.description),
            NSPredicate(format: "id == %@", profileID.rawValue as CVarArg)
        ])
        return try context.fetch(request).first
    }

    static func provisionalHasMeaningfulData(
        profileID: ProfileID,
        context: NSManagedObjectContext
    ) throws -> Bool {
        for entity in [Entity.provisionalFavorite, Entity.provisionalPlayback] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            request.fetchLimit = 1
            request.predicate = NSPredicate(
                format: "profileID == %@",
                profileID.rawValue as CVarArg
            )
            if try !context.fetch(request).isEmpty { return true }
        }
        for entity in [Entity.provisionalViewingSession, Entity.provisionalPlaybackEvent] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            request.fetchLimit = 1
            request.predicate = NSPredicate(
                format: "profileID == %@",
                profileID.rawValue as CVarArg
            )
            if try !context.fetch(request).isEmpty { return true }
        }
        return false
    }

    static func copyViewingFacts(
        sourceProfileID: ProfileID,
        targetProfileID: ProfileID,
        sourceSessionEntity: String,
        targetSessionEntity: String,
        sourceEventEntity: String,
        targetEventEntity: String,
        sourceDeviceEntity: String,
        targetDeviceEntity: String,
        context: NSManagedObjectContext
    ) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var deviceRecordIDs = Set<DeviceRecordID>()

        let sessionRequest = NSFetchRequest<NSManagedObject>(entityName: sourceSessionEntity)
        sessionRequest.predicate = NSPredicate(
            format: "profileID == %@",
            sourceProfileID.rawValue as CVarArg
        )
        for object in try context.fetch(sessionRequest) {
            guard
                let payload = object.value(forKey: "payload") as? Data,
                let session = try? decoder.decode(ViewingSession.self, from: payload)
            else { continue }
            let copy = session.withMutationStamp(
                session.effectiveMutationStamp,
                profileID: targetProfileID
            )
            deviceRecordIDs.insert(copy.deviceRecordID)
            try upsertViewingSession(
                copy,
                entity: targetSessionEntity,
                encoder: encoder,
                context: context
            )
        }

        let eventRequest = NSFetchRequest<NSManagedObject>(entityName: sourceEventEntity)
        eventRequest.predicate = NSPredicate(
            format: "profileID == %@",
            sourceProfileID.rawValue as CVarArg
        )
        for object in try context.fetch(eventRequest) {
            guard
                let payload = object.value(forKey: "payload") as? Data,
                let event = try? decoder.decode(ProfilePlaybackEvent.self, from: payload)
            else { continue }
            let stamp = event.mutationStamp
                ?? MutationStamp(date: event.observedAt, clientID: event.deviceID)
            let copy = event.withMutationStamp(stamp, profileID: targetProfileID)
            deviceRecordIDs.insert(copy.deviceRecordID)
            try upsertPlaybackEvent(
                copy,
                entity: targetEventEntity,
                encoder: encoder,
                context: context
            )
        }

        if sourceDeviceEntity != targetDeviceEntity {
            let request = NSFetchRequest<NSManagedObject>(entityName: sourceDeviceEntity)
            for object in try context.fetch(request) {
                if let id = object.value(forKey: "id") as? UUID {
                    deviceRecordIDs.insert(DeviceRecordID(rawValue: id))
                }
            }
        }
        for deviceRecordID in deviceRecordIDs {
            guard
                let object = try fetchOne(
                    entity: sourceDeviceEntity,
                    key: "id",
                    value: deviceRecordID.rawValue,
                    context: context
                ),
                let payload = object.value(forKey: "payload") as? Data,
                let record = try? decoder.decode(DeviceRecord.self, from: payload)
            else { continue }
            _ = try upsertDeviceRecord(
                record,
                entity: targetDeviceEntity,
                encoder: encoder,
                context: context
            )
        }
    }

    static func copyProvisionalState(
        sourceProfileID: ProfileID,
        targetProfileID: ProfileID,
        context: NSManagedObjectContext
    ) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var mediaKeys = Set<ProfileMediaKey>()

        let favoriteRequest = NSFetchRequest<NSManagedObject>(
            entityName: Entity.provisionalFavorite
        )
        favoriteRequest.predicate = NSPredicate(
            format: "profileID == %@",
            sourceProfileID.rawValue as CVarArg
        )
        for object in try context.fetch(favoriteRequest) {
            guard
                let payload = object.value(forKey: "payload") as? Data,
                let value = try? decoder.decode(ProfileFavoriteState.self, from: payload)
            else { continue }
            let copy = value.withMutationStamp(
                value.effectiveMutationStamp,
                profileID: targetProfileID
            )
            mediaKeys.insert(copy.mediaKey)
            try upsertVersioned(
                copy,
                entity: Entity.favorite,
                key: stateKey(profileID: targetProfileID, mediaKey: copy.mediaKey),
                profileID: targetProfileID,
                mediaKey: copy.mediaKey,
                modifiedAt: copy.modifiedAt,
                deviceID: copy.deviceID,
                mutationStamp: copy.mutationStamp,
                encoder: encoder,
                context: context
            )
        }

        let playbackRequest = NSFetchRequest<NSManagedObject>(
            entityName: Entity.provisionalPlayback
        )
        playbackRequest.predicate = NSPredicate(
            format: "profileID == %@",
            sourceProfileID.rawValue as CVarArg
        )
        for object in try context.fetch(playbackRequest) {
            guard
                let payload = object.value(forKey: "payload") as? Data,
                let value = try? decoder.decode(ProfilePlaybackState.self, from: payload)
            else { continue }
            let copy = value.withMutationStamp(
                value.effectiveMutationStamp,
                profileID: targetProfileID
            )
            mediaKeys.insert(copy.mediaKey)
            try upsertVersioned(
                copy,
                entity: Entity.playback,
                key: stateKey(profileID: targetProfileID, mediaKey: copy.mediaKey),
                profileID: targetProfileID,
                mediaKey: copy.mediaKey,
                modifiedAt: copy.modifiedAt,
                deviceID: copy.deviceID,
                mutationStamp: copy.mutationStamp,
                encoder: encoder,
                context: context
            )
        }

        try copyViewingFacts(
            sourceProfileID: sourceProfileID,
            targetProfileID: targetProfileID,
            sourceSessionEntity: Entity.provisionalViewingSession,
            targetSessionEntity: Entity.viewingSession,
            sourceEventEntity: Entity.provisionalPlaybackEvent,
            targetEventEntity: Entity.playbackEvent,
            sourceDeviceEntity: Entity.provisionalDeviceRecord,
            targetDeviceEntity: Entity.deviceRecord,
            context: context
        )

        if !mediaKeys.isEmpty {
            let snapshotRequest = NSFetchRequest<NSManagedObject>(
                entityName: Entity.provisionalSnapshot
            )
            snapshotRequest.predicate = NSPredicate(
                format: "key IN %@",
                mediaKeys.map(\.rawValue)
            )
            for object in try context.fetch(snapshotRequest) {
                guard
                    let payload = object.value(forKey: "payload") as? Data,
                    let snapshot = try? decoder.decode(ProfileMediaSnapshot.self, from: payload)
                else { continue }
                try upsertSnapshot(snapshot, encoder: encoder, context: context)
            }
        }

        try copyImportMarkers(
            sourceProfileID: sourceProfileID,
            targetProfileID: targetProfileID,
            sourceEntity: Entity.provisionalImportMarker,
            targetEntity: Entity.importMarker,
            context: context
        )
    }

    static func copyImportMarkers(
        sourceProfileID: ProfileID,
        targetProfileID: ProfileID,
        sourceEntity: String,
        targetEntity: String,
        context: NSManagedObjectContext
    ) throws {
        let markerRequest = NSFetchRequest<NSManagedObject>(entityName: sourceEntity)
        markerRequest.predicate = NSPredicate(
            format: "profileID == %@",
            sourceProfileID.rawValue as CVarArg
        )
        for object in try context.fetch(markerRequest) {
            guard
                let sourceID = object.value(forKey: "sourceID") as? UUID,
                let remoteUserID = object.value(forKey: "remoteUserID") as? String,
                let markerValue = object.value(forKey: "marker") as? String
            else { continue }
            let key = "\(targetProfileID.rawValue.uuidString):\(sourceID.uuidString):\(remoteUserID):\(markerValue)"
            guard try fetchOne(
                entity: targetEntity,
                key: "key",
                value: key,
                context: context
            ) == nil else { continue }
            let copy = NSEntityDescription.insertNewObject(
                forEntityName: targetEntity,
                into: context
            )
            copy.setValue(key, forKey: "key")
            copy.setValue(targetProfileID.rawValue, forKey: "profileID")
            copy.setValue(sourceID, forKey: "sourceID")
            copy.setValue(remoteUserID, forKey: "remoteUserID")
            copy.setValue(markerValue, forKey: "marker")
            copy.setValue(object.value(forKey: "importedAt") as? Date, forKey: "importedAt")
        }
    }

    static func migrateLocalProfileReferences(
        sourceProfileID: ProfileID,
        targetProfileID: ProfileID,
        context: NSManagedObjectContext
    ) throws {
        let bindingRequest = NSFetchRequest<NSManagedObject>(entityName: Entity.binding)
        bindingRequest.predicate = NSPredicate(
            format: "profileID == %@",
            sourceProfileID.rawValue as CVarArg
        )
        for object in try context.fetch(bindingRequest) {
            guard let binding = decodeBinding(object) else { continue }
            let targetKey = bindingKey(
                profileID: targetProfileID,
                sourceID: binding.sourceID
            )
            if let target = try fetchOne(
                entity: Entity.binding,
                key: "key",
                value: targetKey,
                context: context
            ) {
                let targetBinding = decodeBinding(target)
                target.setValue(
                    targetBinding?.remoteUserID ?? binding.remoteUserID,
                    forKey: "remoteUserID"
                )
                target.setValue(
                    (targetBinding?.mirrorsRemoteState ?? false) || binding.mirrorsRemoteState,
                    forKey: "mirrorsRemoteState"
                )
                context.delete(object)
                continue
            }
            object.setValue(targetKey, forKey: "key")
            object.setValue(targetProfileID.rawValue, forKey: "profileID")
        }

        let selectionRequest = NSFetchRequest<NSManagedObject>(entityName: Entity.activeSelection)
        selectionRequest.predicate = NSPredicate(
            format: "profileID == %@",
            sourceProfileID.rawValue as CVarArg
        )
        for object in try context.fetch(selectionRequest) {
            object.setValue(targetProfileID.rawValue, forKey: "profileID")
        }

        let mirrorRequest = NSFetchRequest<NSManagedObject>(entityName: Entity.mirrorQueue)
        mirrorRequest.predicate = NSPredicate(
            format: "profileID == %@",
            sourceProfileID.rawValue as CVarArg
        )
        let decoder = JSONDecoder()
        for object in try context.fetch(mirrorRequest) {
            guard
                let payload = object.value(forKey: "payload") as? Data,
                let entry = try? decoder.decode(MirrorQueueEntry.self, from: payload)
            else { continue }
            let mutation: MirrorMutation
            switch entry.mutation {
            case let .favorite(state):
                mutation = .favorite(state.withMutationStamp(
                    state.effectiveMutationStamp,
                    profileID: targetProfileID
                ))
            case let .playback(state):
                mutation = .playback(state.withMutationStamp(
                    state.effectiveMutationStamp,
                    profileID: targetProfileID
                ))
            }
            try writeMirror(
                MirrorQueueEntry(
                    id: entry.id,
                    profileID: targetProfileID,
                    sourceID: entry.sourceID,
                    remoteUserID: entry.remoteUserID,
                    locator: entry.locator,
                    mutation: mutation,
                    attempts: entry.attempts,
                    nextAttemptAt: entry.nextAttemptAt
                ),
                to: object
            )
        }
    }

    static func deleteProvisionalData(
        clientID: ClientID,
        profileID: ProfileID,
        context: NSManagedObjectContext
    ) throws {
        var mediaKeys = Set<String>()
        for entity in [Entity.provisionalFavorite, Entity.provisionalPlayback] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            request.predicate = NSPredicate(
                format: "profileID == %@",
                profileID.rawValue as CVarArg
            )
            for object in try context.fetch(request) {
                if let key = object.value(forKey: "mediaKey") as? String {
                    mediaKeys.insert(key)
                }
                context.delete(object)
            }
        }
        let sessionRequest = NSFetchRequest<NSManagedObject>(
            entityName: Entity.provisionalViewingSession
        )
        sessionRequest.predicate = NSPredicate(
            format: "profileID == %@",
            profileID.rawValue as CVarArg
        )
        for object in try context.fetch(sessionRequest) {
            if let key = object.value(forKey: "mediaKey") as? String {
                mediaKeys.insert(key)
            }
            context.delete(object)
        }
        try deleteAll(
            entity: Entity.provisionalPlaybackEvent,
            predicate: NSPredicate(
                format: "profileID == %@",
                profileID.rawValue as CVarArg
            ),
            context: context
        )
        if !mediaKeys.isEmpty {
            try deleteAll(
                entity: Entity.provisionalSnapshot,
                predicate: NSPredicate(format: "key IN %@", Array(mediaKeys)),
                context: context
            )
        }
        try deleteAll(
            entity: Entity.provisionalImportMarker,
            predicate: NSPredicate(
                format: "profileID == %@",
                profileID.rawValue as CVarArg
            ),
            context: context
        )
        let profilePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "clientID == %@", clientID.description),
            NSPredicate(format: "id == %@", profileID.rawValue as CVarArg)
        ])
        try deleteAll(
            entity: Entity.provisionalProfile,
            predicate: profilePredicate,
            context: context
        )
        try deleteAll(
            entity: Entity.provisionalDeviceRecord,
            predicate: NSPredicate(format: "clientID == %@", clientID.description),
            context: context
        )
    }

}
