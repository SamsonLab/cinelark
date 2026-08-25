import XCTest
@testable import CineLark

@MainActor
final class RemoteTextInputCoordinatorTests: XCTestCase {
    func testRemoteUpdateAdvancesRevisionAndRejectsStaleWrites() throws {
        let coordinator = RemoteTextInputCoordinator()
        let owner = UUID()
        var appliedText: String?
        coordinator.open(
            owner: owner,
            kind: "search",
            text: "",
            update: { appliedText = $0 },
            commit: {},
            cancel: {}
        )
        let sessionID = try XCTUnwrap(coordinator.snapshot?.sessionID)

        try coordinator.update(sessionID: sessionID, revision: 0, text: "arrival")

        XCTAssertEqual(appliedText, "arrival")
        XCTAssertEqual(coordinator.snapshot?.text, "arrival")
        XCTAssertEqual(coordinator.snapshot?.revision, 1)
        XCTAssertThrowsError(
            try coordinator.update(sessionID: sessionID, revision: 0, text: "stale")
        )
    }

    func testCommitKeepsSearchSessionAvailableAndCancelClosesIt() throws {
        let coordinator = RemoteTextInputCoordinator()
        let owner = UUID()
        var commitCount = 0
        var cancelCount = 0
        coordinator.open(
            owner: owner,
            kind: "search",
            text: "arrival",
            update: { _ in },
            commit: { commitCount += 1 },
            cancel: { cancelCount += 1 }
        )
        let snapshot = try XCTUnwrap(coordinator.snapshot)

        try coordinator.commit(sessionID: snapshot.sessionID, revision: snapshot.revision)

        XCTAssertEqual(commitCount, 1)
        XCTAssertNotNil(coordinator.snapshot)

        try coordinator.cancel(sessionID: snapshot.sessionID, revision: snapshot.revision)

        XCTAssertEqual(cancelCount, 1)
        XCTAssertNil(coordinator.snapshot)
    }
}
