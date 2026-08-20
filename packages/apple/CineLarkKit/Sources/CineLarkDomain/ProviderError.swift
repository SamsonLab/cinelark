import Foundation

public enum ProviderError: Error, Sendable, Equatable {
    case unauthenticated
    case invalidCredentials
    case sessionExpired
    case forbidden
    case notFound
    case rateLimited
    case invalidRequest
    case invalidResponse
    case unavailable
    case unsupported
}

extension ProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthenticated:
            "Please sign in to continue."
        case .invalidCredentials:
            "The username, password, or TOTP code was not accepted."
        case .sessionExpired:
            "Your session has expired. Please sign in again."
        case .forbidden:
            "This account cannot access the requested content."
        case .notFound:
            "The requested content is no longer available."
        case .rateLimited:
            "Too many requests. Please try again shortly."
        case .invalidRequest:
            "CineLark could not create a valid provider request."
        case .invalidResponse:
            "The provider returned data CineLark could not understand."
        case .unavailable:
            "The provider is currently unavailable."
        case .unsupported:
            "This provider capability is not supported yet."
        }
    }
}
