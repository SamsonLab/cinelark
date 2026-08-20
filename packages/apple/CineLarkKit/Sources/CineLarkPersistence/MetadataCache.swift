import Foundation

public struct MetadataCacheKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct MetadataCacheTag: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct MetadataCacheValue<Value: Sendable>: Sendable {
    public let value: Value
    public let storedAt: Date
    public let expiresAt: Date

    public init(value: Value, storedAt: Date, expiresAt: Date) {
        self.value = value
        self.storedAt = storedAt
        self.expiresAt = expiresAt
    }

    public func isFresh(at date: Date = Date()) -> Bool {
        date < expiresAt
    }
}

public struct MetadataCacheConfiguration: Sendable, Equatable {
    public let schemaVersion: Int
    public let maxByteCount: Int
    public let maxEntryCount: Int
    public let staleRetention: TimeInterval

    public init(
        schemaVersion: Int = 1,
        maxByteCount: Int = 128 * 1_024 * 1_024,
        maxEntryCount: Int = 2_000,
        staleRetention: TimeInterval = 30 * 24 * 60 * 60
    ) {
        self.schemaVersion = max(schemaVersion, 1)
        self.maxByteCount = max(maxByteCount, 1)
        self.maxEntryCount = max(maxEntryCount, 1)
        self.staleRetention = max(staleRetention, 0)
    }

    public static let `default` = MetadataCacheConfiguration()
}

public struct MetadataCacheStatistics: Sendable, Equatable {
    public let entryCount: Int
    public let freshEntryCount: Int
    public let staleEntryCount: Int
    public let byteCount: Int

    public init(
        entryCount: Int,
        freshEntryCount: Int,
        staleEntryCount: Int,
        byteCount: Int
    ) {
        self.entryCount = entryCount
        self.freshEntryCount = freshEntryCount
        self.staleEntryCount = staleEntryCount
        self.byteCount = byteCount
    }
}

public protocol MetadataCaching: Sendable {
    func value<Value: Codable & Sendable>(
        for key: MetadataCacheKey,
        as type: Value.Type
    ) async throws -> MetadataCacheValue<Value>?

    func insert<Value: Codable & Sendable>(
        _ value: Value,
        for key: MetadataCacheKey,
        timeToLive: TimeInterval,
        tags: Set<MetadataCacheTag>
    ) async throws

    func removeValue(for key: MetadataCacheKey) async throws
    func removeValues(tagged tag: MetadataCacheTag) async throws
    func removeAll() async throws
    func performMaintenance() async throws -> MetadataCacheStatistics
}
