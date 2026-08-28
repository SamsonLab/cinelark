import ComposableArchitecture
import Foundation
import CineLarkInsights
import CineLarkPluginAPI
import CineLarkProfile

enum InsightsClientFailure: Error, Equatable, Sendable {
    case unavailable(String)
}

struct InsightsClient: Sendable {
    var load: @Sendable (
        _ profileID: ProfileID,
        _ sourceID: SourceID?,
        _ period: ViewingInsightPeriod,
        _ referenceDate: Date
    ) async throws -> ViewingInsightsSnapshot
}

extension InsightsClient: DependencyKey {
    static let liveValue = Self(
        load: { _, _, _, _ in
            throw InsightsClientFailure.unavailable("Viewing insights are not configured")
        }
    )

    static let testValue = liveValue
}

extension DependencyValues {
    var insights: InsightsClient {
        get { self[InsightsClient.self] }
        set { self[InsightsClient.self] = newValue }
    }
}

extension InsightsClient {
    static func live(
        service: ViewingInsightsService,
        calendar: @escaping @Sendable () -> Calendar = { .autoupdatingCurrent }
    ) -> Self {
        Self(
            load: { profileID, sourceID, period, referenceDate in
                try await service.snapshot(
                    profileID: profileID,
                    sourceID: sourceID,
                    period: period,
                    containing: referenceDate,
                    calendar: calendar()
                )
            }
        )
    }
}
