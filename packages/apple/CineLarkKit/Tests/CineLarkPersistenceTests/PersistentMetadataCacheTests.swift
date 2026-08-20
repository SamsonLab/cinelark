import Foundation
import Testing
@testable import CineLarkPersistence

@Suite("Persistent metadata cache")
struct PersistentMetadataCacheTests {
    private struct Payload: Codable, Sendable, Equatable {
        let id: Int
        let title: String
    }

    @Test("metadata survives cache recreation")
    func survivesRecreation() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let key = MetadataCacheKey(rawValue: "detail:movie:1")
        let expected = Payload(id: 1, title: "Synthetic Movie")

        let firstCache = PersistentMetadataCache(directory: directory, now: { date })
        try await firstCache.insert(
            expected,
            for: key,
            timeToLive: 3_600,
            tags: []
        )

        let restoredCache = PersistentMetadataCache(directory: directory, now: { date })
        let restored: MetadataCacheValue<Payload>? = try await restoredCache.value(
            for: key,
            as: Payload.self
        )

        #expect(restored?.value == expected)
        #expect(restored?.isFresh(at: date) == true)
    }

    @Test("expired metadata remains available only during stale retention")
    func staleRetention() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let key = MetadataCacheKey(rawValue: "hot:1:20")
        let configuration = MetadataCacheConfiguration(staleRetention: 300)

        let writer = PersistentMetadataCache(
            directory: directory,
            configuration: configuration,
            now: { storedAt }
        )
        try await writer.insert(
            Payload(id: 1, title: "Synthetic Movie"),
            for: key,
            timeToLive: 60,
            tags: []
        )

        let staleDate = storedAt.addingTimeInterval(120)
        let staleCache = PersistentMetadataCache(
            directory: directory,
            configuration: configuration,
            now: { staleDate }
        )
        let stale: MetadataCacheValue<Payload>? = try await staleCache.value(
            for: key,
            as: Payload.self
        )
        #expect(stale != nil)
        #expect(stale?.isFresh(at: staleDate) == false)

        let removalDate = storedAt.addingTimeInterval(361)
        let expiredCache = PersistentMetadataCache(
            directory: directory,
            configuration: configuration,
            now: { removalDate }
        )
        let expired: MetadataCacheValue<Payload>? = try await expiredCache.value(
            for: key,
            as: Payload.self
        )
        #expect(expired == nil)
    }

    @Test("least recently used metadata is evicted at the entry limit")
    func leastRecentlyUsedEviction() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = MutableClock(Date(timeIntervalSince1970: 1_700_000_000))
        let configuration = MetadataCacheConfiguration(
            maxByteCount: 1_024 * 1_024,
            maxEntryCount: 2
        )
        let cache = PersistentMetadataCache(
            directory: directory,
            configuration: configuration,
            now: { clock.value }
        )
        let firstKey = MetadataCacheKey(rawValue: "first")
        let secondKey = MetadataCacheKey(rawValue: "second")
        let thirdKey = MetadataCacheKey(rawValue: "third")

        try await cache.insert(Payload(id: 1, title: "First"), for: firstKey, timeToLive: 600)
        clock.advance(by: 1)
        try await cache.insert(Payload(id: 2, title: "Second"), for: secondKey, timeToLive: 600)
        clock.advance(by: 1)
        let first: MetadataCacheValue<Payload>? = try await cache.value(
            for: firstKey,
            as: Payload.self
        )
        #expect(first != nil)
        clock.advance(by: 1)
        try await cache.insert(Payload(id: 3, title: "Third"), for: thirdKey, timeToLive: 600)

        let evicted: MetadataCacheValue<Payload>? = try await cache.value(
            for: secondKey,
            as: Payload.self
        )
        let retained: MetadataCacheValue<Payload>? = try await cache.value(
            for: firstKey,
            as: Payload.self
        )
        #expect(evicted == nil)
        #expect(retained?.value.id == 1)
    }

    @Test("corrupt entries are removed without poisoning the cache")
    func corruptEntryIsRemoved() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PersistentMetadataCache(directory: directory)
        let key = MetadataCacheKey(rawValue: "corrupt")

        try await cache.insert(Payload(id: 1, title: "Synthetic"), for: key, timeToLive: 600)
        let entryURL = try #require(
            FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).first { $0.pathExtension == "entry" }
        )
        try Data("not-json".utf8).write(to: entryURL)

        let value: MetadataCacheValue<Payload>? = try await cache.value(
            for: key,
            as: Payload.self
        )
        let statistics = try await cache.performMaintenance()
        #expect(value == nil)
        #expect(statistics.entryCount == 0)
    }

    @Test("schema changes reset recreatable metadata")
    func schemaChangeResetsCache() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = MetadataCacheKey(rawValue: "schema-versioned")
        let firstCache = PersistentMetadataCache(
            directory: directory,
            configuration: MetadataCacheConfiguration(schemaVersion: 1)
        )
        try await firstCache.insert(
            Payload(id: 1, title: "Old Schema"),
            for: key,
            timeToLive: 600
        )

        let upgradedCache = PersistentMetadataCache(
            directory: directory,
            configuration: MetadataCacheConfiguration(schemaVersion: 2)
        )
        let value: MetadataCacheValue<Payload>? = try await upgradedCache.value(
            for: key,
            as: Payload.self
        )
        #expect(value == nil)
        #expect(try await upgradedCache.performMaintenance().entryCount == 0)
    }

    @Test("clearing cache never removes unrelated files from its directory")
    func clearPreservesUnrelatedFiles() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PersistentMetadataCache(directory: directory)
        try await cache.insert(
            Payload(id: 1, title: "Cached"),
            for: MetadataCacheKey(rawValue: "cached"),
            timeToLive: 600
        )
        let unrelatedURL = directory.appendingPathComponent("keep.txt")
        try Data("unrelated".utf8).write(to: unrelatedURL)

        try await cache.removeAll()

        #expect(FileManager.default.fileExists(atPath: unrelatedURL.path))
        #expect(try await cache.performMaintenance().entryCount == 0)
    }

    @Test("tag invalidation removes only related metadata")
    func tagInvalidation() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PersistentMetadataCache(directory: directory)
        let mediaTag = MetadataCacheTag(rawValue: "media:1")
        let firstKey = MetadataCacheKey(rawValue: "detail:1")
        let secondKey = MetadataCacheKey(rawValue: "detail:2")

        try await cache.insert(
            Payload(id: 1, title: "First"),
            for: firstKey,
            timeToLive: 600,
            tags: [mediaTag]
        )
        try await cache.insert(
            Payload(id: 2, title: "Second"),
            for: secondKey,
            timeToLive: 600,
            tags: []
        )
        try await cache.removeValues(tagged: mediaTag)

        let first: MetadataCacheValue<Payload>? = try await cache.value(
            for: firstKey,
            as: Payload.self
        )
        let second: MetadataCacheValue<Payload>? = try await cache.value(
            for: secondKey,
            as: Payload.self
        )
        #expect(first == nil)
        #expect(second?.value.id == 2)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cinelark-cache-tests-\(UUID().uuidString)", isDirectory: true)
    }
}

private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    var value: Date {
        lock.withLock { date }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            date = date.addingTimeInterval(interval)
        }
    }
}
