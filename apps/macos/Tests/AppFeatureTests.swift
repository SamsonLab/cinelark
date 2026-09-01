import ComposableArchitecture
import Foundation
import Testing
import CineLarkInsights
import CineLarkProfile
import CineLarkPluginAPI

@testable import CineLark

@MainActor
struct AppFeatureTests {
    @Test("External CloudKit changes refresh the active local projection")
    func externalProfileChangeRefreshesLibrary() async {
        let profileID = ProfileID(rawValue: UUID())
        let sourceID = SourceID(rawValue: UUID())
        var state = AppFeature.State()
        state.library.profileID = profileID
        state.library.sourceID = sourceID
        state.navigation.selection = .insights
        state.insights.activeProfileID = profileID
        state.insights.activeSourceID = sourceID
        state.insights.isPresented = true
        let refreshes = LockIsolated(0)
        let insightRefreshes = LockIsolated(0)
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.date.now = referenceDate
            $0.uuid = .constant(UUID())
            $0.mediaPlatform.cachedPage = { _ in
                MediaPage(items: [], nextCursor: nil, total: 0)
            }
            $0.mediaPlatform.latest = { _ in
                MediaPage(items: [], nextCursor: nil, total: 0)
            }
            $0.mediaPlatform.collections = { _ in
                refreshes.withValue { $0 += 1 }
                return []
            }
            $0.profiles.state = { _ in
                ProfileStateSnapshot(states: [:], snapshots: [:])
            }
            $0.insights.load = { loadedProfileID, loadedSourceID, _, date in
                #expect(loadedSourceID == sourceID)
                insightRefreshes.withValue { $0 += 1 }
                return ViewingInsightsSnapshot(
                    profileID: loadedProfileID,
                    range: ViewingInsightRange(period: .month, start: date, end: date),
                    totalWatchSeconds: 0,
                    sessionCount: 0,
                    completedSessionCount: 0,
                    distinctTitleCount: 0,
                    activeDayCount: 0,
                    longestStreakDays: 0,
                    activity: [],
                    topTitles: [],
                    topGenres: [],
                    topDirectors: [],
                    topActors: []
                )
            }
        }
        store.exhaustivity = .off

        await store.send(.profile(.internal(.repositoryChanged(.external))))
        await store.skipReceivedActions(strict: false)

        #expect(refreshes.value == 1)
        #expect(insightRefreshes.value == 1)
    }

    @Test("Bootstrap applies persisted context after source runtimes are restored")
    func bootstrapAppliesContextAfterSourceRestore() async {
        let profileID = ProfileID(rawValue: UUID())
        let sourceID = SourceID(rawValue: UUID())
        let selection = ActiveProfileSelection(
            profileID: profileID,
            sourceID: sourceID
        )
        var state = AppFeature.State()
        state.pendingBootstrapSelection = selection
        state.source.isLoading = true
        let store = TestStore(initialState: state) {
            AppFeature()
        }
        store.exhaustivity = .off

        await store.send(.source(.internal(.sourcesRestored([sourceID], [:], nil)))) {
            $0.pendingBootstrapSelection = nil
            $0.source.isLoading = false
            $0.source.installedSourceIDs = [sourceID]
        }
        await store.skipReceivedActions(strict: false)

        #expect(store.state.library.profileID == profileID)
        #expect(store.state.library.sourceID == sourceID)
        #expect(store.state.search.sourceID == sourceID)
        #expect(store.state.insights.activeProfileID == profileID)
        #expect(store.state.insights.activeSourceID == sourceID)
        #expect(store.state.playback.profileID == profileID)
        #expect(store.state.navigation.activeProfileID == profileID)
        #expect(store.state.navigation.activeSourceID == sourceID)
        #expect(store.state.bootstrap == .ready)
    }

    @Test("Personal Profile bootstrap proceeds without a selection flow")
    func bootstrapProceedsWithPersonalProfile() async {
        let date = Date(timeIntervalSince1970: 100)
        let manifest = ProfileManifest(
            profile: Profile(
                id: .personal,
                name: "Personal",
                createdAt: date,
                modifiedAt: date,
                deviceID: "this-mac"
            ),
            lastActivityAt: nil,
            lastDeviceName: "This Mac",
            titleCount: 0,
            viewingSessionCount: 0,
            favoriteCount: 0,
            totalWatchSeconds: 0
        )
        let selection = ActiveProfileSelection(profileID: .personal, sourceID: nil)
        let bootstrap = ProfileBootstrap(
            profile: manifest.profile,
            manifest: manifest,
            sources: [],
            selection: selection
        )
        var state = AppFeature.State()
        state.bootstrap = .loading
        let store = TestStore(initialState: state) {
            AppFeature()
        }
        store.exhaustivity = .off

        await store.send(.profile(.internal(.loaded(.success(bootstrap))))) {
            $0.pendingBootstrapSelection = selection
            $0.profile.profile = manifest.profile
            $0.profile.manifest = manifest
            $0.profile.activeProfileID = .personal
        }
        await store.receive(\.source.internal) {
            $0.source.isLoading = true
        }
        await store.receive(\.source.internal) {
            $0.bootstrap = .ready
            $0.pendingBootstrapSelection = nil
            $0.source.isLoading = false
        }

        await store.skipReceivedActions(strict: false)
        #expect(store.state.library.profileID == .personal)
    }

    @Test("Source reconnect preserves the existing Profile binding policy")
    func sourceReconnectPreservesBindingPolicy() async {
        let profileID = ProfileID(rawValue: UUID())
        let sourceID = SourceID(rawValue: UUID())
        var state = AppFeature.State()
        state.profile.activeProfileID = profileID
        state.profile.activeSourceID = sourceID
        state.profile.bindings = [
            ProfileSourceBinding(
                profileID: profileID,
                sourceID: sourceID,
                remoteUserID: "legacy-user",
                mirrorsRemoteState: true
            )
        ]
        let savedBinding = LockIsolated<ProfileSourceBinding?>(nil)
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.profiles.saveBinding = { savedBinding.setValue($0) }
            $0.profiles.setSelection = { _ in }
        }
        store.exhaustivity = .off
        let source = PersistedMediaSource(
            pluginID: "com.samsonlab.cinelark.emby",
            configuration: SourceConfiguration(
                sourceID: sourceID,
                baseURL: URL(string: "https://emby.example.com")!,
                serverIdentity: SourceInstanceIdentity(
                    pluginID: "com.samsonlab.cinelark.emby",
                    serverID: "server"
                ),
                displayName: "Emby",
                remoteUserID: "emby-user"
            )
        )

        await store.send(.source(.delegate(.sourceSaved(source))))
        await store.skipReceivedActions(strict: false)

        #expect(savedBinding.value == ProfileSourceBinding(
            profileID: profileID,
            sourceID: sourceID,
            remoteUserID: "emby-user",
            mirrorsRemoteState: true
        ))
    }
}
