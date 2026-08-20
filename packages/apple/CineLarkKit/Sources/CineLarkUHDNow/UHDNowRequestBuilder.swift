import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
}

public struct UHDNowRequestBuilder: Sendable {
    private let configuration: UHDNowConfiguration

    public init(configuration: UHDNowConfiguration) {
        self.configuration = configuration
    }

    public func request(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        token: String? = nil,
        body: Data? = nil
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: configuration.apiBaseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }

        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let requestPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = "/" + [basePath, requestPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    public static func path(_ components: String...) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return "/" + components.map { component in
            component.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        }.joined(separator: "/")
    }
}
