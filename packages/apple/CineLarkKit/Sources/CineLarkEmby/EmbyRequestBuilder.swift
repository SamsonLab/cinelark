import Foundation

public struct EmbyDeviceIdentity: Codable, Hashable, Sendable {
    public let name: String
    public let id: String
    public let appVersion: String

    public init(name: String = "Mac", id: String, appVersion: String) {
        self.name = name
        self.id = id
        self.appVersion = appVersion
    }
}

struct EmbyRequestBuilder: Sendable {
    let baseURL: URL
    let device: EmbyDeviceIdentity

    func request(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        token: String? = nil,
        body: Data? = nil
    ) throws -> URLRequest {
        let cleanPath = path.split(separator: "/").map(String.init)
        let endpoint = cleanPath.reduce(baseURL) { $0.appendingPathComponent($1) }
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        var authorization = "MediaBrowser Client=\"CineLark\", Device=\"\(device.name)\", DeviceId=\"\(device.id)\", Version=\"\(device.appVersion)\""
        if let token { authorization += ", Token=\"\(token)\"" }
        request.setValue(authorization, forHTTPHeaderField: "X-Emby-Authorization")
        return request
    }
}
