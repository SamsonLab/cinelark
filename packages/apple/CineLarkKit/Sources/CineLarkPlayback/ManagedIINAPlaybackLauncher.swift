import AppKit
import Foundation
import OSLog
import CineLarkDomain

@MainActor
public final class ManagedIINAPlaybackLauncher: PlaybackLaunching {
    public let events: AsyncStream<PlaybackEvent>

    private static let minimumPluginVersion = "0.1.17"
    private static let logger = Logger(
        subsystem: "com.samsonlab.cinelark",
        category: "PlaybackBridge"
    )

    private let bundle: Bundle
    private let workspace: NSWorkspace
    private let pairingStore: BridgePairingStore
    private let client: BridgeProcessClient
    private let eventContinuation: AsyncStream<PlaybackEvent>.Continuation
    private var eventTask: Task<Void, Never>?
    private var secret: Data?
    private var sequence: UInt64 = 1
    private var isBridgeReady = false
    private var preparationTask: Task<Void, Error>?
    private var lifecycle = IINAApplicationTerminationTracker()
    private var eventRouter = IINAPlaybackEventRouter()
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

    public func prepare() async throws {
        if let preparationTask {
            try await preparationTask.value
            return
        }
        let task = Task { @MainActor in
            try await preparePluginInstallation()
        }
        preparationTask = task
        defer { preparationTask = nil }
        try await task.value
    }

    public func open(_ descriptor: PlaybackDescriptor) async throws {
        Self.logger.info(
            "Preparing player.play session=\(descriptor.id.uuidString, privacy: .public)"
        )
        try await prepare()
        guard let iinaURL = workspace.urlForApplication(
            withBundleIdentifier: "com.colliderli.iina"
        ) else {
            throw PlaybackLaunchError.iinaNotInstalled
        }

        let secret = try pairingStore.loadOrCreateSecret()
        self.secret = secret

        if await client.isReady() == false {
            isBridgeReady = false
        }
        try await ensureBridgeStarted(secret: secret)
        try await launchIINA(at: iinaURL)
        try await waitForPlugin()
        let envelope = playbackEnvelope(
            type: "player.play",
            descriptor: descriptor,
            sessionID: descriptor.id,
            secret: secret
        )
        try await client.send(envelope)
        Self.logger.info(
            "Queued player.play session=\(descriptor.id.uuidString, privacy: .public)"
        )
        lifecycle.begin(playbackID: descriptor.id)
    }

    public func enqueue(
        _ descriptor: PlaybackDescriptor,
        sessionID: UUID
    ) async throws {
        guard let secret else {
            throw PlaybackLaunchError.bridgeUnavailable
        }
        try await client.send(
            playbackEnvelope(
                type: "player.enqueue",
                descriptor: descriptor,
                sessionID: sessionID,
                secret: secret
            )
        )
    }

    public func send(
        _ command: PlaybackControlCommand,
        sessionID: UUID
    ) async throws {
        guard let secret else {
            throw PlaybackLaunchError.bridgeUnavailable
        }
        let (type, payload) = command.bridgeRepresentation
        let envelope = BridgeEnvelope(
            type: type,
            sessionID: sessionID,
            sequence: nextSequence(),
            payload: payload,
            secret: secret
        )
        try await client.send(envelope)
    }

