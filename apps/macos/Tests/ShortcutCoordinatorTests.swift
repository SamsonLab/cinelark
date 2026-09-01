import XCTest
@testable import CineLark

@MainActor
final class ShortcutCoordinatorTests: XCTestCase {
    func testRouteSurfaceOutranksPageRegisteredLater() {
        let coordinator = ShortcutCoordinator()
        var receivedDirections: [String] = []

        coordinator.setNavigationSurface(
            owner: UUID(),
            level: .route,
            move: { _ in
                receivedDirections.append("route")
                return true
            },
            activate: { true }
        )
        coordinator.setNavigationSurface(
            owner: UUID(),
            level: .page,
            move: { _ in
                receivedDirections.append("page")
                return true
            },
            activate: { true }
        )

        XCTAssertTrue(coordinator.moveFocus(.down))
        XCTAssertEqual(receivedDirections, ["route"])
    }

    func testRemovingRouteSurfaceRestoresLatestPageSurface() {
        let coordinator = ShortcutCoordinator()
        let routeOwner = UUID()
        var receivedDirections: [String] = []

        coordinator.setNavigationSurface(
            owner: UUID(),
            level: .page,
            move: { _ in
                receivedDirections.append("page")
                return true
            },
            activate: { true }
        )
        coordinator.setNavigationSurface(
            owner: routeOwner,
            level: .route,
            move: { _ in
                receivedDirections.append("route")
                return true
            },
            activate: { true }
        )

        coordinator.removeNavigationSurface(owner: routeOwner)

        XCTAssertTrue(coordinator.moveFocus(.down))
        XCTAssertEqual(receivedDirections, ["page"])
    }

    func testModalSurfaceOutranksRouteRegisteredLater() {
        let coordinator = ShortcutCoordinator()
        var receivedDirections: [String] = []

        coordinator.setNavigationSurface(
            owner: UUID(),
            level: .modal,
            handlesPresentedModal: true,
            move: { _ in
                receivedDirections.append("modal")
                return true
            },
            activate: { true }
        )
        coordinator.setNavigationSurface(
            owner: UUID(),
            level: .route,
            move: { _ in
                receivedDirections.append("route")
                return true
            },
            activate: { true }
        )

        XCTAssertTrue(coordinator.moveFocus(.down))
        XCTAssertEqual(receivedDirections, ["modal"])
    }

    func testKeyboardNavigationKeepsTemporarilyOffscreenOrigin() {
        XCTAssertEqual(
            CineLarkNavigationOriginPolicy.resolve(
                candidate: "episode.2",
                isCandidateVisible: false,
                rebasesOffscreenCandidate: false,
                orderedVisibleCandidates: ["episode.1"],
                direction: .down
            ),
            "episode.2"
        )
    }

    func testPointerHandoffRejectsOffscreenOrigin() {
        XCTAssertEqual(
            CineLarkNavigationOriginPolicy.resolve(
                candidate: "episode.2",
                isCandidateVisible: false,
                rebasesOffscreenCandidate: true,
                orderedVisibleCandidates: ["episode.1"],
                direction: .down
            ),
            "episode.1"
        )
    }
}
