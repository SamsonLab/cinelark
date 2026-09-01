import ComposableArchitecture
import Foundation
import Testing
import CineLarkPluginAPI
import CineLarkProfile

@testable import CineLark

private let legacyPluginID: PluginID = "com.samsonlab.cinelark.uhdnow"
private let canonicalEmbyPluginID: PluginID = "com.samsonlab.cinelark.emby"

@MainActor
struct SourceFeatureTests {
    @Test("Scheme-less public Emby URLs default to HTTPS and preserve proxy paths")
    func publicURLNormalization() async {
        let validated = LockIsolated<URL?>(nil)
        let saved = LockIsolated<PersistedMediaSource?>(nil)
        let sourceUUID = UUID()
        let normalizedURL = URL(string: "https://media.example.com/library/emby")!
        let authenticated = SourceConfiguration(
            sourceID: SourceID(rawValue: sourceUUID),
            baseURL: normalizedURL,
            serverIdentity: SourceInstanceIdentity(
                pluginID: canonicalEmbyPluginID,
                serverID: "server"
            ),
            displayName: "media.example.com",
            remoteUserID: "user-1"
        )
        var state = SourceFeature.State()
        state.setup = SourceFeature.SetupState(
            pluginID: canonicalEmbyPluginID,
            baseURL: "media.example.com/library/emby/"
        )
        let store = TestStore(initialState: state) {
            SourceFeature()
        } withDependencies: {
            $0.uuid = .constant(sourceUUID)
            $0.mediaPlatform.validate = { _, url in
                validated.setValue(url)
                return SourceInstanceIdentity(
                    pluginID: canonicalEmbyPluginID,
                    serverID: "server"
                )
            }
            $0.mediaPlatform.authenticate = { pluginID, configuration, credentials in
                #expect(pluginID == canonicalEmbyPluginID)
                #expect(configuration.baseURL == normalizedURL)
                #expect(credentials == SourceCredentials(
                    username: "samson",
                    password: "synthetic-password"
                ))
                return authenticated
            }
            $0.profiles.saveSource = { pluginID, configuration in
                saved.setValue(PersistedMediaSource(
                    pluginID: pluginID,
                    configuration: configuration
                ))
            }
        }

        await store.send(.view(.validate)) {
            $0.setup?.isValidating = true
        }
        await store.receive(\.internal) {
            $0.setup?.isValidating = false
            $0.setup?.baseURL = normalizedURL.absoluteString
            $0.setup?.validatedConfiguration = SourceConfiguration(
                sourceID: SourceID(rawValue: sourceUUID),
                baseURL: normalizedURL,
                serverIdentity: SourceInstanceIdentity(
                    pluginID: canonicalEmbyPluginID,
                    serverID: "server"
                ),
                displayName: "media.example.com"
            )
        }

        #expect(validated.value?.absoluteString == "https://media.example.com/library/emby")

        await store.send(.view(.authenticate(
            username: "samson",
            password: "synthetic-password"
        ))) {
            $0.setup?.isAuthenticating = true
        }
        let persisted = PersistedMediaSource(
            pluginID: canonicalEmbyPluginID,
            configuration: authenticated
        )
        await store.receive(\.internal) {
            $0.setup = nil
            $0.persistedSources = [persisted]
            $0.installedSourceIDs = [authenticated.sourceID]
        }
        await store.receive(\.delegate)

        #expect(saved.value == persisted)
    }

    @Test("Scheme-less local Emby URLs default to HTTP")
    func localURLNormalization() async {
        let validated = LockIsolated<URL?>(nil)
        let sourceUUID = UUID()
        let normalizedURL = URL(string: "http://192.168.1.20:8096")!
        var state = SourceFeature.State()
        state.setup = SourceFeature.SetupState(
            pluginID: canonicalEmbyPluginID,
            baseURL: "192.168.1.20:8096"
        )
        let store = TestStore(initialState: state) {
            SourceFeature()
        } withDependencies: {
            $0.uuid = .constant(sourceUUID)
            $0.mediaPlatform.validate = { _, url in
                validated.setValue(url)
                return SourceInstanceIdentity(
                    pluginID: canonicalEmbyPluginID,
                    serverID: "server"
                )
            }
        }

        await store.send(.view(.validate)) {
            $0.setup?.isValidating = true
        }
        await store.receive(\.internal) {
            $0.setup?.isValidating = false
            $0.setup?.baseURL = normalizedURL.absoluteString
            $0.setup?.validatedConfiguration = SourceConfiguration(
                sourceID: SourceID(rawValue: sourceUUID),
                baseURL: normalizedURL,
                serverIdentity: SourceInstanceIdentity(
                    pluginID: canonicalEmbyPluginID,
                    serverID: "server"
                ),
                displayName: "192.168.1.20"
            )
        }

        #expect(validated.value?.absoluteString == "http://192.168.1.20:8096")
    }

    @Test("Scheme-less localhost with a port is not mistaken for a URL scheme")
    func localhostURLNormalization() async {
        let validated = LockIsolated<URL?>(nil)
        let sourceUUID = UUID()
        let normalizedURL = URL(string: "http://localhost:8096")!
        var state = SourceFeature.State()
        state.setup = SourceFeature.SetupState(
            pluginID: canonicalEmbyPluginID,
            baseURL: "localhost:8096"
        )
        let store = TestStore(initialState: state) {
            SourceFeature()
        } withDependencies: {
            $0.uuid = .constant(sourceUUID)
            $0.mediaPlatform.validate = { _, url in
                validated.setValue(url)
                return SourceInstanceIdentity(
                    pluginID: canonicalEmbyPluginID,
                    serverID: "server"
                )
            }
        }

        await store.send(.view(.validate)) {
            $0.setup?.isValidating = true
        }
        await store.receive(\.internal) {
            $0.setup?.isValidating = false
            $0.setup?.baseURL = normalizedURL.absoluteString
            $0.setup?.validatedConfiguration = SourceConfiguration(
                sourceID: SourceID(rawValue: sourceUUID),
                baseURL: normalizedURL,
                serverIdentity: SourceInstanceIdentity(
                    pluginID: canonicalEmbyPluginID,
                    serverID: "server"
                ),
                displayName: "localhost"
            )
        }

        #expect(validated.value == normalizedURL)
    }

    @Test("Manual source URLs reject embedded credentials and query data")
    func unsafeURLRejection() async {
        let validations = LockIsolated(0)
        var state = SourceFeature.State()
        state.setup = SourceFeature.SetupState(
            pluginID: canonicalEmbyPluginID,
            baseURL: "https://user:secret@example.com/emby?api_key=secret"
        )
        let store = TestStore(initialState: state) {
            SourceFeature()
        } withDependencies: {
            $0.mediaPlatform.validate = { _, _ in
                validations.withValue { $0 += 1 }
                throw MediaSourceFailure.unavailable
            }
        }

        await store.send(.view(.validate)) {
            $0.setup?.failure = .invalidResponse
        }
        #expect(validations.value == 0)
    }

    @Test("Legacy sources restore as explicit reconnect proposals")
    func legacyRestoreRequiresReconnect() async {
        let source = legacySource()
        let proposal = migrationProposal(for: source)
        let installs = LockIsolated(0)
        let store = TestStore(initialState: SourceFeature.State()) {
            SourceFeature()
        } withDependencies: {
            $0.mediaPlatform = MediaPlatformClient(
                descriptors: { [] },
                migrationProposal: { pluginID, configuration in
                    #expect(pluginID == legacyPluginID)
                    #expect(configuration.sourceID == source.id)
                    return proposal
                },
                install: { _, _ in installs.withValue { $0 += 1 } },
                cachedPage: { _ in throw MediaSourceFailure.unavailable },
                refreshPage: { _ in throw MediaSourceFailure.unavailable }
            )
        }

        await store.send(.internal(.restoreSources([source]))) {
            $0.persistedSources = [source]
            $0.isLoading = true
        }
        await store.receive(.internal(.sourcesRestored([], [source.id: proposal], nil))) {
            $0.isLoading = false
            $0.migrationProposals = [source.id: proposal]
        }

        #expect(installs.value == 0)
    }

    @Test("Reconnect preserves Source identity and persists canonical Emby")
    func reconnectPreservesSourceIdentity() async {
        let source = legacySource()
        let proposal = migrationProposal(for: source)
        let identity = SourceInstanceIdentity(
            pluginID: canonicalEmbyPluginID,
            serverID: "emby-server"
        )
        let canonicalConfiguration = SourceConfiguration(
            sourceID: source.id,
            baseURL: proposal.suggestedBaseURL,
            serverIdentity: identity,
            displayName: source.configuration.displayName,
            remoteUserID: "emby-user"
        )
        let saved = LockIsolated<PersistedMediaSource?>(nil)
        let cleanups = LockIsolated<[(PluginID, SourceID)]>([])
        var state = SourceFeature.State()
        state.persistedSources = [source]
        state.migrationProposals = [source.id: proposal]
        let store = TestStore(initialState: state) {
            SourceFeature()
        } withDependencies: {
            $0.mediaPlatform = MediaPlatformClient(
                descriptors: { [] },
                validate: { pluginID, baseURL in
                    #expect(pluginID == canonicalEmbyPluginID)
                    #expect(baseURL == proposal.suggestedBaseURL)
                    return identity
                },
                authenticate: { pluginID, configuration, credentials in
                    #expect(pluginID == canonicalEmbyPluginID)
                    #expect(configuration.sourceID == source.id)
                    #expect(credentials.username == "samson")
                    return canonicalConfiguration
                },
                cleanupLegacyCredentials: { pluginID, sourceID in
                    cleanups.withValue { $0.append((pluginID, sourceID)) }
                },
                cachedPage: { _ in throw MediaSourceFailure.unavailable },
                refreshPage: { _ in throw MediaSourceFailure.unavailable }
            )
            $0.profiles.saveSource = { pluginID, configuration in
                saved.setValue(PersistedMediaSource(
                    pluginID: pluginID,
                    configuration: configuration
                ))
            }
        }

        await store.send(.view(.beginMigration(source.id))) {
            $0.setup = SourceFeature.SetupState(
                pluginID: canonicalEmbyPluginID,
                sourceID: source.id,
                legacyPluginID: legacyPluginID,
                baseURL: proposal.suggestedBaseURL.absoluteString,
                displayName: proposal.displayName
            )
        }
        await store.send(.view(.validate)) {
            $0.setup?.isValidating = true
        }
        await store.receive(.internal(.validationCompleted(.success(
            SourceConfiguration(
                sourceID: source.id,
                baseURL: proposal.suggestedBaseURL,
                serverIdentity: identity,
                displayName: proposal.displayName
            )
        )))) {
            $0.setup?.isValidating = false
            $0.setup?.validatedConfiguration = SourceConfiguration(
                sourceID: source.id,
                baseURL: proposal.suggestedBaseURL,
                serverIdentity: identity,
                displayName: proposal.displayName
            )
        }
        await store.send(.view(.authenticate(username: "samson", password: "secret"))) {
            $0.setup?.isAuthenticating = true
        }
        let persisted = PersistedMediaSource(
            pluginID: canonicalEmbyPluginID,
            configuration: canonicalConfiguration
        )
        await store.receive(.internal(.authenticationCompleted(.success(persisted)))) {
            $0.setup = nil
            $0.persistedSources = [persisted]
            $0.installedSourceIDs = [source.id]
            $0.migrationProposals = [:]
        }
        await store.receive(.delegate(.sourceSaved(persisted)))

        #expect(saved.value == persisted)
        #expect(cleanups.value.map(\.0) == [legacyPluginID])
        #expect(cleanups.value.map(\.1) == [source.id])
    }

    @Test("Failed canonical validation leaves the legacy source recoverable")
    func failedValidationPreservesMigration() async {
        let source = legacySource()
        let proposal = migrationProposal(for: source)
        var state = SourceFeature.State()
        state.persistedSources = [source]
        state.migrationProposals = [source.id: proposal]
        let store = TestStore(initialState: state) {
            SourceFeature()
        } withDependencies: {
            $0.mediaPlatform = MediaPlatformClient(
                descriptors: { [] },
                validate: { _, _ in throw MediaSourceFailure.unavailable },
                cachedPage: { _ in throw MediaSourceFailure.unavailable },
                refreshPage: { _ in throw MediaSourceFailure.unavailable }
            )
        }

        await store.send(.view(.beginMigration(source.id))) {
            $0.setup = SourceFeature.SetupState(
                pluginID: canonicalEmbyPluginID,
                sourceID: source.id,
                legacyPluginID: legacyPluginID,
                baseURL: proposal.suggestedBaseURL.absoluteString,
                displayName: proposal.displayName
            )
        }
        await store.send(.view(.validate)) {
            $0.setup?.isValidating = true
        }
        await store.receive(.internal(.validationCompleted(.failure(.unavailable)))) {
            $0.setup?.isValidating = false
            $0.setup?.failure = .unavailable
        }

        #expect(store.state.persistedSources == [source])
        #expect(store.state.migrationProposals == [source.id: proposal])
    }
}

private func legacySource() -> PersistedMediaSource {
    let sourceID = SourceID(rawValue: UUID())
    return PersistedMediaSource(
        pluginID: legacyPluginID,
        configuration: SourceConfiguration(
            sourceID: sourceID,
            baseURL: URL(string: "https://www.uhdnow.com/api/v1")!,
            serverIdentity: SourceInstanceIdentity(
                pluginID: legacyPluginID,
                serverID: "www.uhdnow.com/api/v1"
            ),
            displayName: "UHDNow"
        )
    )
}

private func migrationProposal(for source: PersistedMediaSource) -> SourceMigrationProposal {
    SourceMigrationProposal(
        sourceID: source.id,
        legacyPluginID: legacyPluginID,
        targetPluginID: canonicalEmbyPluginID,
        suggestedBaseURL: URL(string: "https://www.uhdnow.com")!,
        displayName: source.configuration.displayName
    )
}
