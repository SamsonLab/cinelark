import ComposableArchitecture
import Foundation
import Testing
import CineLarkInsights
import CineLarkPluginAPI
import CineLarkProfile

@testable import CineLark

@MainActor
struct InsightsFeatureTests {
    @Test("Appearing loads the active Profile range")
    func initialLoad() async {
        let profileID = ProfileID(rawValue: UUID())
        let sourceID = SourceID(rawValue: UUID())
        let requestID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = insightSnapshot(profileID: profileID, period: .month, date: now)
        let store = TestStore(initialState: InsightsFeature.State(
            activeProfileID: profileID,
            activeSourceID: sourceID
        )) {
            InsightsFeature()
        } withDependencies: {
            $0.date.now = now
            $0.uuid = .constant(requestID)
            $0.insights.load = { loadedProfileID, loadedSourceID, period, referenceDate in
                #expect(loadedProfileID == profileID)
                #expect(loadedSourceID == sourceID)
                #expect(period == .month)
                #expect(referenceDate == now)
                return snapshot
            }
        }

        await store.send(.view(.appeared)) {
            $0.isPresented = true
            $0.isLoading = true
            $0.requestID = requestID
        }
        await store.receive(.internal(.loaded(
            requestID: requestID,
            profileID: profileID,
            sourceID: sourceID,
            period: .month,
            .success(snapshot)
        ))) {
            $0.isLoading = false
            $0.requestID = nil
            $0.snapshot = snapshot
        }
    }

    @Test("Stale Profile and period responses cannot replace current insights")
    func staleResponsesAreIgnored() async {
        let profileID = ProfileID(rawValue: UUID())
        let otherProfileID = ProfileID(rawValue: UUID())
        let sourceID = SourceID(rawValue: UUID())
        let otherSourceID = SourceID(rawValue: UUID())
        let requestID = UUID()
        let staleID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expected = insightSnapshot(profileID: profileID, period: .year, date: now)
        var state = InsightsFeature.State(
            activeProfileID: profileID,
            activeSourceID: sourceID,
            selectedPeriod: .year,
            requestID: requestID,
            isPresented: true,
            isLoading: true
        )
        state.snapshot = insightSnapshot(profileID: profileID, period: .month, date: now)
        let store = TestStore(initialState: state) {
            InsightsFeature()
        }

        await store.send(.internal(.loaded(
            requestID: staleID,
            profileID: profileID,
            sourceID: sourceID,
            period: .year,
            .success(expected)
        )))
        await store.send(.internal(.loaded(
            requestID: requestID,
            profileID: otherProfileID,
            sourceID: sourceID,
            period: .year,
            .success(expected)
        )))
        await store.send(.internal(.loaded(
            requestID: requestID,
            profileID: profileID,
            sourceID: otherSourceID,
            period: .year,
            .success(expected)
        )))
        await store.send(.internal(.loaded(
            requestID: requestID,
            profileID: profileID,
            sourceID: sourceID,
            period: .month,
            .success(expected)
        )))
        await store.send(.internal(.loaded(
            requestID: requestID,
            profileID: profileID,
            sourceID: sourceID,
            period: .year,
            .success(expected)
        ))) {
            $0.isLoading = false
            $0.requestID = nil
            $0.snapshot = expected
        }
    }

    @Test("Changing period reloads with a new query identity")
    func periodSelectionReloads() async {
        let profileID = ProfileID(rawValue: UUID())
        let sourceID = SourceID(rawValue: UUID())
        let firstRequestID = UUID()
        let secondRequestID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let month = insightSnapshot(profileID: profileID, period: .month, date: now)
        let quarter = insightSnapshot(profileID: profileID, period: .quarter, date: now)
        let requests = LockIsolated<[ViewingInsightPeriod]>([])
        let store = TestStore(initialState: InsightsFeature.State(
            activeProfileID: profileID,
            activeSourceID: sourceID
        )) {
            InsightsFeature()
        } withDependencies: {
            $0.date.now = now
            $0.uuid = .init { requests.value.isEmpty ? firstRequestID : secondRequestID }
            $0.insights.load = { _, loadedSourceID, period, _ in
                #expect(loadedSourceID == sourceID)
                requests.withValue { $0.append(period) }
                return period == .month ? month : quarter
            }
        }

        await store.send(.view(.appeared)) {
            $0.isPresented = true
            $0.isLoading = true
            $0.requestID = firstRequestID
        }
        await store.receive(.internal(.loaded(
            requestID: firstRequestID,
            profileID: profileID,
            sourceID: sourceID,
            period: .month,
            .success(month)
        ))) {
            $0.isLoading = false
            $0.requestID = nil
            $0.snapshot = month
        }
        await store.send(.view(.periodSelected(.quarter))) {
            $0.selectedPeriod = .quarter
            $0.isLoading = true
            $0.requestID = secondRequestID
        }
        await store.receive(.internal(.loaded(
            requestID: secondRequestID,
            profileID: profileID,
            sourceID: sourceID,
            period: .quarter,
            .success(quarter)
        ))) {
            $0.isLoading = false
            $0.requestID = nil
            $0.snapshot = quarter
        }

        #expect(requests.value == [.month, .quarter])
    }

