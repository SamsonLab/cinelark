import Foundation
import CineLarkDomain

@MainActor
public protocol PlaybackLaunching: AnyObject {
    func open(_ descriptor: PlaybackDescriptor) async throws
}

public enum PlaybackLaunchError: Error, LocalizedError {
    case iinaNotInstalled
    case launchFailed

    public var errorDescription: String? {
        switch self {
        case .iinaNotInstalled:
            "IINA is not installed. Install IINA to play this item."
        case .launchFailed:
            "CineLark could not open this item in IINA."
        }
    }
}
