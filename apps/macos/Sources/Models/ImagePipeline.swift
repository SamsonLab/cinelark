import Foundation
import SwiftUI
import Kingfisher
import CineLarkPluginAPI

struct ArtworkResolutionClient: Sendable {
    var resolve: @Sendable (MediaLocatorID, String) async throws -> ArtworkDescriptor?

    init(
        resolve: @escaping @Sendable (
            MediaLocatorID,
            String
        ) async throws -> ArtworkDescriptor?
    ) {
        self.resolve = resolve
    }

    static let passthrough = Self { _, _ in nil }

    static func live(platform: MediaSourcePlatform) -> Self {
        Self { locator, kind in
            try await platform.artwork(for: locator, kind: kind)
        }
    }
}

private struct ArtworkResolutionClientKey: EnvironmentKey {
    static let defaultValue = ArtworkResolutionClient.passthrough
}

extension EnvironmentValues {
    var artworkResolutionClient: ArtworkResolutionClient {
        get { self[ArtworkResolutionClientKey.self] }
        set { self[ArtworkResolutionClientKey.self] = newValue }
    }
}

struct ArtworkRequestReference: Hashable, Sendable {
    let locator: MediaLocatorID
    let kind: String
}

enum ArtworkRequestPolicy {
    private static let credentialQueryNames = Set([
        "api-key",
        "api_key",
        "access_token",
        "token",
        "x-emby-token"
    ])

    static func cacheKey(
        reference: ArtworkRequestReference,
        fallbackURL: URL
    ) -> String {
        let sanitizedURL = sanitized(fallbackURL)?.absoluteString ?? "invalid-url"
        return [
            "cinelark-artwork",
            reference.locator.sourceID.rawValue.uuidString,
            reference.locator.providerItemID,
            reference.kind.lowercased(),
            sanitizedURL
        ].joined(separator: ":")
    }

    static func applying(
        _ descriptor: ArtworkDescriptor,
        to request: URLRequest
    ) -> URLRequest? {
        guard let fallbackURL = request.url, isSafe(descriptor.url) else { return nil }
        if !descriptor.headers.isEmpty,
           !sameOrigin(fallbackURL, descriptor.url) {
            return nil
        }
        var resolved = request
        resolved.url = descriptor.url
        for (name, value) in descriptor.headers {
            resolved.setValue(value, forHTTPHeaderField: name)
        }
        return resolved
    }

    static func isSafe(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.user == nil,
              components.password == nil
        else { return false }
        return !(components.queryItems ?? []).contains {
            credentialQueryNames.contains($0.name.lowercased())
        }
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        origin(lhs) == origin(rhs)
    }

    private static func origin(_ url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased()
        else { return nil }
        let port = components.port ?? (scheme == "https" ? 443 : scheme == "http" ? 80 : -1)
        return "\(scheme)://\(host):\(port)"
    }

    private static func sanitized(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

struct ArtworkRequestModifier: AsyncImageDownloadRequestModifier {
    let reference: ArtworkRequestReference?
    let resolver: ArtworkResolutionClient
    let onDownloadTaskStarted: (@Sendable (DownloadTask?) -> Void)? = nil

    func modified(for request: URLRequest) async -> URLRequest? {
        guard let reference else { return request }
        guard let fallbackURL = request.url,
              ArtworkRequestPolicy.isSafe(fallbackURL)
        else { return nil }
        do {
            guard let descriptor = try await resolver.resolve(
                reference.locator,
                reference.kind
            ) else { return request }
            return ArtworkRequestPolicy.applying(descriptor, to: request)
        } catch {
            return nil
        }
    }
}

struct ArtworkRedirectHandler: ImageDownloadRedirectHandler {
    let rejectsRedirects: Bool

    func handleHTTPRedirection(
        for task: SessionDataTask,
        response: HTTPURLResponse,
        newRequest: URLRequest
    ) async -> URLRequest? {
        rejectsRedirects ? nil : newRequest
    }
}

@MainActor
enum CineLarkImagePipeline {
    static let cache: ImageCache = {
        let cache = ImageCache(name: "cinelark-artwork")
        cache.memoryStorage.config.totalCostLimit = 128 * 1_024 * 1_024
        cache.memoryStorage.config.expiration = .seconds(10 * 60)
        cache.diskStorage.config.sizeLimit = 512 * 1_024 * 1_024
        cache.diskStorage.config.expiration = .days(30)
        return cache
    }()
}
