@preconcurrency import CoreData
@preconcurrency import CloudKit
import Foundation
import CineLarkPluginAPI

public actor CoreDataProfileRepository: ProfileRepository {
    public struct Configuration: Sendable {
        public let cloudStoreURL: URL?
        public let localStoreURL: URL?
        public let cloudKitContainerIdentifier: String?
        public let inMemory: Bool
        public let cloudAvailabilityOverride: CloudProfileAvailability?

        public init(
            cloudStoreURL: URL? = nil,
            localStoreURL: URL? = nil,
            cloudKitContainerIdentifier: String? = nil,
            inMemory: Bool = false,
            cloudAvailabilityOverride: CloudProfileAvailability? = nil
        ) {
            self.cloudStoreURL = cloudStoreURL
            self.localStoreURL = localStoreURL
            self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
            self.inMemory = inMemory
            self.cloudAvailabilityOverride = cloudAvailabilityOverride
        }
    }

    private enum StoreConfiguration {
        static let cloud = "Cloud"
        static let local = "Local"
    }

    private enum Entity {
        static let profile = "Profile"
        static let favorite = "FavoriteState"
        static let playback = "PlaybackState"
        static let snapshot = "MediaSnapshot"
        static let importMarker = "ImportMarker"
        static let profileMergeMarker = "ProfileMergeMarker"
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
    }

    private let container: NSPersistentCloudKitContainer
    private let context: NSManagedObjectContext
    private let changeHub: ProfileChangeHub
    private let cloudKitContainerIdentifier: String?
    private let inMemory: Bool
    private let cloudAvailabilityOverride: CloudProfileAvailability?

    public init(configuration: Configuration) throws {
        let model = Self.makeModel()
        let container = NSPersistentCloudKitContainer(
            name: "CineLarkProfile",
            managedObjectModel: model
        )

        let cloudURL = configuration.cloudStoreURL ?? URL(
            fileURLWithPath: "/dev/null/CineLarkProfileCloud-\(UUID().uuidString)"
        )
        let cloud = NSPersistentStoreDescription(url: cloudURL)
        cloud.configuration = StoreConfiguration.cloud
        cloud.type = configuration.inMemory ? NSInMemoryStoreType : NSSQLiteStoreType
        cloud.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        cloud.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        cloud.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        cloud.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        if !configuration.inMemory, let identifier = configuration.cloudKitContainerIdentifier {
            cloud.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: identifier
            )
        }

        let localURL = configuration.localStoreURL ?? URL(
            fileURLWithPath: "/dev/null/CineLarkProfileLocal-\(UUID().uuidString)"
        )
        let local = NSPersistentStoreDescription(url: localURL)
        local.configuration = StoreConfiguration.local
        local.type = configuration.inMemory ? NSInMemoryStoreType : NSSQLiteStoreType
        local.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        local.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        container.persistentStoreDescriptions = [cloud, local]

        let loadResult = PersistentStoreLoadResult()
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in
            loadResult.record(error)
            semaphore.signal()
        }
        semaphore.wait()
        semaphore.wait()
        if let error = loadResult.error {
            throw error
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        self.container = container
        self.context = context
        self.cloudKitContainerIdentifier = configuration.cloudKitContainerIdentifier
        self.inMemory = configuration.inMemory
        self.cloudAvailabilityOverride = configuration.cloudAvailabilityOverride
        self.changeHub = ProfileChangeHub(
            container: container,
            coordinator: container.persistentStoreCoordinator
        )
    }

    public func changes() async -> AsyncStream<ProfileRepositoryChange> {
        changeHub.stream()
    }

    public func profiles() async throws -> [Profile] {
        try await context.perform { [context] in
            let request = NSFetchRequest<NSManagedObject>(entityName: Entity.profile)
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            return try context.fetch(request)
                .compactMap(Self.decodeProfile)
                .filter { $0.deletedAt == nil && $0.mergedIntoProfileID == nil }
        }
    }

    public func profileManifests() async throws -> [ProfileManifest] {
        let profiles = try await profiles()
        var manifests: [ProfileManifest] = []
        for profile in profiles {
            manifests.append(try await manifest(
                profile: profile,
                favoriteEntity: Entity.favorite,
                playbackEntity: Entity.playback,
                snapshotEntity: Entity.snapshot
            ))
        }
        return manifests
    }

    public func cloudProfileAvailability() async -> CloudProfileAvailability {
        if let cloudAvailabilityOverride { return cloudAvailabilityOverride }
        if inMemory { return .available }
        guard let cloudKitContainerIdentifier else { return .unavailable }

        let accountStatus = await withCheckedContinuation { continuation in
            CKContainer(identifier: cloudKitContainerIdentifier).accountStatus { status, _ in
                continuation.resume(returning: status)
            }
        }
        guard accountStatus == .available else { return .unavailable }

        do {
            let hasCloudProfile = try await hasVisibleCloudProfile()
            let completedInitialImport = try await hasCompletedInitialImport()
            if hasCloudProfile || completedInitialImport {
                return .available
            }
            return .pendingInitialImport
        } catch {
            return .pendingInitialImport
        }
    }

    public func provisionalProfileManifest(clientID: ClientID) async throws -> ProfileManifest? {
        guard let profile = try await provisionalProfile(clientID: clientID) else { return nil }
        return try await manifest(
            profile: profile,
            favoriteEntity: Entity.provisionalFavorite,
            playbackEntity: Entity.provisionalPlayback,
            snapshotEntity: Entity.provisionalSnapshot
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
            Self.writeProfile(profile, to: cloudProfile)
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

    public func nextMutationStamp(
        clientID: ClientID,
        at wallTime: Date
    ) async throws -> MutationStamp {
        try await context.perform { [context] in
            let key = clientID.description
            let object = try Self.fetchOne(
                entity: Entity.mutationClock,
                key: "clientID",
                value: key,
                context: context
            ) ?? NSEntityDescription.insertNewObject(
                forEntityName: Entity.mutationClock,
                into: context
            )
            let previous: MutationStamp?
            if let physical = object.value(forKey: "physicalMillisecondsUTC") as? NSNumber,
               let logical = object.value(forKey: "logicalCounter") as? NSNumber {
                previous = MutationStamp(
                    physicalMillisecondsUTC: physical.int64Value,
                    logicalCounter: UInt32(clamping: logical.uint64Value),
                    clientID: key
                )
            } else {
                previous = nil
            }
            var clock = MutationClockState(clientID: clientID, lastStamp: previous)
            let stamp = clock.tick(at: wallTime)
            object.setValue(key, forKey: "clientID")
            object.setValue(stamp.physicalMillisecondsUTC, forKey: "physicalMillisecondsUTC")
            object.setValue(Int64(stamp.logicalCounter), forKey: "logicalCounter")
            try Self.save(context)
            return stamp
        }
    }

    public func activeSelection(deviceID: String) async throws -> ActiveProfileSelection {
        try await context.perform { [context] in
            guard let object = try Self.fetchOne(
                entity: Entity.activeSelection,
                key: "deviceID",
                value: deviceID,
                context: context
            ) else {
                return ActiveProfileSelection(profileID: nil, sourceID: nil)
            }
            return ActiveProfileSelection(
                profileID: (object.value(forKey: "profileID") as? UUID).map {
                    ProfileID(rawValue: $0)
                },
                sourceID: (object.value(forKey: "sourceID") as? UUID).map {
                    SourceID(rawValue: $0)
                }
            )
        }
    }

    public func setActiveSelection(
        _ selection: ActiveProfileSelection,
        deviceID: String
    ) async throws {
        try await context.perform { [context] in
            let object = try Self.fetchOne(
                entity: Entity.activeSelection,
                key: "deviceID",
                value: deviceID,
                context: context
            ) ?? NSEntityDescription.insertNewObject(
                forEntityName: Entity.activeSelection,
                into: context
            )
            object.setValue(deviceID, forKey: "deviceID")
            object.setValue(selection.profileID?.rawValue, forKey: "profileID")
            object.setValue(selection.sourceID?.rawValue, forKey: "sourceID")
            try Self.save(context)
        }
        changeHub.yield(.activeSelection(selection))
    }

    public func sourceConfigurations() async throws -> [PersistedMediaSource] {
        try await context.perform { [context] in
            let request = NSFetchRequest<NSManagedObject>(entityName: Entity.source)
            request.sortDescriptors = [NSSortDescriptor(key: "displayName", ascending: true)]
            let decoder = JSONDecoder()
            return try context.fetch(request).compactMap { object in
                guard
                    let pluginID = object.value(forKey: "pluginID") as? String,
                    let data = object.value(forKey: "configuration") as? Data,
                    let configuration = try? decoder.decode(SourceConfiguration.self, from: data)
                else { return nil }
                return PersistedMediaSource(
                    pluginID: PluginID(rawValue: pluginID),
                    configuration: configuration
                )
            }
        }
    }

    public func saveSource(
        pluginID: PluginID,
        configuration: SourceConfiguration
    ) async throws {
        try await context.perform { [context] in
            let object = try Self.fetchOne(
                entity: Entity.source,
                key: "sourceID",
                value: configuration.sourceID.rawValue,
                context: context
            ) ?? NSEntityDescription.insertNewObject(forEntityName: Entity.source, into: context)
            object.setValue(configuration.sourceID.rawValue, forKey: "sourceID")
            object.setValue(pluginID.rawValue, forKey: "pluginID")
            object.setValue(configuration.displayName, forKey: "displayName")
            object.setValue(try JSONEncoder().encode(configuration), forKey: "configuration")
            object.setValue(Date(), forKey: "updatedAt")
            try Self.save(context)
        }
        changeHub.yield(.sources)
    }

    public func deleteSource(id: SourceID) async throws {
        try await context.perform { [context] in
            let predicate = NSPredicate(format: "sourceID == %@", id.rawValue as CVarArg)
            for entity in [Entity.source, Entity.binding, Entity.mirrorQueue] {
                try Self.deleteAll(entity: entity, predicate: predicate, context: context)
            }
            try Self.save(context)
        }
        changeHub.yield(.sources)
    }

    public func bindings(profileID: ProfileID) async throws -> [ProfileSourceBinding] {
        try await context.perform { [context] in
            let request = NSFetchRequest<NSManagedObject>(entityName: Entity.binding)
            request.predicate = NSPredicate(
                format: "profileID == %@",
                profileID.rawValue as CVarArg
            )
            return try context.fetch(request).compactMap(Self.decodeBinding)
        }
    }

    public func saveBinding(_ binding: ProfileSourceBinding) async throws {
        try await context.perform { [context] in
            if binding.mirrorsRemoteState, let remoteUserID = binding.remoteUserID {
                let request = NSFetchRequest<NSManagedObject>(entityName: Entity.binding)
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "sourceID == %@", binding.sourceID.rawValue as CVarArg),
                    NSPredicate(format: "remoteUserID == %@", remoteUserID),
                    NSPredicate(format: "mirrorsRemoteState == YES"),
                    NSPredicate(format: "profileID != %@", binding.profileID.rawValue as CVarArg)
                ])
                if let owner = try context.fetch(request).first,
                   let profileUUID = owner.value(forKey: "profileID") as? UUID {
                    throw ProfileRepositoryError.mirrorOwnerConflict(
                        existing: ProfileID(rawValue: profileUUID)
                    )
                }
            }

            let key = Self.bindingKey(profileID: binding.profileID, sourceID: binding.sourceID)
            let object = try Self.fetchOne(
                entity: Entity.binding,
                key: "key",
                value: key,
                context: context
            ) ?? NSEntityDescription.insertNewObject(forEntityName: Entity.binding, into: context)
            object.setValue(key, forKey: "key")
            object.setValue(binding.profileID.rawValue, forKey: "profileID")
            object.setValue(binding.sourceID.rawValue, forKey: "sourceID")
            object.setValue(binding.remoteUserID, forKey: "remoteUserID")
            object.setValue(binding.mirrorsRemoteState, forKey: "mirrorsRemoteState")
            try Self.save(context)
        }
        changeHub.yield(.sources)
    }

    public func favorite(
        profileID: ProfileID,
        mediaKey: ProfileMediaKey
    ) async throws -> ProfileFavoriteState? {
        let entity = try await isProvisional(profileID: profileID)
            ? Entity.provisionalFavorite
            : Entity.favorite
        return try await state(
            entity: entity,
            key: Self.stateKey(profileID: profileID, mediaKey: mediaKey),
            as: ProfileFavoriteState.self
        )
    }

    public func favorites(profileID: ProfileID) async throws -> [ProfileFavoriteState] {
        let entity = try await isProvisional(profileID: profileID)
            ? Entity.provisionalFavorite
            : Entity.favorite
        return try await states(entity: entity, profileID: profileID, as: ProfileFavoriteState.self)
    }

    public func mediaSnapshots(
        keys: Set<ProfileMediaKey>
    ) async throws -> [ProfileMediaSnapshot] {
        guard !keys.isEmpty else { return [] }
        let cloud = try await snapshots(keys: keys, entity: Entity.snapshot)
        let provisional = try await snapshots(keys: keys, entity: Entity.provisionalSnapshot)
        var newest = Dictionary(uniqueKeysWithValues: cloud.map { ($0.key, $0) })
        for snapshot in provisional {
            if let existing = newest[snapshot.key],
               existing.effectiveMutationStamp >= snapshot.effectiveMutationStamp {
                continue
            }
            newest[snapshot.key] = snapshot
        }
        return Array(newest.values)
    }

    public func saveFavorite(
        _ state: ProfileFavoriteState,
        snapshot: ProfileMediaSnapshot?
    ) async throws {
        let provisional = try await isProvisional(profileID: state.profileID)
        try await saveVersionedState(
            state,
            entity: provisional ? Entity.provisionalFavorite : Entity.favorite,
            snapshotEntity: provisional ? Entity.provisionalSnapshot : Entity.snapshot,
            key: Self.stateKey(profileID: state.profileID, mediaKey: state.mediaKey),
            profileID: state.profileID,
            mediaKey: state.mediaKey,
            modifiedAt: state.modifiedAt,
            deviceID: state.deviceID,
            snapshot: snapshot
        )
        changeHub.yield(.userState(state.profileID))
    }

    public func playback(
        profileID: ProfileID,
        mediaKey: ProfileMediaKey
    ) async throws -> ProfilePlaybackState? {
        let entity = try await isProvisional(profileID: profileID)
            ? Entity.provisionalPlayback
            : Entity.playback
        return try await state(
            entity: entity,
            key: Self.stateKey(profileID: profileID, mediaKey: mediaKey),
            as: ProfilePlaybackState.self
        )
    }

    public func playbackStates(profileID: ProfileID) async throws -> [ProfilePlaybackState] {
        let entity = try await isProvisional(profileID: profileID)
            ? Entity.provisionalPlayback
            : Entity.playback
        return try await states(entity: entity, profileID: profileID, as: ProfilePlaybackState.self)
    }

    public func savePlayback(
        _ state: ProfilePlaybackState,
        snapshot: ProfileMediaSnapshot?
    ) async throws {
        let provisional = try await isProvisional(profileID: state.profileID)
        try await saveVersionedState(
            state,
            entity: provisional ? Entity.provisionalPlayback : Entity.playback,
            snapshotEntity: provisional ? Entity.provisionalSnapshot : Entity.snapshot,
            key: Self.stateKey(profileID: state.profileID, mediaKey: state.mediaKey),
            profileID: state.profileID,
            mediaKey: state.mediaKey,
            modifiedAt: state.modifiedAt,
            deviceID: state.deviceID,
            snapshot: snapshot
        )
        changeHub.yield(.userState(state.profileID))
    }

    @discardableResult
    public func importRemoteState(_ batch: RemoteStateImportBatch) async throws -> Bool {
        let provisional = try await isProvisional(profileID: batch.profileID)
        let snapshotEntity = provisional ? Entity.provisionalSnapshot : Entity.snapshot
        let favoriteEntity = provisional ? Entity.provisionalFavorite : Entity.favorite
        let playbackEntity = provisional ? Entity.provisionalPlayback : Entity.playback
        let markerEntity = provisional ? Entity.provisionalImportMarker : Entity.importMarker
        let imported = try await context.perform { [context] in
            let markerKey = Self.importMarkerKey(batch)
            guard try Self.fetchOne(
                entity: markerEntity,
                key: "key",
                value: markerKey,
                context: context
            ) == nil else {
                return false
            }

            let encoder = JSONEncoder()
            for snapshot in batch.snapshots {
                try Self.upsertSnapshot(
                    snapshot,
                    entity: snapshotEntity,
                    encoder: encoder,
                    context: context
                )
            }
            for favorite in batch.favorites {
                try Self.upsertVersioned(
                    favorite,
                    entity: favoriteEntity,
                    key: Self.stateKey(profileID: favorite.profileID, mediaKey: favorite.mediaKey),
                    profileID: favorite.profileID,
                    mediaKey: favorite.mediaKey,
                    modifiedAt: favorite.modifiedAt,
                    deviceID: favorite.deviceID,
                    mutationStamp: favorite.mutationStamp,
                    encoder: encoder,
                    context: context
                )
            }
            for playback in batch.playback {
                try Self.upsertVersioned(
                    playback,
                    entity: playbackEntity,
                    key: Self.stateKey(profileID: playback.profileID, mediaKey: playback.mediaKey),
                    profileID: playback.profileID,
                    mediaKey: playback.mediaKey,
                    modifiedAt: playback.modifiedAt,
                    deviceID: playback.deviceID,
                    mutationStamp: playback.mutationStamp,
                    encoder: encoder,
                    context: context
                )
            }

            let marker = NSEntityDescription.insertNewObject(
                forEntityName: markerEntity,
                into: context
            )
            marker.setValue(markerKey, forKey: "key")
            marker.setValue(batch.profileID.rawValue, forKey: "profileID")
            marker.setValue(batch.sourceID.rawValue, forKey: "sourceID")
            marker.setValue(batch.remoteUserID, forKey: "remoteUserID")
            marker.setValue(batch.marker, forKey: "marker")
            marker.setValue(Date(), forKey: "importedAt")
            try Self.save(context)
            return true
        }
        if imported {
            changeHub.yield(.userState(batch.profileID))
        }
        return imported
    }

    public func enqueueMirror(_ entry: MirrorQueueEntry) async throws {
        try await context.perform { [context] in
            let object = try Self.fetchOne(
                entity: Entity.mirrorQueue,
                key: "id",
                value: entry.id,
                context: context
            ) ?? NSEntityDescription.insertNewObject(forEntityName: Entity.mirrorQueue, into: context)
            try Self.writeMirror(entry, to: object)
            try Self.save(context)
        }
        changeHub.yield(.mirrorQueue)
    }

    public func dueMirrorEntries(at date: Date, limit: Int) async throws -> [MirrorQueueEntry] {
        try await context.perform { [context] in
            let request = NSFetchRequest<NSManagedObject>(entityName: Entity.mirrorQueue)
            request.predicate = NSPredicate(format: "nextAttemptAt <= %@", date as NSDate)
            request.fetchLimit = max(limit, 1)
            request.sortDescriptors = [NSSortDescriptor(key: "nextAttemptAt", ascending: true)]
            let decoder = JSONDecoder()
            return try context.fetch(request).compactMap { object in
                guard let data = object.value(forKey: "payload") as? Data else { return nil }
                return try? decoder.decode(MirrorQueueEntry.self, from: data)
            }
        }
    }

    public func completeMirrorEntry(id: UUID) async throws {
        try await context.perform { [context] in
            if let object = try Self.fetchOne(
                entity: Entity.mirrorQueue,
                key: "id",
                value: id,
                context: context
            ) {
                context.delete(object)
                try Self.save(context)
            }
        }
        changeHub.yield(.mirrorQueue)
    }

    public func rescheduleMirrorEntry(
        id: UUID,
        attempts: Int,
        nextAttemptAt: Date
    ) async throws {
        try await context.perform { [context] in
            guard
                let object = try Self.fetchOne(
                    entity: Entity.mirrorQueue,
                    key: "id",
                    value: id,
                    context: context
                ),
                let data = object.value(forKey: "payload") as? Data,
                let current = try? JSONDecoder().decode(MirrorQueueEntry.self, from: data)
            else { return }
            let updated = MirrorQueueEntry(
                id: current.id,
                profileID: current.profileID,
                sourceID: current.sourceID,
                remoteUserID: current.remoteUserID,
                locator: current.locator,
                mutation: current.mutation,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt
            )
            try Self.writeMirror(updated, to: object)
            try Self.save(context)
        }
        changeHub.yield(.mirrorQueue)
    }

    private func provisionalProfile(clientID: ClientID) async throws -> Profile? {
        try await context.perform { [context] in
            guard let object = try Self.fetchOne(
                entity: Entity.provisionalProfile,
                key: "clientID",
                value: clientID.description,
                context: context
            ) else { return nil }
            return Self.decodeProfile(object)
        }
    }

    private func isProvisional(profileID: ProfileID) async throws -> Bool {
        try await context.perform { [context] in
            try Self.fetchOne(
                entity: Entity.provisionalProfile,
                key: "id",
                value: profileID.rawValue,
                context: context
            ) != nil
        }
    }

    private func manifest(
        profile: Profile,
        favoriteEntity: String,
        playbackEntity: String,
        snapshotEntity: String
    ) async throws -> ProfileManifest {
        async let favoriteValues = states(
            entity: favoriteEntity,
            profileID: profile.id,
            as: ProfileFavoriteState.self
        )
        async let playbackValues = states(
            entity: playbackEntity,
            profileID: profile.id,
            as: ProfilePlaybackState.self
        )
        let (favorites, playback) = try await (favoriteValues, playbackValues)
        let keys = Set(favorites.map(\.mediaKey) + playback.map(\.mediaKey))
        let snapshotValues = try await snapshots(keys: keys, entity: snapshotEntity)
        let latestState = (favorites.map { ($0.modifiedAt, $0.deviceID) }
            + playback.map { ($0.modifiedAt, $0.deviceID) })
            .max { $0.0 < $1.0 }
        return ProfileManifest(
            profile: profile,
            lastActivityAt: latestState?.0 ?? profile.modifiedAt,
            lastDeviceName: latestState?.1 ?? profile.deviceID,
            titleCount: snapshotValues.count,
            viewingSessionCount: playback.count,
            favoriteCount: favorites.count(where: \.isFavorite),
            totalWatchSeconds: Int64(playback.reduce(0) {
                $0 + max($1.state.positionSeconds, 0)
            })
        )
    }

    private func snapshots(
        keys: Set<ProfileMediaKey>,
        entity: String
    ) async throws -> [ProfileMediaSnapshot] {
        guard !keys.isEmpty else { return [] }
        let rawKeys = keys.map(\.rawValue)
        return try await context.perform { [context] in
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            request.predicate = NSPredicate(format: "key IN %@", rawKeys)
            let decoder = JSONDecoder()
            return try context.fetch(request).compactMap { object in
                guard let payload = object.value(forKey: "payload") as? Data else { return nil }
                return try? decoder.decode(ProfileMediaSnapshot.self, from: payload)
            }
        }
    }

    private func hasVisibleCloudProfile() async throws -> Bool {
        try await context.perform { [context] in
            let request = NSFetchRequest<NSManagedObject>(entityName: Entity.profile)
            request.fetchLimit = 1
            return try !context.fetch(request).isEmpty
        }
    }

    private func hasCompletedInitialImport() async throws -> Bool {
        try await context.perform { [context] in
            let request = NSPersistentCloudKitContainerEventRequest.fetchEvents(
                after: .distantPast
            )
            request.resultType = .events
            guard
                let result = try context.execute(request)
                    as? NSPersistentCloudKitContainerEventResult,
                let events = result.result as? [NSPersistentCloudKitContainer.Event]
            else { return false }
            return events.contains {
                $0.type == .import && $0.endDate != nil && $0.succeeded
            }
        }
    }

    private func state<Value: Decodable & Sendable>(
        entity: String,
        key: String,
        as type: Value.Type
    ) async throws -> Value? {
        try await context.perform { [context] in
            guard
                let object = try Self.fetchOne(
                    entity: entity,
                    key: "key",
                    value: key,
                    context: context
                ),
                let data = object.value(forKey: "payload") as? Data
            else { return nil }
            return try JSONDecoder().decode(type, from: data)
        }
    }

    private func states<Value: Decodable & Sendable>(
        entity: String,
        profileID: ProfileID,
        as type: Value.Type
    ) async throws -> [Value] {
        try await context.perform { [context] in
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            request.predicate = NSPredicate(
                format: "profileID == %@",
                profileID.rawValue as CVarArg
            )
            let decoder = JSONDecoder()
            return try context.fetch(request).compactMap { object in
                guard let data = object.value(forKey: "payload") as? Data else { return nil }
                return try? decoder.decode(type, from: data)
            }
        }
    }

    private func saveVersionedState<Value: Encodable & Sendable>(
        _ value: Value,
        entity: String,
        snapshotEntity: String,
        key: String,
        profileID: ProfileID,
        mediaKey: ProfileMediaKey,
        modifiedAt: Date,
        deviceID: String,
        snapshot: ProfileMediaSnapshot?
    ) async throws {
        try await context.perform { [context] in
            let encoder = JSONEncoder()
            try Self.upsertVersioned(
                value,
                entity: entity,
                key: key,
                profileID: profileID,
                mediaKey: mediaKey,
                modifiedAt: modifiedAt,
                deviceID: deviceID,
                mutationStamp: Self.mutationStamp(from: value),
                encoder: encoder,
                context: context
            )
            if let snapshot {
                try Self.upsertSnapshot(
                    snapshot,
                    entity: snapshotEntity,
                    encoder: encoder,
                    context: context
                )
            }
            try Self.save(context)
        }
    }

    private static func upsertVersioned<Value: Encodable>(
        _ value: Value,
        entity: String,
        key: String,
        profileID: ProfileID,
        mediaKey: ProfileMediaKey,
        modifiedAt: Date,
        deviceID: String,
        mutationStamp incomingMutationStamp: MutationStamp?,
        encoder: JSONEncoder,
        context: NSManagedObjectContext
    ) throws {
        let object = try fetchOne(entity: entity, key: "key", value: key, context: context)
            ?? NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
        let incomingStamp = incomingMutationStamp
            ?? MutationStamp(date: modifiedAt, clientID: deviceID)
        if let existingStamp = mutationStamp(from: object), incomingStamp <= existingStamp {
            return
        }
        object.setValue(key, forKey: "key")
        object.setValue(profileID.rawValue, forKey: "profileID")
        object.setValue(mediaKey.rawValue, forKey: "mediaKey")
        object.setValue(modifiedAt, forKey: "modifiedAt")
        object.setValue(deviceID, forKey: "deviceID")
        setMutationStamp(incomingStamp, on: object)
        object.setValue(try encoder.encode(value), forKey: "payload")
    }

    private static func upsertSnapshot(
        _ snapshot: ProfileMediaSnapshot,
        entity: String = Entity.snapshot,
        encoder: JSONEncoder,
        context: NSManagedObjectContext
    ) throws {
        let object = try fetchOne(
            entity: entity,
            key: "key",
            value: snapshot.key.rawValue,
            context: context
        ) ?? NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
        if let existingStamp = mutationStamp(from: object),
           snapshot.effectiveMutationStamp <= existingStamp {
            return
        }
        object.setValue(snapshot.key.rawValue, forKey: "key")
        object.setValue(snapshot.modifiedAt, forKey: "modifiedAt")
        object.setValue(snapshot.deviceID, forKey: "deviceID")
        setMutationStamp(snapshot.effectiveMutationStamp, on: object)
        object.setValue(try encoder.encode(snapshot), forKey: "payload")
    }

    private static func writeMirror(
        _ entry: MirrorQueueEntry,
        to object: NSManagedObject
    ) throws {
        object.setValue(entry.id, forKey: "id")
        object.setValue(entry.profileID.rawValue, forKey: "profileID")
        object.setValue(entry.sourceID.rawValue, forKey: "sourceID")
        object.setValue(entry.remoteUserID, forKey: "remoteUserID")
        object.setValue(entry.nextAttemptAt, forKey: "nextAttemptAt")
        object.setValue(try JSONEncoder().encode(entry), forKey: "payload")
    }

    private static func decodeProfile(_ object: NSManagedObject) -> Profile? {
        guard
            let id = object.value(forKey: "id") as? UUID,
            let name = object.value(forKey: "name") as? String,
            let createdAt = object.value(forKey: "createdAt") as? Date,
            let modifiedAt = object.value(forKey: "modifiedAt") as? Date,
            let deviceID = object.value(forKey: "deviceID") as? String
        else { return nil }
        return Profile(
            id: ProfileID(rawValue: id),
            name: name,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            deviceID: deviceID,
            mutationStamp: mutationStamp(from: object),
            deletedAt: object.value(forKey: "deletedAt") as? Date,
            mergedIntoProfileID: (object.value(forKey: "mergedIntoProfileID") as? UUID).map {
                ProfileID(rawValue: $0)
            }
        )
    }

    private static func writeProfile(_ profile: Profile, to object: NSManagedObject) {
        object.setValue(profile.id.rawValue, forKey: "id")
        object.setValue(profile.name, forKey: "name")
        object.setValue(profile.createdAt, forKey: "createdAt")
        object.setValue(profile.modifiedAt, forKey: "modifiedAt")
        object.setValue(profile.deviceID, forKey: "deviceID")
        object.setValue(profile.deletedAt, forKey: "deletedAt")
        object.setValue(profile.mergedIntoProfileID?.rawValue, forKey: "mergedIntoProfileID")
        setMutationStamp(profile.effectiveMutationStamp, on: object)
    }

    private static func decodeBinding(_ object: NSManagedObject) -> ProfileSourceBinding? {
        guard
            let profileID = object.value(forKey: "profileID") as? UUID,
            let sourceID = object.value(forKey: "sourceID") as? UUID
        else { return nil }
        return ProfileSourceBinding(
            profileID: ProfileID(rawValue: profileID),
            sourceID: SourceID(rawValue: sourceID),
            remoteUserID: object.value(forKey: "remoteUserID") as? String,
            mirrorsRemoteState: object.value(forKey: "mirrorsRemoteState") as? Bool ?? false
        )
    }

    private static func mutationStamp<Value>(from value: Value) -> MutationStamp? {
        switch value {
        case let value as ProfileFavoriteState:
            value.mutationStamp
        case let value as ProfilePlaybackState:
            value.mutationStamp
        default:
            nil
        }
    }

    private static func mutationStamp(from object: NSManagedObject) -> MutationStamp? {
        if let physical = object.value(forKey: "mutationPhysicalMillisecondsUTC") as? NSNumber,
           let logical = object.value(forKey: "mutationLogicalCounter") as? NSNumber,
           let clientID = object.value(forKey: "mutationClientID") as? String {
            return MutationStamp(
                physicalMillisecondsUTC: physical.int64Value,
                logicalCounter: UInt32(clamping: logical.uint64Value),
                clientID: clientID
            )
        }
        guard
            let modifiedAt = object.value(forKey: "modifiedAt") as? Date,
            let deviceID = object.value(forKey: "deviceID") as? String
        else { return nil }
        return MutationStamp(date: modifiedAt, clientID: deviceID)
    }

    private static func setMutationStamp(_ stamp: MutationStamp, on object: NSManagedObject) {
        object.setValue(stamp.physicalMillisecondsUTC, forKey: "mutationPhysicalMillisecondsUTC")
        object.setValue(Int64(stamp.logicalCounter), forKey: "mutationLogicalCounter")
        object.setValue(stamp.clientID, forKey: "mutationClientID")
    }

    private static func copyStates<Value: Decodable>(
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

    private static func provisionalProfileObject(
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

    private static func provisionalHasMeaningfulData(
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
        return false
    }

    private static func copyProvisionalState(
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

        let markerRequest = NSFetchRequest<NSManagedObject>(
            entityName: Entity.provisionalImportMarker
        )
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
                entity: Entity.importMarker,
                key: "key",
                value: key,
                context: context
            ) == nil else { continue }
            let copy = NSEntityDescription.insertNewObject(
                forEntityName: Entity.importMarker,
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

    private static func migrateLocalProfileReferences(
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
            if try fetchOne(
                entity: Entity.binding,
                key: "key",
                value: targetKey,
                context: context
            ) != nil {
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
    }

    private static func deleteProvisionalData(
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
    }

    private static func stateKey(profileID: ProfileID, mediaKey: ProfileMediaKey) -> String {
        "\(profileID.rawValue.uuidString):\(mediaKey.rawValue)"
    }

    private static func bindingKey(profileID: ProfileID, sourceID: SourceID) -> String {
        "\(profileID.rawValue.uuidString):\(sourceID.rawValue.uuidString)"
    }

    private static func importMarkerKey(_ batch: RemoteStateImportBatch) -> String {
        "\(batch.profileID.rawValue.uuidString):\(batch.sourceID.rawValue.uuidString):\(batch.remoteUserID):\(batch.marker)"
    }

    private static func fetchOne(
        entity: String,
        key: String,
        value: Any,
        context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "\(key) == %@", argumentArray: [value])
        return try context.fetch(request).first
    }

    private static func deleteAll(
        entity: String,
        predicate: NSPredicate,
        context: NSManagedObjectContext
    ) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = predicate
        for object in try context.fetch(request) {
            context.delete(object)
        }
    }

    private static func save(_ context: NSManagedObjectContext) throws {
        if context.hasChanges { try context.save() }
    }

    private static func makeModel() -> NSManagedObjectModel {
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

        model.entities = [
            profile, favorite, playback, snapshot, importMarker, profileMergeMarker,
            source, binding, active, mirror, mutationClock, provisionalProfile,
            provisionalFavorite, provisionalPlayback, provisionalSnapshot,
            provisionalImportMarker
        ]
        model.setEntities(
            [profile, favorite, playback, snapshot, importMarker, profileMergeMarker],
            forConfigurationName: StoreConfiguration.cloud
        )
        model.setEntities(
            [
                source, binding, active, mirror, mutationClock, provisionalProfile,
                provisionalFavorite, provisionalPlayback, provisionalSnapshot,
                provisionalImportMarker
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

private final class PersistentStoreLoadResult: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var error: Error?

    func record(_ error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        self.error = self.error ?? error
    }
}

private final class ProfileChangeHub: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<ProfileRepositoryChange>.Continuation] = [:]
    private var observers: [NSObjectProtocol] = []

    init(
        container: NSPersistentCloudKitContainer,
        coordinator: NSPersistentStoreCoordinator
    ) {
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: coordinator,
            queue: nil
        ) { [weak self] _ in
            self?.yield(.external)
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: nil
        ) { [weak self] notification in
            guard
                let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event,
                event.type == .import,
                event.endDate != nil,
                event.succeeded
            else { return }
            self?.yield(.bootstrap)
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.yield(.bootstrap)
        })
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func stream() -> AsyncStream<ProfileRepositoryChange> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.remove(id)
            }
        }
    }

    func yield(_ change: ProfileRepositoryChange) {
        lock.lock()
        let current = Array(continuations.values)
        lock.unlock()
        for continuation in current {
            continuation.yield(change)
        }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        continuations[id] = nil
        lock.unlock()
    }
}
