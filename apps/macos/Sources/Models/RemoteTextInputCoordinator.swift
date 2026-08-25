import Foundation
import Observation

@Observable
@MainActor
final class RemoteTextInputCoordinator {
    struct Snapshot: Equatable {
        let sessionID: UUID
        let kind: String
        let text: String
        let maximumLength: Int
        let revision: UInt64
    }

    enum UpdateError: Error {
        case staleSession
        case staleRevision
        case invalidText
    }

    private(set) var snapshot: Snapshot?
    var onSnapshotChanged: (@MainActor @Sendable () -> Void)?

    @ObservationIgnored private var owner: UUID?
    @ObservationIgnored private var updateAction: ((String) -> Void)?
    @ObservationIgnored private var commitAction: (() -> Void)?
    @ObservationIgnored private var cancelAction: (() -> Void)?

    func open(
        owner: UUID,
        kind: String,
        text: String,
        maximumLength: Int = 512,
        update: @escaping (String) -> Void,
        commit: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        self.owner = owner
        updateAction = update
        commitAction = commit
        cancelAction = cancel
        snapshot = Snapshot(
            sessionID: UUID(),
            kind: kind,
            text: String(text.prefix(maximumLength)),
            maximumLength: maximumLength,
            revision: 0
        )
        onSnapshotChanged?()
    }

    func close(owner: UUID) {
        guard self.owner == owner else { return }
        close()
    }

    func localTextChanged(_ text: String, owner: UUID) {
        guard self.owner == owner, let snapshot else { return }
        let bounded = String(text.prefix(snapshot.maximumLength))
        guard bounded != snapshot.text else { return }
        self.snapshot = Snapshot(
            sessionID: snapshot.sessionID,
            kind: snapshot.kind,
            text: bounded,
            maximumLength: snapshot.maximumLength,
            revision: snapshot.revision &+ 1
        )
        onSnapshotChanged?()
    }

    func update(sessionID: UUID, revision: UInt64, text: String) throws {
        guard let snapshot, snapshot.sessionID == sessionID else {
            throw UpdateError.staleSession
        }
        guard snapshot.revision == revision else {
            throw UpdateError.staleRevision
        }
        guard text.count <= snapshot.maximumLength else {
            throw UpdateError.invalidText
        }
        updateAction?(text)
        self.snapshot = Snapshot(
            sessionID: snapshot.sessionID,
            kind: snapshot.kind,
            text: text,
            maximumLength: snapshot.maximumLength,
            revision: snapshot.revision &+ 1
        )
        onSnapshotChanged?()
    }

    func commit(sessionID: UUID, revision: UInt64) throws {
        try validate(sessionID: sessionID, revision: revision)
        commitAction?()
    }

    func cancel(sessionID: UUID, revision: UInt64) throws {
        try validate(sessionID: sessionID, revision: revision)
        let action = cancelAction
        close()
        action?()
    }

    private func validate(sessionID: UUID, revision: UInt64) throws {
        guard let snapshot, snapshot.sessionID == sessionID else {
            throw UpdateError.staleSession
        }
        guard snapshot.revision == revision else {
            throw UpdateError.staleRevision
        }
    }

    private func close() {
        owner = nil
        updateAction = nil
        commitAction = nil
        cancelAction = nil
        snapshot = nil
        onSnapshotChanged?()
    }
}
