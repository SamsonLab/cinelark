import ComposableArchitecture
import Testing

@testable import CineLark

private actor CacheRecorder {
    var isCleared = false

    func usage() -> CacheUsage {
        isCleared
            ? .zero
            : CacheUsage(metadataBytes: 1_024, artworkBytes: 2_048)
    }

    func clear() {
        isCleared = true
    }
}

@MainActor
struct CacheFeatureTests {
    @Test("Confirmed cache clearing preserves UI state until completion and reloads usage")
    func clearAndReload() async {
        let recorder = CacheRecorder()
        let populated = CacheUsage(metadataBytes: 1_024, artworkBytes: 2_048)
        let store = TestStore(initialState: CacheFeature.State()) {
            CacheFeature()
        } withDependencies: {
            $0.cache = CacheClient(
                usage: { await recorder.usage() },
                clearAll: { await recorder.clear() }
            )
        }

        await store.send(.view(.appeared)) {
            $0.isLoading = true
        }
        await store.receive(.internal(.usageLoaded(.success(populated)))) {
            $0.isLoading = false
            $0.usage = populated
        }
        await store.send(.view(.clearButtonTapped)) {
            $0.showsClearConfirmation = true
        }
        await store.send(.view(.clearConfirmed)) {
            $0.showsClearConfirmation = false
            $0.isClearing = true
        }
        await store.receive(.delegate(.willClear))
        await store.receive(.internal(.clearFinished(.success))) {
            $0.isClearing = false
            $0.usage = .zero
        }
        await store.receive(.delegate(.didClear))
        await store.receive(.view(.refresh)) {
            $0.isLoading = true
        }
        await store.receive(.internal(.usageLoaded(.success(.zero)))) {
            $0.isLoading = false
        }
    }
}
