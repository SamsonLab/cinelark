import XCTest
@testable import CineLark

@MainActor
final class RemotePanelDismissalRegistryTests: XCTestCase {
    func testDismissesRegisteredPresentationOnce() {
        let registry = RemotePanelDismissalRegistry()
        var dismissalCount = 0

        registry.register(id: UUID()) {
            dismissalCount += 1
        }

        XCTAssertTrue(registry.dismissIfPresented())
        XCTAssertEqual(dismissalCount, 1)
        XCTAssertFalse(registry.dismissIfPresented())
    }

    func testStaleUnregisterDoesNotRemoveCurrentPresentation() {
        let registry = RemotePanelDismissalRegistry()
        let staleID = UUID()
        let currentID = UUID()
        var dismissed = false

        registry.register(id: staleID) {}
        registry.register(id: currentID) {
            dismissed = true
        }
        registry.unregister(id: staleID)

        XCTAssertTrue(registry.dismissIfPresented())
        XCTAssertTrue(dismissed)
    }
}