    @Test("Changing Profile clears the old projection and reloads while visible")
    func profileChangeReloads() async {
        let firstProfileID = ProfileID(rawValue: UUID())
        let secondProfileID = ProfileID(rawValue: UUID())
        let sourceID = SourceID(rawValue: UUID())
        let requestID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let oldSnapshot = insightSnapshot(
            profileID: firstProfileID,
            period: .month,
            date: now
        )
        let newSnapshot = insightSnapshot(
            profileID: secondProfileID,
            period: .month,
            date: now
        )
        let store = TestStore(initialState: InsightsFeature.State(
            activeProfileID: firstProfileID,
            activeSourceID: sourceID,
            snapshot: oldSnapshot,
            isPresented: true
        )) {
            InsightsFeature()
        } withDependencies: {
            $0.date.now = now
            $0.uuid = .constant(requestID)
            $0.insights.load = { profileID, loadedSourceID, _, _ in
                #expect(profileID == secondProfileID)
                #expect(loadedSourceID == sourceID)
                return newSnapshot
            }
        }

        await store.send(.view(.contextChanged(
            profileID: secondProfileID,
            sourceID: sourceID
        ))) {
            $0.activeProfileID = secondProfileID
            $0.snapshot = nil
            $0.isLoading = true
            $0.requestID = requestID
        }
        await store.receive(.internal(.loaded(
            requestID: requestID,
            profileID: secondProfileID,
            sourceID: sourceID,
            period: .month,
            .success(newSnapshot)
        ))) {
            $0.isLoading = false
            $0.requestID = nil
            $0.snapshot = newSnapshot
        }
    }

    @Test("Changing Source invalidates an in-flight recommendation projection")
    func sourceChangeReloads() async {
        let profileID = ProfileID(rawValue: UUID())
        let firstSourceID = SourceID(rawValue: UUID())
        let secondSourceID = SourceID(rawValue: UUID())
        let requestID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let oldSnapshot = insightSnapshot(profileID: profileID, period: .month, date: now)
        let newSnapshot = insightSnapshot(profileID: profileID, period: .month, date: now)
        let store = TestStore(initialState: InsightsFeature.State(
            activeProfileID: profileID,
            activeSourceID: firstSourceID,
            snapshot: oldSnapshot,
            isPresented: true
        )) {
            InsightsFeature()
        } withDependencies: {
            $0.date.now = now
            $0.uuid = .constant(requestID)
            $0.insights.load = { loadedProfileID, sourceID, _, _ in
                #expect(loadedProfileID == profileID)
                #expect(sourceID == secondSourceID)
                return newSnapshot
            }
        }

        await store.send(.view(.contextChanged(
            profileID: profileID,
            sourceID: secondSourceID
        ))) {
            $0.activeSourceID = secondSourceID
            $0.snapshot = nil
            $0.isLoading = true
            $0.requestID = requestID
        }
        await store.receive(.internal(.loaded(
            requestID: requestID,
            profileID: profileID,
            sourceID: secondSourceID,
            period: .month,
            .success(newSnapshot)
        ))) {
            $0.isLoading = false
            $0.requestID = nil
            $0.snapshot = newSnapshot
        }
    }
}

private func insightSnapshot(
    profileID: ProfileID,
    period: ViewingInsightPeriod,
    date: Date
) -> ViewingInsightsSnapshot {
    ViewingInsightsSnapshot(
        profileID: profileID,
        range: ViewingInsightRange(
            period: period,
            start: date.addingTimeInterval(-86_400),
            end: date.addingTimeInterval(86_400)
        ),
        totalWatchSeconds: 120,
        sessionCount: 1,
        completedSessionCount: 1,
        distinctTitleCount: 1,
        activeDayCount: 1,
        longestStreakDays: 1,
        activity: [],
        topTitles: [],
        topGenres: [],
        topDirectors: [],
        topActors: []
    )
}
