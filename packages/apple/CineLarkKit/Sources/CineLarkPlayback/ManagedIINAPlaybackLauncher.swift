import AppKit
import Foundation
import CineLarkDomain

@MainActor
public final class ManagedIINAPlaybackLauncher: PlaybackLaunching {
    public let events: AsyncStream<PlaybackEvent>

    private static let minimumPluginVersion = "0.1.3"

    private let bundle: Bundle
    private let workspace: NSWorkspace
    private let pairingStore: BridgePairingStore
    private let client: BridgeProcessClient
    private let eventContinuation: AsyncStream<PlaybackEvent>.Continuation
    private var eventTask: Task<Void, Never>?
    private var secret: Data?
    private var sequence: UInt64 = 1
    private var isBridgeReady = false
    private var lifecycle = IINAApplicationTerminationTracker()
    private var terminationObserver: NSObjectProtocol?

    public init(
        bundle: Bundle = .main,
        workspace: NSWorkspace = .shared
    ) {
        self.bundle = bundle
        self.workspace = workspace
        self.pairingStore = BridgePairingStore()
        let executableURL = bundle.bundleURL
            .appendingPathComponent("Contents/Helpers/CineLarkBridge", isDirectory: false)
        self.client = BridgeProcessClient(executableURL: executableURL)
        let pair = AsyncStream<PlaybackEvent>.makeStream()
        self.events = pair.stream
        self.eventContinuation = pair.continuation
        self.terminationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let bundleIdentifier = (
                notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            )?.bundleIdentifier
            Task { @MainActor [weak self] in
                self?.applicationDidTerminate(bundleIdentifier: bundleIdentifier)
            }
        }
    }

    public func open(_ descriptor: PlaybackDescriptor) async throws {
        guard let iinaURL = workspace.urlForApplication(
            withBundleIdentifier: "com.colliderli.iina"
        ) else {
            throw PlaybackLaunchError.iinaNotInstalled
        }

        let secret = try pairingStore.loadOrCreateSecret()
        self.secret = secret
        guard !pluginRequiresInstallation else {
            try await openPluginInstaller(with: iinaURL)
            throw PlaybackLaunchError.pluginInstallationRequired
        }

        if await client.isReady() == false {
            isBridgeReady = false
        }
        try await ensureBridgeStarted(secret: secret)
        try await launchIINA(at: iinaURL)
        try await waitForPlugin()
        let envelope = BridgeEnvelope(
            type: "player.play",
            sessionID: descriptor.id,
            sequence: nextSequence(),
            payload: [
                "playbackID": .string(descriptor.id.uuidString.lowercased()),
                "url": .string(descriptor.url.absoluteString),
                "title": .string(descriptor.title),
                "startPositionSeconds": .number(descriptor.startPositionSeconds),
                "presentation": .object(["fullscreen": .bool(descriptor.startsInFullscreen)])
            ],
            secret: secret
        )
        try await client.send(envelope)
        lifecycle.begin(playbackID: descriptor.id)
    }

    public func send(
        _ command: PlaybackControlCommand,
        playbackID: UUID
    ) async throws {
        guard let secret else {
            throw PlaybackLaunchError.bridgeUnavailable
        }
        let (type, payload) = command.bridgeRepresentation
        let envelope = BridgeEnvelope(
            type: type,
            sessionID: playbackID,
            sequence: nextSequence(),
            payload: payload,
            secret: secret
        )
        try await client.send(envelope)
    }

    private func ensureBridgeStarted(secret: Data) async throws {
        if eventTask == nil {
            let stream = await client.eventStream()
            eventTask = Task { @MainActor [weak self] in
                for await envelope in stream {
                    self?.receive(envelope)
                }
            }
        }
        try await client.start(secret: secret)
    }

    private func receive(_ envelope: BridgeEnvelope) {
        guard let secret, envelope.isAuthenticated(with: secret) else {
            eventContinuation.yield(
                .bridgeError(
                    code: "authentication_failed",
                    message: "The bridge rejected an unauthenticated event."
                )
            )
            return
        }

        let playbackID = envelope.sessionID.flatMap(UUID.init(uuidString:))
        switch envelope.type {
        case "bridge.ready":
            isBridgeReady = true
            eventContinuation.yield(.bridgeReady)
        case "bridge.error":
            eventContinuation.yield(
                .bridgeError(
                    code: envelope.payload["code"]?.stringValue ?? "bridge_error",
                    message: envelope.payload["message"]?.stringValue ?? "The bridge reported an error."
                )
            )
        case "player.fileLoaded":
            guard let playbackID else { return }
            eventContinuation.yield(
                .fileLoaded(
                    playbackID: playbackID,
                    resumedAtSeconds: envelope.payload["resumedAtSeconds"]?.doubleValue ?? 0
                )
            )
        case "player.stateChanged":
            guard let playbackID,
                  let stateValue = envelope.payload["state"]?.stringValue,
                  let state = PlaybackSnapshot.State(rawValue: stateValue) else { return }
            if state == .stopped {
                lifecycle.finish(playbackID: playbackID)
            }
            eventContinuation.yield(
                .stateChanged(
                    playbackID: playbackID,
                    snapshot: PlaybackSnapshot(
                        state: state,
                        positionSeconds: envelope.payload["positionSeconds"]?.doubleValue ?? 0,
                        durationSeconds: envelope.payload["durationSeconds"]?.doubleValue ?? 0,
                        speed: envelope.payload["speed"]?.doubleValue ?? 1,
                        volume: envelope.payload["volume"]?.doubleValue ?? 0,
                        muted: envelope.payload["muted"]?.boolValue ?? false,
                        fullscreen: envelope.payload["fullscreen"]?.boolValue ?? false
                    )
                )
            )
        case "player.positionChanged":
            guard let playbackID else { return }
            eventContinuation.yield(
                .positionChanged(
                    playbackID: playbackID,
                    positionSeconds: envelope.payload["positionSeconds"]?.doubleValue ?? 0,
                    durationSeconds: envelope.payload["durationSeconds"]?.doubleValue ?? 0
                )
            )
        case "player.tracksChanged":
            guard let playbackID else { return }
            eventContinuation.yield(
                .tracksChanged(
                    playbackID: playbackID,
                    audio: tracks(envelope.payload["audio"]),
                    subtitles: tracks(envelope.payload["subtitles"]),
                    video: tracks(envelope.payload["video"])
                )
            )
        case "player.ended":
            guard let playbackID else { return }
            lifecycle.finish(playbackID: playbackID)
            eventContinuation.yield(
                .ended(
                    playbackID: playbackID,
                    reason: envelope.payload["reason"]?.stringValue ?? "unknown"
                )
            )
        case "player.closed":
            guard let playbackID else { return }
            lifecycle.finish(playbackID: playbackID)
            eventContinuation.yield(
                .closed(
                    playbackID: playbackID,
                    reason: envelope.payload["reason"]?.stringValue ?? "unknown"
                )
            )
        default:
            break
        }
    }

    private func applicationDidTerminate(bundleIdentifier: String?) {
        isBridgeReady = false
        guard let playbackID = lifecycle.applicationDidTerminate(
            bundleIdentifier: bundleIdentifier
        ) else { return }
        eventContinuation.yield(
            .closed(playbackID: playbackID, reason: "application_terminated")
        )
    }

    private func tracks(_ value: JSONValue?) -> [BridgeTrack] {
        value?.arrayValue?.compactMap { value in
            guard let object = value.objectValue,
                  let id = object["id"]?.doubleValue else { return nil }
            return BridgeTrack(
                id: Int(id),
                title: object["title"]?.stringValue,
                formattedTitle: object["formattedTitle"]?.stringValue,
                language: object["language"]?.stringValue,
                codec: object["codec"]?.stringValue,
                isDefault: object["isDefault"]?.boolValue ?? false,
                isForced: object["isForced"]?.boolValue ?? false,
                isSelected: object["isSelected"]?.boolValue ?? false,
                isExternal: object["isExternal"]?.boolValue ?? false
            )
        } ?? []
    }

    private func waitForPlugin() async throws {
        for _ in 0..<60 {
            if isBridgeReady { return }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw PlaybackLaunchError.pluginUnavailable
    }

    private func nextSequence() -> UInt64 {
        defer { sequence += 1 }
        return sequence
    }

    private var pluginRequiresInstallation: Bool {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return true
        }
        let pluginURL = applicationSupport
            .appendingPathComponent("com.colliderli.iina/plugins", isDirectory: true)
            .appendingPathComponent(
                "\(BridgePairingStore.pluginIdentifier).iinaplugin",
                isDirectory: true
            )
        return IINAPluginInstallation(directoryURL: pluginURL)
            .requiresVersion(Self.minimumPluginVersion)
    }

    private func openPluginInstaller(with iinaURL: URL) async throws {
        guard let archiveURL = bundle.url(
            forResource: "CineLark",
            withExtension: "iinaplgz"
        ) else {
            throw PlaybackLaunchError.pluginUnavailable
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        try await open([archiveURL], with: iinaURL, configuration: configuration)
    }

    private func launchIINA(at applicationURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await withCheckedThrowingContinuation { continuation in
            workspace.openApplication(
                at: applicationURL,
                configuration: configuration
            ) { _, error in
                if error == nil {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PlaybackLaunchError.launchFailed)
                }
            }
        }
    }

    private func open(
        _ URLs: [URL],
        with applicationURL: URL,
        configuration: NSWorkspace.OpenConfiguration
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            workspace.open(
                URLs,
                withApplicationAt: applicationURL,
                configuration: configuration
            ) { _, error in
                if error == nil {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PlaybackLaunchError.launchFailed)
                }
            }
        }
    }
}

