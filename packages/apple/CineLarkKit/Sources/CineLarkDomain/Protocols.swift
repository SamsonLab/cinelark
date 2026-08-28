import Foundation

public struct MediaSort: Codable, Sendable, Hashable {
    public enum Field: String, Codable, CaseIterable, Sendable {
        case releaseDate = "release_date"
        case updatedAt = "updated_at"
        case assetUpdatedAt = "asset_updated_at"
        case title
        case rating
        case popularity = "hot"
    }

    public enum Order: String, Codable, CaseIterable, Sendable {
        case ascending = "asc"
        case descending = "desc"
    }

    public let field: Field
    public let order: Order

    public init(field: Field, order: Order) {
        self.field = field
        self.order = order
    }

    public static let newest = MediaSort(field: .releaseDate, order: .descending)
}
