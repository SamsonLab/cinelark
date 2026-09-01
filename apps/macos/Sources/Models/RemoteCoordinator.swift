import AppKit
import CineLarkPlayback
import CineLarkRemote
import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class RemoteCoordinator {
    struct StateSnapshot: Equatable, Sendable {
        let status: Status
        let pairingDisplay: PairingDisplay?
        let pendingPairings: [RemotePairingRequest]
        let pairedDevices: [RemoteDeviceRecord]
        let connectedDeviceIDs: Set<UUID>
        let errorCode: String?
    }

    struct PlaybackState: Equatable, Sendable {
        let playbackID: UUID
        let state: PlaybackSnapshot.State
        let title: String
        let positionSeconds: Double
        let durationSeconds: Double
        let speed: Double
        let volume: Double
        let muted: Bool
        let fullscreen: Bool
        let audioTracks: [BridgeTrack]
        let subtitleTracks: [BridgeTrack]
    }

    struct PairingDisplay: Equatable, Sendable {
        let payload: String
        let expiresAt: Date
    }

    enum Status: Equatable, Sendable {
        case stopped
        case starting
        case ready(port: UInt16)
        case failed
    }

    private static let logger = Logger(
        subsystem: "com.samsonlab.cinelark",
        category: "Remote"
    )
    private static let pairingDuration: TimeInterval = 5 * 60
    private static let allCapabilities = RemoteCapabilityPolicy.advertised

    private(set) var status: Status = .stopped
    private(set) var pairingDisplay: PairingDisplay?
    private(set) var pendingPairings: [RemotePairingRequest] = []
    private(set) var pairedDevices: [RemoteDeviceRecord] = []
    private(set) var connectedDeviceIDs: Set<UUID> = []
    private(set) var errorCode: String?

    var stateSnapshot: StateSnapshot {
        StateSnapshot(
            status: status,
            pairingDisplay: pairingDisplay,
            pendingPairings: pendingPairings,
            pairedDevices: pairedDevices,
            connectedDeviceIDs: connectedDeviceIDs,
            errorCode: errorCode
        )
    }

    @ObservationIgnored private let shortcuts: ShortcutCoordinator
    @ObservationIgnored private let textInput: RemoteTextInputCoordinator
    @ObservationIgnored private let client: any RemoteGatewayTransport
    @ObservationIgnored private let store: RemoteCredentialStore
    @ObservationIgnored private let panelDismissal = RemotePanelDismissalRegistry()
    @ObservationIgnored private var storedState: RemoteGatewayStoredState?
    @ObservationIgnored private var ready: RemoteGatewayReady?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var outboundTask: Task<Void, Never>?
    @ObservationIgnored private var pairingExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var bonjourService: NetService?
    @ObservationIgnored private var appRevision: UInt64 = 0
    @ObservationIgnored private var playbackRevision: UInt64 = 0
    @ObservationIgnored private var playbackState: PlaybackState?
    @ObservationIgnored private var playbackCommand: (@MainActor (PlaybackControlCommand) -> Void)?

    init(
        shortcuts: ShortcutCoordinator,
        textInput: RemoteTextInputCoordinator,
        client: any RemoteGatewayTransport,
        store: RemoteCredentialStore = RemoteCredentialStore()
    ) {
        self.shortcuts = shortcuts
        self.textInput = textInput
        self.store = store
        self.client = client
        shortcuts.onSectionChanged = { [weak self] in
            self?.publishAppState()
        }
        textInput.onSnapshotChanged = { [weak self] in
            self?.publishTextInputState()
        }
    }

    func configurePlayback(
        command: @escaping @MainActor (PlaybackControlCommand) -> Void
    ) {
        playbackCommand = command
    }

    func updatePlayback(_ state: PlaybackState?) {
        guard playbackState != state else { return }
        playbackState = state
        playbackRevision &+= 1
        publishPlaybackState()
    }

    func start() async {
        guard status == .stopped || status == .failed else { return }
        status = .starting
        errorCode = nil
        do {
            let state = try await store.loadOrCreate()
            storedState = state
            pairedDevices = state.devices.sorted { $0.pairedAt < $1.pairedAt }
            let stream = await client.eventStream()
            eventTask = Task { @MainActor [weak self] in
                for await event in stream {
                    await self?.handle(event)
                }
            }
            let configuration = RemoteGatewayConfiguration(
                serviceID: state.serviceID,
                name: deviceName,
                identity: state.identity,
                devices: state.devices
            )
            let ready = try await client.start(configuration: configuration)
            self.ready = ready
            status = .ready(port: ready.port)
            publishBonjour(port: ready.port, serviceID: state.serviceID)
        } catch {
            eventTask?.cancel()
            eventTask = nil
            await client.stop()
            Self.logger.error("Failed to start the Remote gateway")
            errorCode = "gatewayUnavailable"
            status = .failed
        }
    }

    func stop() async {
        pairingExpiryTask?.cancel()
        pairingExpiryTask = nil
        eventTask?.cancel()
        eventTask = nil
        bonjourService?.stop()
        bonjourService = nil
        await outboundTask?.value
        outboundTask = nil
        await client.stop()
        ready = nil
        pairingDisplay = nil
        pendingPairings = []
        connectedDeviceIDs = []
        status = .stopped
    }

    func beginPairing() async {
        guard let state = storedState, let ready else {
            errorCode = "gatewayUnavailable"
            return
        }
        do {
            let secret = try RemoteSecret.generate()
            let expiresAt = Date().addingTimeInterval(Self.pairingDuration)
            try await client.startPairing(secret: secret, expiresAt: expiresAt)
            let payload = RemotePairingPayload(
                serviceID: state.serviceID.uuidString.lowercased(),
                name: deviceName,
                platform: "macos",
                host: try RemoteNetworkAddress.preferredIPv4Address(),
                port: ready.port,
                fingerprint: ready.fingerprint,
                secret: secret.remoteBase64URLEncodedString(),
                expiresAt: expiresAt
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(payload)
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw RemoteGatewayError.invalidFrame
            }
            pairingDisplay = PairingDisplay(payload: encoded, expiresAt: expiresAt)
            pendingPairings = []
            errorCode = nil
            pairingExpiryTask?.cancel()
            pairingExpiryTask = Task { @MainActor [weak self] in
                try? await Task.sleep(until: .now + .seconds(Self.pairingDuration))
                guard !Task.isCancelled else { return }
                await self?.endPairing()
            }
        } catch {
            Self.logger.error("Failed to open a Remote pairing window")
            errorCode = "pairingUnavailable"
        }
    }

    func endPairing() async {
        pairingExpiryTask?.cancel()
        pairingExpiryTask = nil
        try? await client.stopPairing()
        pairingDisplay = nil
        pendingPairings = []
    }

    func approve(_ request: RemotePairingRequest) async {
        guard pendingPairings.contains(where: { $0.id == request.id }) else { return }
        do {
            let credential = try RemoteSecret.generate().remoteBase64URLEncodedString()
            let device = RemoteDeviceRecord(
                id: request.deviceID,
                name: request.deviceName,
                credential: credential,
                capabilities: Self.allCapabilities
            )
            try await store.upsertDevice(device)
            try await client.approvePairing(connectionID: request.connectionID, device: device)
            pairedDevices.removeAll { $0.id == device.id }
            pairedDevices.append(device)
            pendingPairings = []
            pairingDisplay = nil
            pairingExpiryTask?.cancel()
            pairingExpiryTask = nil
        } catch {
            try? await store.removeDevice(request.deviceID)
            Self.logger.error("Failed to approve a Remote pairing request")
            errorCode = "pairingUnavailable"
        }
    }

    func reject(_ request: RemotePairingRequest) async {
        try? await client.rejectPairing(connectionID: request.connectionID)
        await endPairing()
    }

    func revoke(_ device: RemoteDeviceRecord) async {
        do {
            try await store.removeDevice(device.id)
            try await client.revokeDevice(device.id)
            pairedDevices.removeAll { $0.id == device.id }
            connectedDeviceIDs.remove(device.id)
        } catch {
            errorCode = "gatewayUnavailable"
        }
    }

    func registerPanelPresentation(
        id: UUID,
        dismiss: @escaping @MainActor () -> Void
    ) {
        panelDismissal.register(id: id, dismiss: dismiss)
    }

    func unregisterPanelPresentation(id: UUID) {
        panelDismissal.unregister(id: id)
    }

    private func handle(_ event: RemoteGatewayEvent) async {
        switch event {
        case .identityGenerated(let identity, _):
            do {
                try await store.saveIdentity(identity)
                storedState?.identity = identity
            } catch {
                errorCode = "gatewayIdentityUnavailable"
            }
        case .ready(let ready):
            self.ready = ready
        case .pairingRequested(let request):
            guard !pairedDevices.contains(where: { $0.id == request.deviceID }) else {
                try? await client.rejectPairing(
                    connectionID: request.connectionID,
                    code: "pairingRejected"
                )
                await endPairing()
                return
            }
            pendingPairings.removeAll { $0.deviceID == request.deviceID }
            pendingPairings.append(request)
        case .connected(let connectionID, let deviceID):
            connectedDeviceIDs.insert(deviceID)
            do {
                try await sendInitialSnapshots(to: connectionID, deviceID: deviceID)
            } catch {
                Self.logger.error("Failed to send initial Remote state")
            }
        case .envelope(let connectionID, let deviceID, let envelope):
            await handle(envelope, from: connectionID, deviceID: deviceID)
        case .disconnected(let connectionID, let deviceID, _):
            pendingPairings.removeAll { $0.connectionID == connectionID }
            if let deviceID { connectedDeviceIDs.remove(deviceID) }
        case .error(let code):
            Self.logger.error("Remote gateway reported code=\(code, privacy: .public)")
            errorCode = code
            if code == "gatewayUnavailable" {
                pairingExpiryTask?.cancel()
                pairingExpiryTask = nil
                bonjourService?.stop()
                bonjourService = nil
                ready = nil
                pairingDisplay = nil
                pendingPairings = []
                connectedDeviceIDs = []
                status = .failed
            }
        }
    }

    private func handle(
        _ envelope: RemoteEnvelope,
        from connectionID: UUID,
        deviceID: UUID
    ) async {
        let interval = CineLarkPerformanceMonitor.shared.start(.remoteCommand)
        var performanceOutcome = CineLarkPerformanceOutcome.success
        defer {
            CineLarkPerformanceMonitor.shared.finish(interval, outcome: performanceOutcome)
        }
        do {
            try await execute(envelope, connectionID: connectionID, deviceID: deviceID)
            try await sendAcknowledgement(
                connectionID: connectionID,
                replyTo: envelope.id,
                accepted: true,
                code: nil
            )
        } catch let error as RemoteCommandError {
            performanceOutcome = .failure
            try? await sendAcknowledgement(
                connectionID: connectionID,
                replyTo: envelope.id,
                accepted: false,
                code: error.code
            )
        } catch {
            performanceOutcome = .failure
            try? await sendAcknowledgement(
                connectionID: connectionID,
                replyTo: envelope.id,
                accepted: false,
                code: "internal"
            )
        }
    }

    private func execute(
        _ envelope: RemoteEnvelope,
        connectionID: UUID,
        deviceID: UUID
    ) async throws {
        try authorize(envelope.type, for: deviceID)
        switch envelope.type {
        case "app.requestSnapshot":
            try await sendInitialSnapshots(to: connectionID, deviceID: deviceID)
        case "app.activate":
            activateApp()
        case "auth.submitCredentials":
            throw RemoteCommandError("unsupportedCapability")
        case "navigation.move":
            activateApp()
            guard let raw = envelope.payload.string("direction"),
                  let direction = remoteDirection(raw),
                  shortcuts.moveFocus(direction) else {
                throw RemoteCommandError("invalidState")
            }
        case "navigation.select":
            activateApp()
            guard shortcuts.activateFocusedItem() else {
                throw RemoteCommandError("invalidState")
            }
        case "navigation.back":
            if panelDismissal.dismissIfPresented() {
                return
            }
            activateApp()
            guard shortcuts.navigateBackSemantically() else {
                throw RemoteCommandError("invalidState")
            }
        case "navigation.openSection":
            activateApp()
            guard let raw = envelope.payload.string("section"),
                  let section = CineLarkSection(rawValue: raw),
                  shortcuts.openSection(section) else {
                throw RemoteCommandError("invalidState")
            }
        case "textInput.update":
            let (sessionID, revision) = try textSessionScope(envelope.payload)
            guard let text = envelope.payload.string("text") else {
                throw RemoteCommandError("invalidMessage")
            }
            do {
                try textInput.update(sessionID: sessionID, revision: revision, text: text)
            } catch {
                throw textInputError(error)
            }
        case "textInput.commit":
            let (sessionID, revision) = try textSessionScope(envelope.payload)
            do {
                try textInput.commit(sessionID: sessionID, revision: revision)
            } catch {
                throw textInputError(error)
            }
        case "textInput.cancel":
            let (sessionID, revision) = try textSessionScope(envelope.payload)
            do {
                try textInput.cancel(sessionID: sessionID, revision: revision)
            } catch {
                throw textInputError(error)
            }
        case "playback.requestSnapshot":
            try await sendPlaybackSnapshot(to: connectionID)
        case "playback.togglePause":
            let snapshot = try playbackScope(envelope.payload)
            try sendPlayback(snapshot.state == .playing ? .pause : .resume)
        case "playback.pause":
            _ = try playbackScope(envelope.payload)
            try sendPlayback(.pause)
        case "playback.resume":
            _ = try playbackScope(envelope.payload)
            try sendPlayback(.resume)
        case "playback.stop":
            _ = try playbackScope(envelope.payload)
            try sendPlayback(.stop)
        case "playback.seekRelative":
            _ = try playbackScope(envelope.payload)
            guard let seconds = envelope.payload.number("seconds"),
                  (-3600...3600).contains(seconds) else {
                throw RemoteCommandError("invalidMessage")
            }
            try sendPlayback(
                .seekRelative(seconds: seconds, exact: envelope.payload.bool("exact") ?? false)
            )
        case "playback.seekAbsolute":
            let snapshot = try playbackScope(envelope.payload)
            guard let seconds = envelope.payload.number("seconds"), seconds >= 0,
                  snapshot.durationSeconds == 0 || seconds <= snapshot.durationSeconds else {
                throw RemoteCommandError("invalidMessage")
            }
            try sendPlayback(.seekAbsolute(seconds: seconds))
        case "playback.setRate":
            _ = try playbackScope(envelope.payload)
            guard let rate = envelope.payload.number("rate"), (0.25...4).contains(rate) else {
                throw RemoteCommandError("invalidMessage")
            }
            try sendPlayback(.setSpeed(rate))
        case "playback.setFullscreen":
            _ = try playbackScope(envelope.payload)
            guard let fullscreen = envelope.payload.bool("fullscreen") else {
                throw RemoteCommandError("invalidMessage")
            }
            try sendPlayback(.setFullscreen(fullscreen))
        case "playback.playPrevious":
            throw RemoteCommandError("unsupportedCapability")
        case "playback.playNext":
            throw RemoteCommandError("unsupportedCapability")
        case "playback.selectAudioTrack":
            let snapshot = try revisionedPlaybackScope(envelope.payload)
            guard let trackID = envelope.payload.int("trackID"),
                  snapshot.audioTracks.contains(where: { $0.id == trackID }) else {
                throw RemoteCommandError("invalidMessage")
            }
            try sendPlayback(.selectAudioTrack(trackID))
        case "playback.selectSubtitleTrack":
            let snapshot = try revisionedPlaybackScope(envelope.payload)
            if envelope.payload["trackID"] == .null {
                try sendPlayback(.disableSubtitles)
            } else {
                guard let trackID = envelope.payload.int("trackID"),
                      snapshot.subtitleTracks.contains(where: { $0.id == trackID }) else {
                    throw RemoteCommandError("invalidMessage")
                }
                try sendPlayback(.selectSubtitleTrack(trackID))
            }
        case "playback.closeAndActivateApp":
            _ = try playbackScope(envelope.payload)
            try sendPlayback(.stop)
            activateApp()
        case "audio.setVolume":
            _ = try playbackScope(envelope.payload)
            guard let volume = envelope.payload.number("volume"), (0...100).contains(volume) else {
                throw RemoteCommandError("invalidMessage")
            }
            try sendPlayback(.setVolume(volume))
        case "audio.adjustVolume":
            let snapshot = try playbackScope(envelope.payload)
            guard let delta = envelope.payload.number("delta"), (-100...100).contains(delta) else {
                throw RemoteCommandError("invalidMessage")
            }
            try sendPlayback(.setVolume(min(max(snapshot.volume + delta, 0), 100)))
        case "audio.setMuted":
            _ = try playbackScope(envelope.payload)
            guard let muted = envelope.payload.bool("muted") else {
                throw RemoteCommandError("invalidMessage")
            }
            try sendPlayback(.setMuted(muted))
        default:
            throw RemoteCommandError("unsupportedCapability")
        }
    }

    private func authorize(_ messageType: String, for deviceID: UUID) throws {
        guard pairedDevices.contains(where: { $0.id == deviceID }) else {
            throw RemoteCommandError("unauthenticated")
        }
        guard let requiredCapability = RemoteCapabilityPolicy.requiredCapability(
            for: messageType
        ) else { return }
        guard capabilities.contains(requiredCapability),
              pairedDevices.contains(where: {
                  $0.id == deviceID && $0.capabilities.contains(requiredCapability)
              }) else {
            throw RemoteCommandError("unsupportedCapability")
        }
    }

    private func sendInitialSnapshots(to connectionID: UUID, deviceID: UUID) async throws {
        try await client.send(
            connectionID: connectionID,
            type: "session.ready",
            payload: [
                "protocolVersion": .integer(1),
                "deviceID": .string(deviceID.uuidString.lowercased()),
                "capabilities": .array(capabilities.map(RemoteJSONValue.string))
            ]
        )
        try await sendAppSnapshot(to: connectionID)
        try await sendTextInputSnapshot(to: connectionID)
        try await sendPlaybackSnapshot(to: connectionID)
    }

    private func publishAppState() {
        appRevision &+= 1
        broadcast(type: "app.snapshot", revision: appRevision, payload: appPayload)
        publishCapabilities()
    }

    private func publishTextInputState() {
        appRevision &+= 1
        broadcast(
            type: "textInput.snapshot",
            revision: appRevision,
            payload: textInputPayload
        )
        publishCapabilities()
    }

    private func publishPlaybackState() {
        broadcast(
            type: "playback.snapshot",
            revision: playbackRevision,
            payload: playbackPayload
        )
        publishCapabilities()
    }

    private func publishCapabilities() {
        broadcast(
            type: "capabilities.changed",
            payload: ["capabilities": .array(capabilities.map(RemoteJSONValue.string))]
        )
    }

    private func sendAppSnapshot(to connectionID: UUID) async throws {
        try await client.send(
            connectionID: connectionID,
            type: "app.snapshot",
            revision: appRevision,
            payload: appPayload
        )
    }

    private func sendTextInputSnapshot(to connectionID: UUID) async throws {
        try await client.send(
            connectionID: connectionID,
            type: "textInput.snapshot",
            revision: appRevision,
            payload: textInputPayload
        )
    }

    private func sendPlaybackSnapshot(to connectionID: UUID) async throws {
        try await client.send(
            connectionID: connectionID,
            type: "playback.snapshot",
            revision: playbackRevision,
            payload: playbackPayload
        )
    }

    private func sendAcknowledgement(
        connectionID: UUID,
        replyTo: String,
        accepted: Bool,
        code: String?
    ) async throws {
        var payload: [String: RemoteJSONValue] = ["accepted": .bool(accepted)]
        if let code { payload["code"] = .string(code) }
        try await client.send(
            connectionID: connectionID,
            type: "command.ack",
            replyTo: replyTo,
            payload: payload
        )
    }

    private var appPayload: [String: RemoteJSONValue] {
        return [
            "phase": .string("signedIn"),
            "selectedSection": .string(shortcuts.currentSection.rawValue),
            "sections": .array(CineLarkSection.allCases.map { .string($0.rawValue) }),
            "errorCode": .null
        ]
    }

    private var textInputPayload: [String: RemoteJSONValue] {
        guard let snapshot = textInput.snapshot else { return ["active": .null] }
        return [
            "active": .object([
                "sessionID": .string(snapshot.sessionID.uuidString.lowercased()),
                "kind": .string(snapshot.kind),
                "text": .string(snapshot.text),
                "maximumLength": .integer(Int64(snapshot.maximumLength)),
                "revision": .integer(Int64(snapshot.revision))
            ])
        ]
    }

    private var playbackPayload: [String: RemoteJSONValue] {
        guard let snapshot = playbackState else {
            return [
                "playbackID": .null,
                "state": .string("idle"),
                "title": .null,
                "subtitle": .null,
                "artworkResourceID": .null,
                "positionSeconds": .number(0),
                "durationSeconds": .number(0),
                "speed": .number(1),
                "volume": .number(0),
                "muted": .bool(false),
                "fullscreen": .bool(false),
                "canPlayPrevious": .bool(false),
                "canPlayNext": .bool(false),
                "audioTracks": .array([]),
                "subtitleTracks": .array([])
            ]
        }
        return [
            "playbackID": .string(snapshot.playbackID.uuidString.lowercased()),
            "state": .string(snapshot.state.rawValue),
            "title": .string(snapshot.title),
            "subtitle": .null,
            "artworkResourceID": .null,
            "positionSeconds": .number(snapshot.positionSeconds),
            "durationSeconds": .number(snapshot.durationSeconds),
            "speed": .number(snapshot.speed),
            "volume": .number(snapshot.volume),
            "muted": .bool(snapshot.muted),
            "fullscreen": .bool(snapshot.fullscreen),
            "canPlayPrevious": .bool(false),
            "canPlayNext": .bool(false),
            "audioTracks": .array(snapshot.audioTracks.map { trackPayload($0, kind: "audio") }),
            "subtitleTracks": .array(snapshot.subtitleTracks.map { trackPayload($0, kind: "subtitle") })
        ]
    }

    private func trackPayload(_ track: BridgeTrack, kind: String) -> RemoteJSONValue {
        .object([
            "id": .integer(Int64(track.id)),
            "kind": .string(kind),
            "title": track.formattedTitle.map(RemoteJSONValue.string)
                ?? track.title.map(RemoteJSONValue.string)
                ?? .null,
            "language": track.language.map(RemoteJSONValue.string) ?? .null,
            "codec": track.codec.map(RemoteJSONValue.string) ?? .null,
            "selected": .bool(track.isSelected),
            "isDefault": .bool(track.isDefault),
            "isForced": .bool(track.isForced),
            "isExternal": .bool(track.isExternal)
        ])
    }

    private var capabilities: [String] {
        var values = ["navigation.basic", "navigation.sections"]
        if textInput.snapshot != nil { values.append("textInput.remote") }
        if playbackState != nil {
            values += [
                "playback.transport",
                "playback.seek",
                "playback.rate",
                "playback.fullscreen",
                "playback.trackSelection",
                "playback.closeAndActivate",
                "audio.volume"
            ]
        }
        return values
    }

    private func playbackScope(
        _ payload: [String: RemoteJSONValue]
    ) throws -> PlaybackState {
        guard let playbackID = payload.uuid("playbackID"),
              let snapshot = playbackState,
              snapshot.playbackID == playbackID else {
            throw RemoteCommandError("invalidState")
        }
        return snapshot
    }

    private func revisionedPlaybackScope(
        _ payload: [String: RemoteJSONValue]
    ) throws -> PlaybackState {
        let snapshot = try playbackScope(payload)
        guard let revision = payload.uint64("revision"),
              revision == playbackRevision else {
            throw RemoteCommandError("staleRevision")
        }
        return snapshot
    }

    private func textSessionScope(
        _ payload: [String: RemoteJSONValue]
    ) throws -> (UUID, UInt64) {
        guard let sessionID = payload.uuid("sessionID"),
              let revision = payload.uint64("revision") else {
            throw RemoteCommandError("invalidMessage")
        }
        return (sessionID, revision)
    }

    private func textInputError(_ error: Error) -> RemoteCommandError {
        switch error as? RemoteTextInputCoordinator.UpdateError {
        case .staleRevision: RemoteCommandError("staleRevision")
        case .staleSession: RemoteCommandError("invalidState")
        case .invalidText: RemoteCommandError("invalidMessage")
        case nil: RemoteCommandError("internal")
        }
    }

    private func remoteDirection(_ value: String) -> CineLarkFocusDirection? {
        switch value {
        case "left": .left
        case "right": .right
        case "up": .up
        case "down": .down
        default: nil
        }
    }

    private func sendPlayback(_ command: PlaybackControlCommand) throws {
        guard let playbackCommand else {
            throw RemoteCommandError("invalidState")
        }
        playbackCommand(command)
    }

    private func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
    }

    private func broadcast(
        type: String,
        revision: UInt64? = nil,
        payload: [String: RemoteJSONValue]
    ) {
        let previousTask = outboundTask
        outboundTask = Task {
            await previousTask?.value
            guard !Task.isCancelled else { return }
            try? await client.broadcast(type: type, revision: revision, payload: payload)
        }
    }

    private func publishBonjour(port: UInt16, serviceID: UUID) {
        bonjourService?.stop()
        let service = NetService(
            domain: "local.",
            type: "_cinelark._tcp.",
            name: deviceName,
            port: Int32(port)
        )
        service.setTXTRecord(
            NetService.data(fromTXTRecord: [
                "serviceID": Data(serviceID.uuidString.lowercased().utf8),
                "protocolMin": Data("1".utf8),
                "protocolMax": Data("1".utf8),
                "tls": Data("required".utf8)
            ])
        )
        service.publish()
        bonjourService = service
    }

    private var deviceName: String {
        Host.current().localizedName ?? "Mac"
    }
}

private struct RemotePairingPayload: Encodable {
    let protocolVersion = 1
    let serviceID: String
    let name: String
    let platform: String
    let host: String
    let port: UInt16
    let fingerprint: String
    let secret: String
    let expiresAt: Date
}

private struct RemoteCommandError: Error {
    let code: String
    init(_ code: String) { self.code = code }
}

private extension Dictionary where Key == String, Value == RemoteJSONValue {
    func string(_ key: String) -> String? { self[key]?.stringValue }
    func bool(_ key: String) -> Bool? { self[key]?.boolValue }
    func number(_ key: String) -> Double? { self[key]?.doubleValue }
    func int(_ key: String) -> Int? { self[key]?.intValue }
    func uuid(_ key: String) -> UUID? { string(key).flatMap(UUID.init(uuidString:)) }
    func uint64(_ key: String) -> UInt64? {
        guard let value = number(key), value >= 0, value.rounded() == value else { return nil }
        return UInt64(exactly: value)
    }
}
