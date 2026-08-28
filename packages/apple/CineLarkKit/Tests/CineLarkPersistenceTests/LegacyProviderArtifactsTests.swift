import Foundation
import Testing

@testable import CineLarkPersistence

@Suite("Legacy provider artifacts")
struct LegacyProviderArtifactsTests {
    @Test("cleanup removes only the retired metadata directory and is idempotent")
    func removesOnlyMetadataDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cinelark-legacy-cleanup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let appDirectory = root.appendingPathComponent("CineLark", isDirectory: true)
        let metadataDirectory = appDirectory
            .appendingPathComponent("MetadataCache", isDirectory: true)
        let sibling = appDirectory.appendingPathComponent("keep.txt")
        try FileManager.default.createDirectory(
            at: metadataDirectory,
            withIntermediateDirectories: true
        )
        try Data("legacy".utf8).write(
            to: metadataDirectory.appendingPathComponent("manifest.json")
        )
        try Data("current".utf8).write(to: sibling)
        let artifacts = LegacyProviderArtifacts(metadataCacheURL: metadataDirectory)

        try artifacts.removeMetadataCache()
        try artifacts.removeMetadataCache()

        #expect(!FileManager.default.fileExists(atPath: metadataDirectory.path))
        #expect(FileManager.default.fileExists(atPath: sibling.path))
    }

    @Test("cleanup rejects a directory outside the retired cache shape")
    func rejectsBroadDirectory() {
        let invalid = LegacyProviderArtifacts(
            metadataCacheURL: FileManager.default.temporaryDirectory
        )

        #expect(throws: LegacyProviderArtifactsError.invalidMetadataCacheURL) {
            try invalid.removeMetadataCache()
        }
    }
}