struct IINAApplicationTerminationTracker {
    private static let bundleIdentifier = "com.colliderli.iina"
    private(set) var activePlaybackID: UUID?

    mutating func begin(playbackID: UUID) {
        activePlaybackID = playbackID
    }

    mutating func finish(playbackID: UUID) {
        guard activePlaybackID == playbackID else { return }
        activePlaybackID = nil
    }

    mutating func applicationDidTerminate(bundleIdentifier: String?) -> UUID? {
        guard bundleIdentifier == Self.bundleIdentifier,
              let activePlaybackID else { return nil }
        self.activePlaybackID = nil
        return activePlaybackID
    }
}

struct IINAPluginInstallation {
    let directoryURL: URL

    func requiresVersion(_ minimumVersion: String) -> Bool {
        let manifestURL = directoryURL.appendingPathComponent("Info.json", isDirectory: false)
        let playerEntryURL = directoryURL.appendingPathComponent("src/main.js", isDirectory: false)
        let globalEntryURL = directoryURL.appendingPathComponent("src/global.js", isDirectory: false)
        guard FileManager.default.fileExists(atPath: playerEntryURL.path),
              FileManager.default.fileExists(atPath: globalEntryURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.identifier == BridgePairingStore.pluginIdentifier else {
            return true
        }
        return manifest.version.compare(minimumVersion, options: .numeric) == .orderedAscending
    }

    private struct Manifest: Decodable {
        let identifier: String
        let version: String
    }
}

private extension PlaybackControlCommand {
    var bridgeRepresentation: (String, [String: JSONValue]) {
        switch self {
        case .pause:
            ("player.pause", [:])
        case .resume:
            ("player.resume", [:])
        case .stop:
            ("player.stop", [:])
        case .seekRelative(let seconds, let exact):
            ("player.seekRelative", ["seconds": .number(seconds), "exact": .bool(exact)])
        case .seekAbsolute(let seconds):
            ("player.seekAbsolute", ["seconds": .number(max(seconds, 0))])
        case .setSpeed(let speed):
            ("player.setSpeed", ["speed": .number(max(speed, 0.1))])
        case .setVolume(let volume):
            ("player.setVolume", ["volume": .number(max(volume, 0))])
        case .setMuted(let muted):
            ("player.setMuted", ["muted": .bool(muted)])
        case .selectAudioTrack(let id):
            ("player.selectAudioTrack", ["id": .integer(Int64(id))])
        case .selectSubtitleTrack(let id):
            ("player.selectSubtitleTrack", ["id": .integer(Int64(id))])
        case .requestState:
            ("player.requestState", [:])
        }
    }
}
