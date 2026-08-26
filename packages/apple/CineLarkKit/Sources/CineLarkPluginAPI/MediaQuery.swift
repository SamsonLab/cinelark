import Foundation
import CineLarkDomain

public struct SourceScope: Codable, Hashable, Sendable {
    public let sourceIDs: Set<SourceID>

    public init(sourceIDs: Set<SourceID>) {
        precondition(!sourceIDs.isEmpty, "A source scope cannot be empty")
        self.sourceIDs = sourceIDs
    }

    public init(sourceID: SourceID) {
        self.sourceIDs = [sourceID]
    }
}

public struct MediaCursor: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public enum MediaFilter: Codable, Hashable, Sendable {
    case favorite(Bool)
    case played(Bool)
    case resumable(Bool)
    case genre(String)
    case releaseYear(ClosedRange<Int>)
    case provider(name: String, value: String)
}

public struct MediaQuery: Codable, Hashable, Sendable {
    public let scope: SourceScope
    public let parent: MediaLocatorID?
    public let kinds: Set<MediaKind>
    public let filters: [MediaFilter]
    public let sort: MediaSort?
    public let cursor: MediaCursor?
    public let limit: Int

    public init(
        scope: SourceScope,
        parent: MediaLocatorID? = nil,
        kinds: Set<MediaKind> = [],
        filters: [MediaFilter] = [],
        sort: MediaSort? = nil,
        cursor: MediaCursor? = nil,
        limit: Int = 50
    ) {
        self.scope = scope
        self.parent = parent
        self.kinds = kinds
        self.filters = filters
        self.sort = sort
        self.cursor = cursor
        self.limit = max(1, limit)
    }
}

public struct LocatedMediaItem: Codable, Hashable, Sendable {
    public let catalogID: CatalogItemID?
    public let locator: MediaLocatorID
    public let contentKeys: Set<ContentKey>
    public let summary: MediaSummary

    public init(
        catalogID: CatalogItemID? = nil,
        locator: MediaLocatorID,
        contentKeys: Set<ContentKey> = [],
        summary: MediaSummary
    ) {
        self.catalogID = catalogID
        self.locator = locator
        self.contentKeys = contentKeys
        self.summary = summary
    }
}

public struct MediaPage: Codable, Hashable, Sendable {
    public let items: [LocatedMediaItem]
    public let nextCursor: MediaCursor?
    public let total: Int?

    public init(items: [LocatedMediaItem], nextCursor: MediaCursor?, total: Int?) {
        self.items = items
        self.nextCursor = nextCursor
        self.total = total
    }
}