    private func ensureBridgeStarted(secret: Data) async throws {
        if eventTask == nil {
            Self.logger.info("Starting playback bridge event listener")
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
            Self.logger.error(
                "Rejected unauthenticated bridge event type=\(envelope.type, privacy: .public)"
            )
            eventContinuation.yield(
                .bridgeError(
                    code: "authentication_failed",
                    message: "The bridge rejected an unauthenticated event."
                )
            )
            return
        }

        let sessionID = envelope.sessionID.flatMap(UUID.init(uuidString:))
        let payloadPlaybackID = envelope.payload["playbackID"]?.stringValue
            .flatMap(UUID.init(uuidString:))
        let playbackID = eventRouter.playbackID(
            eventType: envelope.type,
            sessionID: sessionID,
            payloadPlaybackID: payloadPlaybackID
        )
        switch envelope.type {
        case "bridge.ready":
            let pluginVersion = envelope.payload["pluginVersion"]?.stringValue
            guard let pluginVersion,
                  IINAPluginInstallation.isVersion(
                    pluginVersion,
                    atLeast: Self.minimumPluginVersion
                  ) else {
                Self.logger.error(
                    "Rejected outdated IINA bridge ready event version=\(pluginVersion ?? "missing", privacy: .public)"
                )
                return
            }
            isBridgeReady = true
            Self.logger.info(
                "IINA bridge is ready pluginVersion=\(pluginVersion, privacy: .public)"
            )
            eventContinuation.yield(.bridgeReady)
        case "bridge.error":
            Self.logger.error(
                "IINA bridge error code=\(envelope.payload["code"]?.stringValue ?? "bridge_error", privacy: .public)"
            )
            eventContinuation.yield(
                .bridgeError(
                    code: envelope.payload["code"]?.stringValue ?? "bridge_error",
                    message: envelope.payload["message"]?.stringValue ?? "The bridge reported an error."
                )
            )
        case "player.fileLoaded":
            guard let playbackID else {
                Self.logger.error("Dropped player.fileLoaded without a playback ID")
                return
            }
            Self.logger.info(
                "IINA loaded playback=\(playbackID.uuidString, privacy: .public)"
            )
            lifecycle.begin(playbackID: playbackID)
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
            guard let playbackID else {
                Self.logger.error("Dropped player.ended without a playback ID")
                return
            }
            let reason = envelope.payload["reason"]?.stringValue ?? "unknown"
            Self.logger.info(
                "IINA ended playback=\(playbackID.uuidString, privacy: .public) reason=\(reason, privacy: .public)"
            )
            lifecycle.finish(playbackID: playbackID)
            eventContinuation.yield(
                .ended(
                    playbackID: playbackID,
                    reason: reason
                )
            )
        case "player.closed":
            guard let playbackID else {
                Self.logger.error("Dropped player.closed without a playback ID")
                return
            }
            let reason = envelope.payload["reason"]?.stringValue ?? "unknown"
            Self.logger.info(
                "IINA closed playback=\(playbackID.uuidString, privacy: .public) reason=\(reason, privacy: .public)"
            )
            lifecycle.finish(playbackID: playbackID)
            eventContinuation.yield(
                .closed(
                    playbackID: playbackID,
                    reason: reason
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

    private func waitForPlugin(attempts: Int = 60) async throws {
        for _ in 0..<attempts {
            if isBridgeReady { return }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw PlaybackLaunchError.pluginUnavailable
    }

    private func nextSequence() -> UInt64 {
        defer { sequence += 1 }
        return sequence
    }

    private func playbackEnvelope(
        type: String,
        descriptor: PlaybackDescriptor,
        sessionID: UUID,
        secret: Data
    ) -> BridgeEnvelope {
        BridgeEnvelope(
            type: type,
            sessionID: sessionID,
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
    }

    private func preparePluginInstallation() async throws {
        guard let iinaURL = workspace.urlForApplication(
            withBundleIdentifier: "com.colliderli.iina"
        ) else {
            throw PlaybackLaunchError.iinaNotInstalled
        }

        guard let installation = installedPlugin else {
            throw PlaybackLaunchError.pluginInstallationFailed
        }
        switch installation.state(requiring: Self.minimumPluginVersion) {
        case .current:
            return
        case .missing:
            guard !isIINARunning else {
                throw PlaybackLaunchError.pluginSetupRequiresIINAQuit
            }
            let secret = try pairingStore.loadOrCreateSecret()
            self.secret = secret
            isBridgeReady = false
            try await ensureBridgeStarted(secret: secret)
            Self.logger.info("Opening IINA Bridge first-install consent flow")
            try await openPluginInstaller(with: iinaURL)
            do {
                try await waitForPlugin(attempts: 450)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if case .current = installation.state(
                    requiring: Self.minimumPluginVersion
                ) {
                    throw PlaybackLaunchError.pluginUnavailable
                }
                throw PlaybackLaunchError.pluginInstallationRequired
            }
        case .invalid, .outdated:
            guard !isIINARunning else {
                throw PlaybackLaunchError.pluginSetupRequiresIINAQuit
            }
            guard let bundledPluginURL = bundle.url(
                forResource: "CineLark",
                withExtension: "iinaplugin"
            ) else {
                throw PlaybackLaunchError.pluginInstallationFailed
            }
            do {
                try installation.replace(
                    with: bundledPluginURL,
                    requiring: Self.minimumPluginVersion
                )
                Self.logger.info("Safely replaced the stopped IINA Bridge installation")
            } catch {
                Self.logger.error(
                    "Failed to replace the stopped IINA Bridge installation error=\(String(describing: error), privacy: .public)"
                )
                throw PlaybackLaunchError.pluginInstallationFailed
            }
        }
    }

    private var installedPlugin: IINAPluginInstallation? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        let pluginURL = applicationSupport
            .appendingPathComponent("com.colliderli.iina/plugins", isDirectory: true)
            .appendingPathComponent(
                "\(BridgePairingStore.pluginIdentifier).iinaplugin",
                isDirectory: true
            )
        return IINAPluginInstallation(directoryURL: pluginURL)
    }

    private var isIINARunning: Bool {
        workspace.runningApplications.contains {
            $0.bundleIdentifier == "com.colliderli.iina" && !$0.isTerminated
        }
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

struct IINAPlaybackEventRouter {
    private var activePlaybackBySession: [UUID: UUID] = [:]

    mutating func playbackID(
        eventType: String,
        sessionID: UUID?,
        payloadPlaybackID: UUID?
    ) -> UUID? {
        let playbackID = payloadPlaybackID
            ?? sessionID.flatMap { activePlaybackBySession[$0] }
            ?? sessionID
        if eventType == "player.fileLoaded",
           let sessionID,
           let playbackID {
            activePlaybackBySession[sessionID] = playbackID
        } else if eventType == "player.closed", let sessionID {
            activePlaybackBySession[sessionID] = nil
        }
        return playbackID
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
    enum State: Equatable {
        case missing
        case invalid
        case outdated(version: String)
        case current(version: String)
    }

    enum InstallationError: Error {
        case invalidBundledPlugin
        case invalidInstalledPlugin
    }

    let directoryURL: URL

    func state(requiring minimumVersion: String) -> State {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: directoryURL.path,
            isDirectory: &isDirectory
        ) else {
            return .missing
        }
        guard isDirectory.boolValue else { return .invalid }

        let manifestURL = directoryURL.appendingPathComponent("Info.json", isDirectory: false)
        let playerEntryURL = directoryURL.appendingPathComponent("src/main.js", isDirectory: false)
        let globalEntryURL = directoryURL.appendingPathComponent("src/global.js", isDirectory: false)
        guard FileManager.default.fileExists(atPath: playerEntryURL.path),
              FileManager.default.fileExists(atPath: globalEntryURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.identifier == BridgePairingStore.pluginIdentifier,
              Self.versionComponents(manifest.version) != nil else {
            return .invalid
        }
        return Self.isVersion(manifest.version, atLeast: minimumVersion)
            ? .current(version: manifest.version)
            : .outdated(version: manifest.version)
    }

    func replace(with bundledDirectoryURL: URL, requiring minimumVersion: String) throws {
        guard case .current = IINAPluginInstallation(
            directoryURL: bundledDirectoryURL
        ).state(requiring: minimumVersion) else {
            throw InstallationError.invalidBundledPlugin
        }

        let fileManager = FileManager.default
        let parentURL = directoryURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parentURL,
            withIntermediateDirectories: true
        )
        let stagingURL = parentURL.appendingPathComponent(
            ".cinelark-plugin-staging-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: stagingURL) }

        try fileManager.copyItem(at: bundledDirectoryURL, to: stagingURL)
        guard case .current = IINAPluginInstallation(
            directoryURL: stagingURL
        ).state(requiring: minimumVersion) else {
            throw InstallationError.invalidBundledPlugin
        }

        if fileManager.fileExists(atPath: directoryURL.path) {
            _ = try fileManager.replaceItemAt(
                directoryURL,
                withItemAt: stagingURL,
                backupItemName: nil,
                options: .usingNewMetadataOnly
            )
        } else {
            try fileManager.moveItem(at: stagingURL, to: directoryURL)
        }

        guard case .current = state(requiring: minimumVersion) else {
            throw InstallationError.invalidInstalledPlugin
        }
    }

    static func isVersion(_ version: String, atLeast minimumVersion: String) -> Bool {
        guard let version = versionComponents(version),
              let minimumVersion = versionComponents(minimumVersion) else {
            return false
        }
        let componentCount = max(version.count, minimumVersion.count)
        for index in 0..<componentCount {
            let component = index < version.count ? version[index] : 0
            let minimumComponent = index < minimumVersion.count ? minimumVersion[index] : 0
            if component != minimumComponent {
                return component > minimumComponent
            }
        }
        return true
    }

    private static func versionComponents(_ version: String) -> [UInt]? {
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return nil }
        let parsed = components.compactMap { UInt(String($0)) }
        return parsed.count == components.count ? parsed : nil
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
        case .setFullscreen(let fullscreen):
            ("player.setFullscreen", ["fullscreen": .bool(fullscreen)])
        case .selectAudioTrack(let id):
            ("player.selectAudioTrack", ["id": .integer(Int64(id))])
        case .selectSubtitleTrack(let id):
            ("player.selectSubtitleTrack", ["id": .integer(Int64(id))])
        case .disableSubtitles:
            ("player.disableSubtitles", [:])
        case .requestState:
            ("player.requestState", [:])
        }
    }
}
