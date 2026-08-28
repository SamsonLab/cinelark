import Foundation
import CineLarkPluginAPI

public struct CatalogChange: Sendable, Equatable {
    public let sourceID: SourceID
    public let itemIDs: Set<CatalogItemID>

    public init(sourceID: SourceID, itemIDs: Set<CatalogItemID>) {
        self.sourceID = sourceID
        self.itemIDs = itemIDs
    }
}

public struct CatalogCacheStatistics: Sendable, Equatable {
    public let itemCount: Int
    public let locatorCount: Int
    public let queryCount: Int
    public let byteCount: Int

    public init(
        itemCount: Int,
        locatorCount: Int,
        queryCount: Int,
        byteCount: Int
    ) {
        self.itemCount = itemCount
        self.locatorCount = locatorCount
        self.queryCount = queryCount
        self.byteCount = max(byteCount, 0)
    }
}

public protocol CatalogRepository: Sendable {
    func cachedPage(for query: MediaQuery) async throws -> MediaPage
    func items(for locators: Set<MediaLocatorID>) async throws -> [LocatedMediaItem]
    func cache(
        _ page: MediaPage,
        for query: MediaQuery,
        refreshedAt: Date
    ) async throws -> MediaPage
    @discardableResult
    func upsert(_ items: [LocatedMediaItem], refreshedAt: Date) async throws -> [LocatedMediaItem]
    func cacheStatistics() async throws -> CatalogCacheStatistics
    func removeAllCachedData() async throws
    func changes() async -> AsyncStream<CatalogChange>
}
