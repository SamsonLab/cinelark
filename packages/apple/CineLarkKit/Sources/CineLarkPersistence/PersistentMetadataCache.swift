import CryptoKit
import Foundation

public actor PersistentMetadataCache: MetadataCaching {
    private struct Manifest: Codable {
        let formatVersion: Int
        let schemaVersion: Int
        var entries: [String: Record]
    }

    private struct Record: Codable {
        let fileName: String
        let storedAt: Date
        let expiresAt: Date
        var lastAccessAt: Date
        let byteCount: Int
        let tags: Set<String>
    }

    private static let manifestFormatVersion = 1
    private static let manifestFileName = "manifest.json"
    private static let entryExtension = "entry"

    private let directoryURL: URL
    private let configuration: MetadataCacheConfiguration
    private let now: @Sendable () -> Date
    private var loadedManifest: Manifest?

    public init(
        directory: URL? = nil,
        configuration: MetadataCacheConfiguration = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.directoryURL = directory ?? Self.defaultDirectoryURL()
        self.configuration = configuration
        self.now = now
    }

    public func value<Value: Codable & Sendable>(
        for key: MetadataCacheKey,
        as type: Value.Type
    ) async throws -> MetadataCacheValue<Value>? {
        try loadManifestIfNeeded()

        let identifier = identifier(for: key)
        guard var record = loadedManifest?.entries[identifier] else {
            return nil
        }

        let currentDate = now()
        let removalDate = record.expiresAt.addingTimeInterval(configuration.staleRetention)
        guard currentDate < removalDate else {
            removeEntry(identifier: identifier)
            try saveManifest()
            return nil
        }

        let fileURL = directoryURL.appendingPathComponent(record.fileName)
        do {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let value = try makeDecoder().decode(Value.self, from: data)
            record.lastAccessAt = currentDate
            loadedManifest?.entries[identifier] = record
            return MetadataCacheValue(
                value: value,
                storedAt: record.storedAt,
                expiresAt: record.expiresAt
            )
        } catch {
            removeEntry(identifier: identifier)
            try saveManifest()
            return nil
        }
    }

    public func insert<Value: Codable & Sendable>(
        _ value: Value,
        for key: MetadataCacheKey,
        timeToLive: TimeInterval,
        tags: Set<MetadataCacheTag> = []
    ) async throws {
        try loadManifestIfNeeded()

        let identifier = identifier(for: key)
        let data = try makeEncoder().encode(value)
        guard data.count <= configuration.maxByteCount else {
            if loadedManifest?.entries[identifier] != nil {
                removeEntry(identifier: identifier)
                try saveManifest()
            }
            return
        }

        let fileName = "\(identifier).\(Self.entryExtension)"
        let fileURL = directoryURL.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )

        let currentDate = now()
        loadedManifest?.entries[identifier] = Record(
            fileName: fileName,
            storedAt: currentDate,
            expiresAt: currentDate.addingTimeInterval(max(timeToLive, 0)),
            lastAccessAt: currentDate,
            byteCount: data.count,
            tags: Set(tags.map(\.rawValue))
        )

        prune(at: currentDate)
        try saveManifest()
    }

    public func removeValue(for key: MetadataCacheKey) async throws {
        try loadManifestIfNeeded()
        let identifier = identifier(for: key)
        guard loadedManifest?.entries[identifier] != nil else { return }
        removeEntry(identifier: identifier)
        try saveManifest()
    }

    public func removeValues(tagged tag: MetadataCacheTag) async throws {
        try loadManifestIfNeeded()
        let identifiers: [String] = loadedManifest?.entries.compactMap { identifier, record in
            record.tags.contains(tag.rawValue) ? identifier : nil
        } ?? []
        guard !identifiers.isEmpty else { return }
        identifiers.forEach(removeEntry)
        try saveManifest()
    }

    public func removeAll() async throws {
        try resetStorage()
    }

    public func performMaintenance() async throws -> MetadataCacheStatistics {
        try loadManifestIfNeeded()
        let currentDate = now()

        removeMissingEntries()
        prune(at: currentDate)
        removeOrphanedFiles()
        try saveManifest()

        return statistics(at: currentDate)
    }

    private static func defaultDirectoryURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("CineLark", isDirectory: true)
            .appendingPathComponent("MetadataCache", isDirectory: true)
    }

    private func loadManifestIfNeeded() throws {
        guard loadedManifest == nil else { return }
        try prepareDirectory()

        let manifestURL = directoryURL.appendingPathComponent(Self.manifestFileName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            loadedManifest = emptyManifest()
            removeOrphanedFiles()
            try saveManifest()
            return
        }

        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try makeDecoder().decode(Manifest.self, from: data)
            guard manifest.formatVersion == Self.manifestFormatVersion,
                  manifest.schemaVersion == configuration.schemaVersion else {
                try resetStorage()
                return
            }
            loadedManifest = manifest
        } catch {
            try resetStorage()
        }
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
    }

    private func resetStorage() throws {
        loadedManifest = nil
        try prepareDirectory()

        let files = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        for fileURL in files where
            fileURL.lastPathComponent == Self.manifestFileName ||
            fileURL.pathExtension == Self.entryExtension {
            try FileManager.default.removeItem(at: fileURL)
        }

        loadedManifest = emptyManifest()
        try saveManifest()
    }

    private func emptyManifest() -> Manifest {
        Manifest(
            formatVersion: Self.manifestFormatVersion,
            schemaVersion: configuration.schemaVersion,
            entries: [:]
        )
    }

    private func saveManifest() throws {
        guard let loadedManifest else { return }
        let data = try makeEncoder().encode(loadedManifest)
        let manifestURL = directoryURL.appendingPathComponent(Self.manifestFileName)
        try data.write(to: manifestURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: manifestURL.path
        )
    }

    private func identifier(for key: MetadataCacheKey) -> String {
        let digest = SHA256.hash(data: Data(key.rawValue.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func removeEntry(identifier: String) {
        guard let record = loadedManifest?.entries.removeValue(forKey: identifier) else {
            return
        }
        let fileURL = directoryURL.appendingPathComponent(record.fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func removeMissingEntries() {
        let identifiers: [String] = loadedManifest?.entries.compactMap { identifier, record in
            let fileURL = directoryURL.appendingPathComponent(record.fileName)
            return FileManager.default.fileExists(atPath: fileURL.path) ? nil : identifier
        } ?? []
        identifiers.forEach(removeEntry)
    }

    private func removeOrphanedFiles() {
        let referencedFiles = Set(loadedManifest?.entries.values.map(\.fileName) ?? [])
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )) ?? []

        for fileURL in files where fileURL.pathExtension == Self.entryExtension {
            guard !referencedFiles.contains(fileURL.lastPathComponent) else { continue }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func prune(at date: Date) {
        let expiredIdentifiers: [String] = loadedManifest?.entries.compactMap { identifier, record in
            let removalDate = record.expiresAt.addingTimeInterval(configuration.staleRetention)
            return date >= removalDate ? identifier : nil
        } ?? []
        expiredIdentifiers.forEach(removeEntry)

        guard let entries = loadedManifest?.entries else { return }
        var entryCount = entries.count
        var byteCount = entries.values.reduce(0) { $0 + $1.byteCount }
        guard entryCount > configuration.maxEntryCount ||
                byteCount > configuration.maxByteCount else {
            return
        }

        let evictionCandidates = entries.sorted {
            if $0.value.lastAccessAt == $1.value.lastAccessAt {
                return $0.key < $1.key
            }
            return $0.value.lastAccessAt < $1.value.lastAccessAt
        }

        for (identifier, record) in evictionCandidates {
            guard entryCount > configuration.maxEntryCount ||
                    byteCount > configuration.maxByteCount else {
                break
            }
            removeEntry(identifier: identifier)
            entryCount -= 1
            byteCount -= record.byteCount
        }
    }

    private func statistics(at date: Date) -> MetadataCacheStatistics {
        let entries = loadedManifest?.entries.values ?? [:].values
        let freshEntryCount = entries.reduce(0) { count, record in
            count + (date < record.expiresAt ? 1 : 0)
        }
        let entryCount = entries.count
        return MetadataCacheStatistics(
            entryCount: entryCount,
            freshEntryCount: freshEntryCount,
            staleEntryCount: entryCount - freshEntryCount,
            byteCount: entries.reduce(0) { $0 + $1.byteCount }
        )
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
