import Foundation
import CineLarkPluginAPI

public struct HTTPResponse: @unchecked Sendable {
    public let data: Data
    public let response: HTTPURLResponse

    public init(data: Data, response: HTTPURLResponse) {
        self.data = data
        self.response = response
    }
}

public struct EmbyHTTPClient: Sendable {
    public var send: @Sendable (URLRequest) async throws -> HTTPResponse

    public init(send: @escaping @Sendable (URLRequest) async throws -> HTTPResponse) {
        self.send = send
    }

    public static let live = EmbyHTTPClient { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MediaSourceFailure.invalidResponse
        }
        return HTTPResponse(data: data, response: response)
    }
}

public struct EmbyTokenVault: Sendable {
    public var load: @Sendable (SourceID) async throws -> String?
    public var save: @Sendable (String, SourceID) async throws -> Void
    public var remove: @Sendable (SourceID) async throws -> Void

    public init(
        load: @escaping @Sendable (SourceID) async throws -> String?,
        save: @escaping @Sendable (String, SourceID) async throws -> Void,
        remove: @escaping @Sendable (SourceID) async throws -> Void
    ) {
        self.load = load
        self.save = save
        self.remove = remove
    }

    public static let ephemeral = EmbyTokenVault(
        load: { _ in nil },
        save: { _, _ in },
        remove: { _ in }
    )
}
