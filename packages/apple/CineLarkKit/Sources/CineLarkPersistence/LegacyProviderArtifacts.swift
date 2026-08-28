import Foundation

public enum LegacyProviderArtifactsError: Error, Equatable, Sendable {
    case invalidMetadataCacheURL
}

public struct LegacyProviderArtifacts: Sendable {
    private let metadataCacheURL: URL

    public init(metadataCacheURL: URL? = nil) {
        self.metadataCacheURL = metadataCacheURL ?? Self.defaultMetadataCacheURL()
    }

    public func removeMetadataCache() throws {
        let target = metadataCacheURL.standardizedFileURL
        guard target.lastPathComponent == "MetadataCache",
              target.deletingLastPathComponent().lastPathComponent == "CineLark"
        else {
            throw LegacyProviderArtifactsError.invalidMetadataCacheURL
        }
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }

    private static func defaultMetadataCacheURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("CineLark", isDirectory: true)
            .appendingPathComponent("MetadataCache", isDirectory: true)
    }
}
