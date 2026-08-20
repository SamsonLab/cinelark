import Foundation

public struct UHDNowConfiguration: Sendable, Equatable {
    public let apiBaseURL: URL
    public let webBaseURL: URL

    public init(apiBaseURL: URL, webBaseURL: URL) {
        self.apiBaseURL = apiBaseURL
        self.webBaseURL = webBaseURL
    }

    public static let production = UHDNowConfiguration(
        apiBaseURL: URL(string: "https://www.uhdnow.com/api/v1")!,
        webBaseURL: URL(string: "https://www.uhdnow.com")!
    )
}
