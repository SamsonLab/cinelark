import Foundation
import Testing
import CineLarkDomain
import CineLarkPluginAPI
@testable import CineLarkCatalog

@Test func cacheStatisticsAndPurgeCoverOnlyRecreatableCatalogData() async throws {
    let store = try CoreDataCatalogStore(inMemory: true)
    let source = SourceID(rawValue: UUID())
    let query = MediaQuery(scope: SourceScope(sourceID: source), limit: 20)
    _ = try await store.cache(
        MediaPage(
            items: [
                LocatedMediaItem(
                    locator: MediaLocatorID(sourceID: source, providerItemID: "movie-1"),
                    summary: MediaSummary(id: "movie-1", kind: .movie, title: "Arrival")
                )
            ],
            nextCursor: nil,
            total: 1
        ),
        for: query,
        refreshedAt: .now
    )

    let populated = try await store.cacheStatistics()
    #expect(populated.itemCount == 1)
    #expect(populated.locatorCount == 1)
    #expect(populated.queryCount == 1)
    #expect(populated.byteCount > 0)

    try await store.removeAllCachedData()

    let empty = try await store.cacheStatistics()
    #expect(empty == CatalogCacheStatistics(
        itemCount: 0,
        locatorCount: 0,
        queryCount: 0,
        byteCount: 0
    ))
    #expect(try await store.cachedPage(for: query).items.isEmpty)
}

@Test func catalogKeepsSourcesIsolatedAndSupportsMultipleLocators() async throws {
    let store = try CoreDataCatalogStore(inMemory: true)
    let sourceA = SourceID(rawValue: UUID())
    let sourceB = SourceID(rawValue: UUID())
    let sharedCatalogID = CatalogItemID(rawValue: UUID())
    let summary = MediaSummary(id: "provider-a", kind: .movie, title: "Arrival")
    let first = LocatedMediaItem(
        catalogID: sharedCatalogID,
        locator: MediaLocatorID(sourceID: sourceA, providerItemID: "provider-a"),
        contentKeys: [.imdb("tt2543164")],
        summary: summary
    )
    let second = LocatedMediaItem(
        catalogID: sharedCatalogID,
        locator: MediaLocatorID(sourceID: sourceB, providerItemID: "provider-b"),
        contentKeys: [.imdb("tt2543164")],
        summary: MediaSummary(id: "provider-b", kind: .movie, title: "Arrival")
    )
    try await store.upsert([first, second], refreshedAt: Date(timeIntervalSince1970: 1))

    let pageA = try await store.cachedPage(
        for: MediaQuery(scope: SourceScope(sourceID: sourceA))
    )
    let pageB = try await store.cachedPage(
        for: MediaQuery(scope: SourceScope(sourceID: sourceB))
    )

    #expect(pageA.items.map(\.locator.sourceID) == [sourceA])
    #expect(pageB.items.map(\.locator.sourceID) == [sourceB])
    #expect(pageA.items.first?.catalogID == pageB.items.first?.catalogID)
}

@Test func matchingContentKeysDoNotMergeWithoutExplicitCatalogIdentity() async throws {
    let store = try CoreDataCatalogStore(inMemory: true)
    let source = SourceID(rawValue: UUID())
    let contentKey: ContentKey = .imdb("tt2543164")
    let values = ["first", "second"].map {
        LocatedMediaItem(
            locator: MediaLocatorID(sourceID: source, providerItemID: $0),
            contentKeys: [contentKey],
            summary: MediaSummary(id: $0, kind: .movie, title: "Arrival")
        )
    }
    let normalized = try await store.upsert(values, refreshedAt: .now)

    #expect(normalized[0].catalogID != normalized[1].catalogID)
}

@Test func cachedPagesPreserveExactQueryMembershipAndOrder() async throws {
    let store = try CoreDataCatalogStore(inMemory: true)
    let source = SourceID(rawValue: UUID())
    let collection = MediaLocatorID(sourceID: source, providerItemID: "collection")
    let query = MediaQuery(
        scope: SourceScope(sourceID: source),
        parent: collection,
        sort: MediaSort(field: .releaseDate, order: .descending),
        limit: 20
    )
    let items = ["second", "first"].map { id in
        LocatedMediaItem(
            locator: MediaLocatorID(sourceID: source, providerItemID: id),
            summary: MediaSummary(id: id, kind: .movie, title: id.capitalized)
        )
    }
    let cached = try await store.cache(
        MediaPage(
            items: items,
            nextCursor: MediaCursor(rawValue: "next"),
            total: 42
        ),
        for: query,
        refreshedAt: .now
    )

    let restored = try await store.cachedPage(for: query)

    #expect(restored.items.map(\.locator.providerItemID) == ["second", "first"])
    #expect(restored.items.map(\.catalogID) == cached.items.map(\.catalogID))
    #expect(restored.nextCursor == MediaCursor(rawValue: "next"))
    #expect(restored.total == 42)
    let otherSort = MediaQuery(
        scope: SourceScope(sourceID: source),
        parent: collection,
        sort: MediaSort(field: .title, order: .ascending),
        limit: 20
    )
    #expect(try await store.cachedPage(for: otherSort).items.isEmpty)
}
