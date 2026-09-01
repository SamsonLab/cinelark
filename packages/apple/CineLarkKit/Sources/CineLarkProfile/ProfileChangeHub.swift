@preconcurrency import CloudKit
@preconcurrency import CoreData
import Foundation

final class PersistentStoreLoadResult: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var error: Error?

    func record(_ error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        self.error = self.error ?? error
    }
}

struct ProfileCloudTransportSnapshot: Sendable {
    var activeOperations: Set<ProfileCloudSyncOperation> = []
    var lastSuccessfulAt: Date?
    var lastCompletedAt: Date?
    var failureDescription: String?

    mutating func recordCompletion(_ event: NSPersistentCloudKitContainer.Event) {
        guard let completedAt = event.endDate else { return }
        if event.succeeded,
           lastSuccessfulAt.map({ completedAt > $0 }) ?? true {
            lastSuccessfulAt = completedAt
        }
        if lastCompletedAt.map({ completedAt > $0 }) ?? true {
            lastCompletedAt = completedAt
            failureDescription = event.succeeded
                ? nil
                : Self.normalizedFailure(event.error)
        }
    }

    mutating func merge(_ other: Self) {
        activeOperations.formUnion(other.activeOperations)
        if let otherSuccess = other.lastSuccessfulAt,
           lastSuccessfulAt.map({ otherSuccess > $0 }) ?? true {
            lastSuccessfulAt = otherSuccess
        }
        if let otherCompletion = other.lastCompletedAt,
           lastCompletedAt.map({ otherCompletion > $0 }) ?? true {
            lastCompletedAt = otherCompletion
            failureDescription = other.failureDescription
        }
    }

    static func operation(
        for type: NSPersistentCloudKitContainer.EventType
    ) -> ProfileCloudSyncOperation {
        switch type {
        case .setup:
            return .setup
        case .import:
            return .importing
        case .export:
            return .exporting
        @unknown default:
            return .setup
        }
    }

    private static func normalizedFailure(_ error: Error?) -> String {
        guard let cloudError = error as? CKError else {
            return "iCloud synchronization failed. CineLark will retry automatically."
        }
        switch cloudError.code {
        case .notAuthenticated:
            return "Sign in to iCloud in System Settings to sync Profiles."
        case .quotaExceeded:
            return "iCloud storage is full. Free space to resume Profile sync."
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .requestRateLimited, .zoneBusy:
            return "iCloud is temporarily unavailable. CineLark will retry automatically."
        default:
            return "iCloud synchronization failed. CineLark will retry automatically."
        }
    }
}

final class ProfileChangeHub: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<ProfileRepositoryChange>.Continuation] = [:]
    private var observers: [NSObjectProtocol] = []
    private var activeCloudEvents: [UUID: ProfileCloudSyncOperation] = [:]
    private var cloudTransport = ProfileCloudTransportSnapshot()

    init(
        container: NSPersistentCloudKitContainer,
        coordinator: NSPersistentStoreCoordinator
    ) {
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: coordinator,
            queue: nil
        ) { [weak self] _ in
            self?.yield(.external)
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: nil
        ) { [weak self] notification in
            guard
                let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event
            else { return }
            let completedInitialImport = self?.record(event) ?? false
            self?.yield(.cloudSyncStatus)
            if completedInitialImport {
                self?.yield(.bootstrap)
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.yield(.bootstrap)
        })
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func stream() -> AsyncStream<ProfileRepositoryChange> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.remove(id)
            }
        }
    }

    func cloudTransportSnapshot() -> ProfileCloudTransportSnapshot {
        lock.lock()
        defer { lock.unlock() }
        var snapshot = cloudTransport
        snapshot.activeOperations = Set(activeCloudEvents.values)
        return snapshot
    }

    func yield(_ change: ProfileRepositoryChange) {
        lock.lock()
        let current = Array(continuations.values)
        lock.unlock()
        for continuation in current {
            continuation.yield(change)
        }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        continuations[id] = nil
        lock.unlock()
    }

    private func record(_ event: NSPersistentCloudKitContainer.Event) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if event.endDate == nil {
            activeCloudEvents[event.identifier] = ProfileCloudTransportSnapshot.operation(
                for: event.type
            )
            return false
        }
        activeCloudEvents[event.identifier] = nil
        cloudTransport.recordCompletion(event)
        return event.type == .import && event.succeeded
    }
}
