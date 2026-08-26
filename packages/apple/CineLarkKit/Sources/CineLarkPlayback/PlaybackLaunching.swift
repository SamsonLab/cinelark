import Foundation
import CineLarkDomain

public struct PlaybackSnapshot: Sendable, Equatable {
    public enum State: String, Sendable {
        case playing
        case paused
        case stopped
    }

    public let state: State
    public let positionSeconds: Double
    public let durationSeconds: Double
    public let speed: Double
    public let volume: Double
    public let muted: Bool
    public let fullscreen: Bool

    public init(
        state: State,
        positionSeconds: Double,
        durationSeconds: Double,
        speed: Double,
        volume: Double,
        muted: Bool,
        fullscreen: Bool
    ) {
        self.state = state
        self.positionSeconds = max(positionSeconds, 0)
        self.durationSeconds = max(durationSeconds, 0)
        self.speed = max(speed, 0)
        self.volume = max(volume, 0)
        self.muted = muted
        self.fullscreen = fullscreen
    }
}

public enum PlaybackEvent: Sendable, Equatable {
    case bridgeReady
    case fileLoaded(playbackID: UUID, resumedAtSeconds: Double)
    case stateChanged(playbackID: UUID, snapshot: PlaybackSnapshot)
    case positionChanged(playbackID: UUID, positionSeconds: Double, durationSeconds: Double)
    case tracksChanged(playbackID: UUID, audio: [BridgeTrack], subtitles: [BridgeTrack], video: [BridgeTrack])
    case ended(playbackID: UUID, reason: String)
    case closed(playbackID: UUID, reason: String)
    case bridgeError(code: String, message: String)
}

public struct BridgeTrack: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let title: String?
    public let formattedTitle: String?
    public let language: String?
    public let codec: String?
    public let isDefault: Bool
    public let isForced: Bool
    public let isSelected: Bool
    public let isExternal: Bool

    public init(
        id: Int,
        title: String? = nil,
        formattedTitle: String? = nil,
        language: String? = nil,
        codec: String? = nil,
        isDefault: Bool = false,
        isForced: Bool = false,
        isSelected: Bool = false,
        isExternal: Bool = false
    ) {
        self.id = id
        self.title = title
        self.formattedTitle = formattedTitle
        self.language = language
        self.codec = codec
        self.isDefault = isDefault
        self.isForced = isForced
        self.isSelected = isSelected
        self.isExternal = isExternal
    }
}

public enum PlaybackControlCommand: Sendable, Equatable {
    case pause
    case resume
    case stop
    case seekRelative(seconds: Double, exact: Bool)
    case seekAbsolute(seconds: Double)
    case setSpeed(Double)
    case setVolume(Double)
    case setMuted(Bool)
    case setFullscreen(Bool)
    case selectAudioTrack(Int)
    case selectSubtitleTrack(Int)
    case disableSubtitles
    case requestState
}

@MainActor
public protocol PlaybackLaunching: AnyObject, Sendable {
    var events: AsyncStream<PlaybackEvent> { get }
    func prepare() async throws
    func open(_ descriptor: PlaybackDescriptor) async throws
    func enqueue(_ descriptor: PlaybackDescriptor, sessionID: UUID) async throws
    func send(_ command: PlaybackControlCommand, sessionID: UUID) async throws
}

public extension PlaybackLaunching {
    var events: AsyncStream<PlaybackEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func prepare() async throws {}

    func enqueue(_ descriptor: PlaybackDescriptor, sessionID: UUID) async throws {
        throw PlaybackLaunchError.bridgeUnavailable
    }

    func send(_ command: PlaybackControlCommand, sessionID: UUID) async throws {
        throw PlaybackLaunchError.bridgeUnavailable
    }
}

public enum PlaybackLaunchError: Error, LocalizedError {
    case iinaNotInstalled
    case pluginInstallationRequired
    case pluginSetupRequiresIINAQuit
    case pluginInstallationFailed
    case pluginUnavailable
    case helperUnavailable
    case bridgeAuthenticationFailed
    case bridgeUnavailable
    case launchFailed

    public var errorDescription: String? {
        switch self {
        case .iinaNotInstalled:
            "IINA is not installed. Install IINA to play this item."
        case .pluginInstallationRequired:
            "Complete the IINA Bridge installation and enable it, then try again."
        case .pluginSetupRequiresIINAQuit:
            "CineLark needs to install or update its IINA Bridge. Fully quit IINA, then play again so CineLark can finish safely."
        case .pluginInstallationFailed:
            "CineLark could not safely install the bundled IINA Bridge. Reinstall CineLark, then try again."
        case .pluginUnavailable:
            "The CineLark IINA Bridge is not enabled. Enable it in IINA, then try again."
        case .helperUnavailable:
            "CineLark could not start its bundled playback helper."
        case .bridgeAuthenticationFailed:
            "IINA could not authenticate with CineLark. Reinstall the bridge to pair it again."
        case .bridgeUnavailable:
            "The CineLark IINA Bridge is unavailable. Start IINA and try again."
        case .launchFailed:
            "CineLark could not open this item in IINA."
        }
    }
}
