import ComposableArchitecture
import Foundation
import Testing
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
        let refreshes = LockIsolated(0)
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
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
        }
        store.exhaustivity = .off

        await store.send(.profile(.internal(.repositoryChanged(.external))))
        await store.skipReceivedActions(strict: false)

        #expect(refreshes.value == 1)
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

        await store.send(.source(.internal(.sourcesRestored([sourceID], nil)))) {
            $0.pendingBootstrapSelection = nil
            $0.source.isLoading = false
            $0.source.installedSourceIDs = [sourceID]
        }
        await store.skipReceivedActions(strict: false)

        #expect(store.state.library.profileID == profileID)
        #expect(store.state.library.sourceID == sourceID)
        #expect(store.state.search.sourceID == sourceID)
        #expect(store.state.playback.profileID == profileID)
        #expect(store.state.navigation.activeProfileID == profileID)
        #expect(store.state.navigation.activeSourceID == sourceID)
    }
}
