import ComposableArchitecture
import Foundation
import CineLarkCatalog

struct CacheUsage: Equatable, Sendable {
    var metadataBytes: UInt64
    var artworkBytes: UInt64

    var totalBytes: UInt64 { metadataBytes + artworkBytes }

    static let zero = Self(metadataBytes: 0, artworkBytes: 0)
}

enum CacheClientFailure: Error, Equatable, Sendable {
    case unavailable(String)

    var message: String {
        switch self {
        case let .unavailable(message): message
        }
    }
}

struct CacheClient: Sendable {
    var usage: @Sendable () async throws -> CacheUsage
    var clearAll: @Sendable () async throws -> Void
}

extension CacheClient: DependencyKey {
    static let liveValue = Self(
        usage: { throw CacheClientFailure.unavailable("Cache client is not configured") },
        clearAll: { throw CacheClientFailure.unavailable("Cache client is not configured") }
    )

    static let testValue = liveValue
}

extension DependencyValues {
    var cache: CacheClient {
        get { self[CacheClient.self] }
        set { self[CacheClient.self] = newValue }
    }
}

extension CacheClient {
    private enum ClearOutcome: Sendable {
        case success
        case cancelled
        case failure(String)
    }

    static func live(
        catalog: any CatalogRepository,
        artworkUsage: @escaping @Sendable () async throws -> UInt64,
        clearArtwork: @escaping @Sendable () async throws -> Void
    ) -> Self {
        Self(
            usage: {
                async let catalogStatistics = catalog.cacheStatistics()
                async let artworkBytes = artworkUsage()
                let values = try await (catalogStatistics, artworkBytes)
                return CacheUsage(
                    metadataBytes: UInt64(values.0.byteCount),
                    artworkBytes: values.1
                )
            },
            clearAll: {
                async let catalogFailure = Self.clearFailure("Media metadata") {
                    try await catalog.removeAllCachedData()
                }
                async let artworkFailure = Self.clearFailure("Artwork") {
                    try await clearArtwork()
                }
                let outcomes = await [catalogFailure, artworkFailure]
                if outcomes.contains(where: {
                    if case .cancelled = $0 { return true }
                    return false
                }) {
                    throw CancellationError()
                }
                let failures = outcomes.compactMap { outcome -> String? in
                    guard case let .failure(message) = outcome else { return nil }
                    return message
                }
                guard failures.isEmpty else {
                    throw CacheClientFailure.unavailable(failures.joined(separator: "; "))
                }
            }
        )
    }

    private static func clearFailure(
        _ category: String,
        operation: @escaping @Sendable () async throws -> Void
    ) async -> ClearOutcome {
        do {
            try await operation()
            return .success
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failure("\(category): \(String(describing: error))")
        }
    }
}
