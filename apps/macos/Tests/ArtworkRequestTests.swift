import Foundation
import Testing
import CineLarkPluginAPI

@testable import CineLark

struct ArtworkRequestTests {
    @Test("Capability headers are applied only to the ephemeral image request")
    func requestResolution() async throws {
        let reference = ArtworkRequestReference(
            locator: MediaLocatorID(
                sourceID: SourceID(rawValue: UUID()),
                providerItemID: "movie-1"
            ),
            kind: "primary"
        )
        let fallbackURL = URL(string: "https://example.test/items/movie-1/images/primary")!
        let resolver = ArtworkResolutionClient { _, _ in
            ArtworkDescriptor(
                url: fallbackURL,
                headers: ["X-Test-Authorization": "Synthetic credential"]
            )
        }
        let modifier = ArtworkRequestModifier(reference: reference, resolver: resolver)

        let request = try #require(await modifier.modified(for: URLRequest(url: fallbackURL)))

        #expect(request.url == fallbackURL)
        #expect(request.value(forHTTPHeaderField: "X-Test-Authorization") == "Synthetic credential")
    }

    @Test("Unsafe artwork descriptors are rejected before credentials can escape")
    func unsafeDescriptors() async {
        let reference = ArtworkRequestReference(
            locator: MediaLocatorID(
                sourceID: SourceID(rawValue: UUID()),
                providerItemID: "movie-1"
            ),
            kind: "primary"
        )
        let fallbackURL = URL(string: "https://example.test/items/movie-1/images/primary")!
        let crossOrigin = ArtworkRequestModifier(
            reference: reference,
            resolver: ArtworkResolutionClient { _, _ in
                ArtworkDescriptor(
                    url: URL(string: "https://cdn.example.test/poster.jpg")!,
                    headers: ["Authorization": "Synthetic credential"]
                )
            }
        )
        let queryCredential = ArtworkRequestModifier(
            reference: reference,
            resolver: ArtworkResolutionClient { _, _ in
                ArtworkDescriptor(
                    url: URL(string: "https://example.test/poster.jpg?api_key=synthetic")!
                )
            }
        )
        let unsafeFallback = URL(
            string: "https://example.test/poster.jpg?X-Emby-Token=synthetic"
        )!

        #expect(await crossOrigin.modified(for: URLRequest(url: fallbackURL)) == nil)
        #expect(await queryCredential.modified(for: URLRequest(url: fallbackURL)) == nil)
        #expect(await crossOrigin.modified(for: URLRequest(url: unsafeFallback)) == nil)
    }

    @Test("Artwork cache identity excludes URL credentials and query values")
    func cacheKeyRedaction() {
        let reference = ArtworkRequestReference(
            locator: MediaLocatorID(
                sourceID: SourceID(rawValue: UUID()),
                providerItemID: "movie-1"
            ),
            kind: "primary"
        )
        let url = URL(string: "https://user:password@example.test/poster.jpg?api_key=secret#fragment")!

        let key = ArtworkRequestPolicy.cacheKey(reference: reference, fallbackURL: url)

        #expect(key.contains(reference.locator.sourceID.rawValue.uuidString))
        #expect(key.contains(reference.locator.providerItemID))
        #expect(!key.contains("user"))
        #expect(!key.contains("password"))
        #expect(!key.contains("api_key"))
        #expect(!key.contains("secret"))
        #expect(!key.contains("fragment"))
    }
}
