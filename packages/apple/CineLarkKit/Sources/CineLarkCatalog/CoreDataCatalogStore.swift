@preconcurrency import CoreData
import Foundation
import CineLarkDomain
import CineLarkPluginAPI

public actor CoreDataCatalogStore: CatalogRepository {
    private enum Entity {
        static let item = "CatalogItem"
        static let locator = "MediaLocator"
        static let source = "SourceRecord"
        static let refresh = "RefreshMetadata"
    }

    private let context: NSManagedObjectContext
    private var continuations: [UUID: AsyncStream<CatalogChange>.Continuation] = [:]

    public init(storeURL: URL? = nil, inMemory: Bool = false) throws {
        let model = Self.makeModel()
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let type = inMemory ? NSInMemoryStoreType : NSSQLiteStoreType
        let options: [AnyHashable: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true
        ]
        try coordinator.addPersistentStore(
            ofType: type,
            configurationName: nil,
            at: inMemory ? nil : storeURL,
            options: options
        )
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.context = context
    }

    public func changes() async -> AsyncStream<CatalogChange> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    public func cacheStatistics() async throws -> CatalogCacheStatistics {
        try await context.perform { [context] in
            let items = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: Entity.item))
            let locators = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: Entity.locator))
            let sources = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: Entity.source))
            let refreshes = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: Entity.refresh))
            let byteCount = [items, locators, sources, refreshes]
                .joined()
                .reduce(into: 0) { result, object in
                    for property in object.entity.attributesByName.keys {
                        switch object.value(forKey: property) {
                        case let data as Data:
                            result += data.count
                        case let string as String:
                            result += string.utf8.count
                        case let url as URL:
                            result += url.absoluteString.utf8.count
                        default:
                            break
                        }
                    }
                }
            return CatalogCacheStatistics(
                itemCount: items.count,
                locatorCount: locators.count,
                queryCount: refreshes.count,
                byteCount: byteCount
            )
        }
    }

    public func removeAllCachedData() async throws {
        try await context.perform { [context] in
            for entity in [Entity.refresh, Entity.locator, Entity.item, Entity.source] {
                let request = NSFetchRequest<NSManagedObject>(entityName: entity)
                for object in try context.fetch(request) {
                    context.delete(object)
                }
            }
            if context.hasChanges { try context.save() }
            context.reset()
        }
    }

    public func cachedPage(for query: MediaQuery) async throws -> MediaPage {
        let sourceIDs = query.scope.sourceIDs.map(\.rawValue)
        let cursorOffset = query.cursor.flatMap { Int($0.rawValue) } ?? 0
        let limit = query.limit
        let kinds = query.kinds.map(\.rawValue)
        let queryIdentity = try Self.queryIdentity(query)

        return try await context.perform { [context] in
            let locatorRequest = NSFetchRequest<NSManagedObject>(entityName: Entity.locator)
            locatorRequest.predicate = NSPredicate(format: "sourceID IN %@", sourceIDs)
            let locators = try context.fetch(locatorRequest)

            let refreshRequest = NSFetchRequest<NSManagedObject>(entityName: Entity.refresh)
            refreshRequest.fetchLimit = 1
            refreshRequest.predicate = NSPredicate(format: "queryIdentity == %@", queryIdentity)
            if let refresh = try context.fetch(refreshRequest).first,
               let itemData = refresh.value(forKey: "itemIDs") as? Data,
               let itemIDs = try? JSONDecoder().decode([UUID].self, from: itemData) {
                let items = try Self.locatedItems(
                    itemIDs: itemIDs,
                    locators: locators,
                    context: context
                )
                let cursor = (refresh.value(forKey: "cursor") as? String).map(MediaCursor.init)
                let total = (refresh.value(forKey: "total") as? NSNumber)?.intValue
                return MediaPage(items: items, nextCursor: cursor, total: total)
            }

            guard query.parent == nil, query.filters.isEmpty, query.sort == nil else {
                return MediaPage(items: [], nextCursor: nil, total: 0)
            }
            let itemIDs = Set(locators.compactMap { $0.value(forKey: "catalogItemID") as? UUID })

            let itemRequest = NSFetchRequest<NSManagedObject>(entityName: Entity.item)
            var predicates = [NSPredicate(format: "id IN %@", Array(itemIDs))]
            if !kinds.isEmpty {
                predicates.append(NSPredicate(format: "kind IN %@", kinds))
            }
            itemRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            itemRequest.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
            let allItems = try context.fetch(itemRequest)
            let pageItems = Array(allItems.dropFirst(cursorOffset).prefix(limit))
            let decoder = JSONDecoder()

            let located = pageItems.compactMap { object -> LocatedMediaItem? in
                guard
                    let id = object.value(forKey: "id") as? UUID,
                    let data = object.value(forKey: "summary") as? Data,
                    let summary = try? decoder.decode(MediaSummary.self, from: data),
                    let locator = locators.first(where: {
                        ($0.value(forKey: "catalogItemID") as? UUID) == id
                    }),
                    let sourceUUID = locator.value(forKey: "sourceID") as? UUID,
                    let providerID = locator.value(forKey: "providerItemID") as? String
                else { return nil }

                let contentData = locator.value(forKey: "contentKeys") as? Data
                let contentKeys = contentData.flatMap {
                    try? decoder.decode(Set<ContentKey>.self, from: $0)
                } ?? []
                return LocatedMediaItem(
                    catalogID: CatalogItemID(rawValue: id),
                    locator: MediaLocatorID(
                        sourceID: SourceID(rawValue: sourceUUID),
                        providerItemID: providerID
                    ),
                    contentKeys: contentKeys,
                    summary: summary
                )
            }
            let nextOffset = cursorOffset + located.count
            return MediaPage(
                items: located,
                nextCursor: nextOffset < allItems.count
                    ? MediaCursor(rawValue: String(nextOffset))
                    : nil,
                total: allItems.count
            )
        }
    }

    public func cache(
        _ page: MediaPage,
        for query: MediaQuery,
        refreshedAt: Date
    ) async throws -> MediaPage {
        let normalized = try await upsert(page.items, refreshedAt: refreshedAt)
        let identity = try Self.queryIdentity(query)
        let sourceID = query.scope.sourceIDs.first?.rawValue
        try await context.perform { [context] in
            let request = NSFetchRequest<NSManagedObject>(entityName: Entity.refresh)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "queryIdentity == %@", identity)
            let object = try context.fetch(request).first
                ?? NSEntityDescription.insertNewObject(forEntityName: Entity.refresh, into: context)
            object.setValue(identity, forKey: "key")
            object.setValue(sourceID, forKey: "sourceID")
            object.setValue(identity, forKey: "queryIdentity")
            object.setValue(refreshedAt, forKey: "refreshedAt")
            object.setValue(page.nextCursor?.rawValue, forKey: "cursor")
            object.setValue(page.total.map(NSNumber.init(value:)), forKey: "total")
            object.setValue(
                try JSONEncoder().encode(normalized.compactMap { $0.catalogID?.rawValue }),
                forKey: "itemIDs"
            )
            if context.hasChanges { try context.save() }
        }
        return MediaPage(
            items: normalized,
            nextCursor: page.nextCursor,
            total: page.total
        )
    }

    @discardableResult
    public func upsert(
        _ items: [LocatedMediaItem],
        refreshedAt: Date
    ) async throws -> [LocatedMediaItem] {
        let normalized = try await context.perform { [context] in
            let encoder = JSONEncoder()
            var normalized: [LocatedMediaItem] = []

            for incoming in items {
                let locatorKey = Self.locatorKey(incoming.locator)
                let locatorRequest = NSFetchRequest<NSManagedObject>(entityName: Entity.locator)
                locatorRequest.fetchLimit = 1
                locatorRequest.predicate = NSPredicate(format: "key == %@", locatorKey)
                let existingLocator = try context.fetch(locatorRequest).first
                let catalogID = incoming.catalogID?.rawValue
                    ?? (existingLocator?.value(forKey: "catalogItemID") as? UUID)
                    ?? UUID()

                let itemRequest = NSFetchRequest<NSManagedObject>(entityName: Entity.item)
                itemRequest.fetchLimit = 1
                itemRequest.predicate = NSPredicate(format: "id == %@", catalogID as CVarArg)
                let item = try context.fetch(itemRequest).first
                    ?? NSEntityDescription.insertNewObject(forEntityName: Entity.item, into: context)
                item.setValue(catalogID, forKey: "id")
                item.setValue(incoming.summary.kind.rawValue, forKey: "kind")
                item.setValue(incoming.summary.title, forKey: "title")
                item.setValue(try encoder.encode(incoming.summary), forKey: "summary")
                item.setValue(refreshedAt, forKey: "updatedAt")

                let locator = existingLocator
                    ?? NSEntityDescription.insertNewObject(forEntityName: Entity.locator, into: context)
                locator.setValue(locatorKey, forKey: "key")
                locator.setValue(incoming.locator.sourceID.rawValue, forKey: "sourceID")
                locator.setValue(incoming.locator.providerItemID, forKey: "providerItemID")
                locator.setValue(catalogID, forKey: "catalogItemID")
                locator.setValue(try encoder.encode(incoming.contentKeys), forKey: "contentKeys")
                locator.setValue(item, forKey: "item")

                normalized.append(
                    LocatedMediaItem(
                        catalogID: CatalogItemID(rawValue: catalogID),
                        locator: incoming.locator,
                        contentKeys: incoming.contentKeys,
                        summary: incoming.summary
                    )
                )
            }
            if context.hasChanges { try context.save() }
            return normalized
        }

        let grouped = Dictionary(grouping: normalized, by: \.locator.sourceID)
        for (sourceID, items) in grouped {
            let change = CatalogChange(
                sourceID: sourceID,
                itemIDs: Set(items.compactMap(\.catalogID))
            )
            for continuation in continuations.values { continuation.yield(change) }
        }
        return normalized
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private static func locatorKey(_ locator: MediaLocatorID) -> String {
        "\(locator.sourceID.rawValue.uuidString):\(locator.providerItemID)"
    }

    private static func queryIdentity(_ query: MediaQuery) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(query).base64EncodedString()
    }

    private static func locatedItems(
        itemIDs: [UUID],
        locators: [NSManagedObject],
        context: NSManagedObjectContext
    ) throws -> [LocatedMediaItem] {
        guard !itemIDs.isEmpty else { return [] }
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.item)
        request.predicate = NSPredicate(format: "id IN %@", itemIDs)
        let objects = try context.fetch(request)
        let objectsByID = Dictionary(uniqueKeysWithValues: objects.compactMap { object in
            (object.value(forKey: "id") as? UUID).map { ($0, object) }
        })
        let decoder = JSONDecoder()
        return itemIDs.compactMap { id in
            guard
                let object = objectsByID[id],
                let data = object.value(forKey: "summary") as? Data,
                let summary = try? decoder.decode(MediaSummary.self, from: data),
                let locator = locators.first(where: {
                    ($0.value(forKey: "catalogItemID") as? UUID) == id
                }),
                let sourceUUID = locator.value(forKey: "sourceID") as? UUID,
                let providerID = locator.value(forKey: "providerItemID") as? String
            else { return nil }
            let contentKeys = (locator.value(forKey: "contentKeys") as? Data).flatMap {
                try? decoder.decode(Set<ContentKey>.self, from: $0)
            } ?? []
            return LocatedMediaItem(
                catalogID: CatalogItemID(rawValue: id),
                locator: MediaLocatorID(
                    sourceID: SourceID(rawValue: sourceUUID),
                    providerItemID: providerID
                ),
                contentKeys: contentKeys,
                summary: summary
            )
        }
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let item = entity(Entity.item, attributes: [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("kind", .stringAttributeType, optional: false),
            attribute("title", .stringAttributeType, optional: false),
            attribute("summary", .binaryDataAttributeType, optional: false),
            attribute("updatedAt", .dateAttributeType, optional: false)
        ], uniqueness: ["id"])
        let locator = entity(Entity.locator, attributes: [
            attribute("key", .stringAttributeType, optional: false),
            attribute("sourceID", .UUIDAttributeType, optional: false),
            attribute("providerItemID", .stringAttributeType, optional: false),
            attribute("catalogItemID", .UUIDAttributeType, optional: false),
            attribute("contentKeys", .binaryDataAttributeType, optional: false)
        ], uniqueness: ["key"])
        let source = entity(Entity.source, attributes: [
            attribute("sourceID", .UUIDAttributeType, optional: false),
            attribute("pluginID", .stringAttributeType, optional: false),
            attribute("serverID", .stringAttributeType, optional: false),
            attribute("displayName", .stringAttributeType, optional: false),
            attribute("baseURL", .URIAttributeType, optional: false)
        ], uniqueness: ["sourceID"])
        let refresh = entity(Entity.refresh, attributes: [
            attribute("key", .stringAttributeType, optional: false),
            attribute("sourceID", .UUIDAttributeType, optional: false),
            attribute("queryIdentity", .stringAttributeType, optional: false),
            attribute("refreshedAt", .dateAttributeType, optional: false),
            attribute("cursor", .stringAttributeType, optional: true),
            attribute("total", .integer64AttributeType, optional: true),
            attribute("itemIDs", .binaryDataAttributeType, optional: true)
        ], uniqueness: ["key"])

        let itemLocators = NSRelationshipDescription()
        itemLocators.name = "locators"
        itemLocators.destinationEntity = locator
        itemLocators.minCount = 0
        itemLocators.maxCount = 0
        itemLocators.deleteRule = .cascadeDeleteRule
        itemLocators.isOptional = true

        let locatorItem = NSRelationshipDescription()
        locatorItem.name = "item"
        locatorItem.destinationEntity = item
        locatorItem.minCount = 1
        locatorItem.maxCount = 1
        locatorItem.deleteRule = .nullifyDeleteRule
        locatorItem.isOptional = false
        itemLocators.inverseRelationship = locatorItem
        locatorItem.inverseRelationship = itemLocators
        item.properties.append(itemLocators)
        locator.properties.append(locatorItem)

        model.entities = [item, locator, source, refresh]
        return model
    }

    private static func entity(
        _ name: String,
        attributes: [NSAttributeDescription],
        uniqueness: [String]
    ) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = "NSManagedObject"
        entity.properties = attributes
        entity.uniquenessConstraints = [uniqueness]
        return entity
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }
}
