import Foundation
import Testing
@testable import CineLarkUHDNow

@Suite("UHDNow endpoint construction")
struct UHDNowEndpointTests {
    @Test("search terms and paging are URL encoded")
    func encodesSearchQuery() throws {
        let request = try UHDNowRequestBuilder(
            configuration: .production
        ).request(
            method: .get,
            path: "/stream/library/search",
            queryItems: [
                URLQueryItem(name: "q", value: "九部电影"),
                URLQueryItem(name: "page", value: "2"),
                URLQueryItem(name: "page_size", value: "24")
            ],
            token: "synthetic-token"
        )

        let url = try #require(request.url)
        let components = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        #expect(components.path == "/api/v1/stream/library/search")
        #expect(components.queryItems?.first == URLQueryItem(name: "q", value: "九部电影"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "synthetic-token")
    }

    @Test("path traversal-like identifiers stay inside the API path")
    func encodesPathComponent() throws {
        let path = UHDNowRequestBuilder.path(
            "stream",
            "movies",
            "synthetic/id",
            "assets"
        )
        #expect(path == "/stream/movies/synthetic%2Fid/assets")
    }
}
