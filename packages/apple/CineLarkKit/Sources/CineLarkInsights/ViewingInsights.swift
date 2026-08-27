import Foundation
import CineLarkDomain
import CineLarkPluginAPI
import CineLarkProfile

public enum ViewingInsightPeriod: String, Codable, CaseIterable, Hashable, Sendable {
    case month
    case quarter
    case year
    case allTime
}

public struct ViewingInsightRange: Codable, Hashable, Sendable {
    public let period: ViewingInsightPeriod
    public let start: Date
    public let end: Date

    public init(period: ViewingInsightPeriod, start: Date, end: Date) {
        self.period = period
        self.start = start
        self.end = end
    }
}

public struct ViewingInsightActivity: Codable, Hashable, Sendable, Identifiable {
    public var id: Date { day }
    public let day: Date
    public let watchedSeconds: Double
    public let sessionCount: Int

    public init(day: Date, watchedSeconds: Double, sessionCount: Int) {
        self.day = day
        self.watchedSeconds = max(watchedSeconds, 0)
        self.sessionCount = max(sessionCount, 0)
    }
}

public struct ViewingInsightTitle: Codable, Hashable, Sendable, Identifiable {
    public var id: ProfileMediaKey { mediaKey }
    public let mediaKey: ProfileMediaKey
    public let locator: MediaLocatorID?
    public let title: String
    public let kind: MediaKind?
    public let artworkURL: URL?
    public let watchedSeconds: Double
    public let sessionCount: Int
    public let completedSessionCount: Int

    public init(
        mediaKey: ProfileMediaKey,
        locator: MediaLocatorID? = nil,
        title: String,
        kind: MediaKind?,
        artworkURL: URL?,
        watchedSeconds: Double,
        sessionCount: Int,
        completedSessionCount: Int
    ) {
        self.mediaKey = mediaKey
        self.locator = locator
        self.title = title
        self.kind = kind
        self.artworkURL = artworkURL
        self.watchedSeconds = max(watchedSeconds, 0)
        self.sessionCount = max(sessionCount, 0)
        self.completedSessionCount = max(completedSessionCount, 0)
    }
}

public struct ViewingInsightDimension: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let watchedSeconds: Double
    public let sessionCount: Int

    public init(id: String, name: String, watchedSeconds: Double, sessionCount: Int) {
        self.id = id
        self.name = name
        self.watchedSeconds = max(watchedSeconds, 0)
        self.sessionCount = max(sessionCount, 0)
    }
}

public struct ViewingInsightsSnapshot: Codable, Hashable, Sendable {
    public let profileID: ProfileID
    public let range: ViewingInsightRange
    public let totalWatchSeconds: Double
    public let sessionCount: Int
    public let completedSessionCount: Int
    public let distinctTitleCount: Int
    public let activeDayCount: Int
    public let longestStreakDays: Int
    public let activity: [ViewingInsightActivity]
    public let topTitles: [ViewingInsightTitle]
    public let topGenres: [ViewingInsightDimension]
    public let topDirectors: [ViewingInsightDimension]
    public let topActors: [ViewingInsightDimension]

    public init(
        profileID: ProfileID,
        range: ViewingInsightRange,
        totalWatchSeconds: Double,
        sessionCount: Int,
        completedSessionCount: Int,
        distinctTitleCount: Int,
        activeDayCount: Int,
        longestStreakDays: Int,
        activity: [ViewingInsightActivity],
        topTitles: [ViewingInsightTitle],
        topGenres: [ViewingInsightDimension],
        topDirectors: [ViewingInsightDimension],
        topActors: [ViewingInsightDimension]
    ) {
        self.profileID = profileID
        self.range = range
        self.totalWatchSeconds = max(totalWatchSeconds, 0)
        self.sessionCount = max(sessionCount, 0)
        self.completedSessionCount = max(completedSessionCount, 0)
        self.distinctTitleCount = max(distinctTitleCount, 0)
        self.activeDayCount = max(activeDayCount, 0)
        self.longestStreakDays = max(longestStreakDays, 0)
        self.activity = activity
        self.topTitles = topTitles
        self.topGenres = topGenres
        self.topDirectors = topDirectors
        self.topActors = topActors
    }
}

public enum ViewingInsightsProjector {
    public static let rankingLimit = 10

    public static func project(
        profileID: ProfileID,
        period: ViewingInsightPeriod,
        containing referenceDate: Date,
        calendar: Calendar,
        sessions: [ViewingSession],
        snapshots: [ProfileMediaKey: ProfileMediaSnapshot]
    ) -> ViewingInsightsSnapshot {
        let range = makeRange(
            period: period,
            containing: referenceDate,
            calendar: calendar,
            sessions: sessions
        )
        let included = sessions.filter { session in
            let activity = session.endedAt ?? session.modifiedAt
            let hasActivity = session.watchedSeconds > 0 || session.status == .completed
            return hasActivity
                && activity >= range.start
                && activity < range.end
                && activity <= referenceDate
        }

        var daily: [Date: ActivityAccumulator] = [:]
        var titles: [ProfileMediaKey: TitleAccumulator] = [:]
        var genres: [String: DimensionAccumulator] = [:]
        var directors: [String: DimensionAccumulator] = [:]
        var actors: [String: DimensionAccumulator] = [:]

        for session in included {
            let watched = max(session.watchedSeconds, 0)
            let activityDate = session.endedAt ?? session.modifiedAt
            let day = calendar.startOfDay(for: activityDate)
            daily[day, default: ActivityAccumulator()].watchedSeconds += watched
            daily[day, default: ActivityAccumulator()].sessionCount += 1

            let snapshot = snapshots[session.mediaKey]
            var title = titles[session.mediaKey] ?? TitleAccumulator(
                mediaKey: session.mediaKey,
                locator: snapshot?.locator,
                title: snapshot?.title ?? session.mediaKey.rawValue,
                kind: snapshot?.kind,
                artworkURL: snapshot?.artworkURL
            )
            title.watchedSeconds += watched
            title.sessionCount += 1
            if session.status == .completed { title.completedSessionCount += 1 }
            titles[session.mediaKey] = title

            guard let metadata = snapshot?.metadata else { continue }
            accumulate(
                metadata.genres.map { (dimensionID(name: $0.name), $0.name) },
                watched: watched,
                into: &genres
            )
            accumulate(
                metadata.directors.map { (personID($0), $0.name) },
                watched: watched,
                into: &directors
            )
            accumulate(
                metadata.cast.map { (personID($0), $0.name) },
                watched: watched,
                into: &actors
            )
        }

        let activity = daily.map { day, value in
            ViewingInsightActivity(
                day: day,
                watchedSeconds: value.watchedSeconds,
                sessionCount: value.sessionCount
            )
        }.sorted { $0.day < $1.day }
        let topTitles = titles.values.map { value in
            ViewingInsightTitle(
                mediaKey: value.mediaKey,
                locator: value.locator,
                title: value.title,
                kind: value.kind,
                artworkURL: value.artworkURL,
                watchedSeconds: value.watchedSeconds,
                sessionCount: value.sessionCount,
                completedSessionCount: value.completedSessionCount
            )
        }.sorted(by: titleRanksBefore).prefix(rankingLimit)

        return ViewingInsightsSnapshot(
            profileID: profileID,
            range: range,
            totalWatchSeconds: included.reduce(0) { $0 + max($1.watchedSeconds, 0) },
            sessionCount: included.count,
            completedSessionCount: included.count { $0.status == .completed },
            distinctTitleCount: Set(included.map(\.mediaKey)).count,
            activeDayCount: activity.count,
            longestStreakDays: longestStreak(in: activity.map(\.day), calendar: calendar),
            activity: activity,
            topTitles: Array(topTitles),
            topGenres: rankedDimensions(genres),
            topDirectors: rankedDimensions(directors),
            topActors: rankedDimensions(actors)
        )
    }

    private struct ActivityAccumulator {
        var watchedSeconds: Double = 0
        var sessionCount = 0
    }

    private struct TitleAccumulator {
        let mediaKey: ProfileMediaKey
        let locator: MediaLocatorID?
        let title: String
        let kind: MediaKind?
        let artworkURL: URL?
        var watchedSeconds: Double = 0
        var sessionCount = 0
        var completedSessionCount = 0
    }

    private struct DimensionAccumulator {
        var name: String
        var watchedSeconds: Double = 0
        var sessionCount = 0
    }

    private static func makeRange(
        period: ViewingInsightPeriod,
        containing referenceDate: Date,
        calendar: Calendar,
        sessions: [ViewingSession]
    ) -> ViewingInsightRange {
        switch period {
        case .month:
            let interval = calendar.dateInterval(of: .month, for: referenceDate)
            return ViewingInsightRange(
                period: period,
                start: interval?.start ?? calendar.startOfDay(for: referenceDate),
                end: interval?.end ?? referenceDate
            )
        case .quarter:
            let components = calendar.dateComponents([.era, .year, .month], from: referenceDate)
            let month = components.month ?? 1
            let quarterMonth = ((month - 1) / 3) * 3 + 1
            var startComponents = DateComponents()
            startComponents.calendar = calendar
            startComponents.timeZone = calendar.timeZone
            startComponents.era = components.era
            startComponents.year = components.year
            startComponents.month = quarterMonth
            startComponents.day = 1
            let start = calendar.date(from: startComponents)
                ?? calendar.startOfDay(for: referenceDate)
            let end = calendar.date(byAdding: .month, value: 3, to: start) ?? referenceDate
            return ViewingInsightRange(period: period, start: start, end: end)
        case .year:
            let interval = calendar.dateInterval(of: .year, for: referenceDate)
            return ViewingInsightRange(
                period: period,
                start: interval?.start ?? calendar.startOfDay(for: referenceDate),
                end: interval?.end ?? referenceDate
            )
        case .allTime:
            let referenceDay = calendar.startOfDay(for: referenceDate)
            let earliest = sessions.map { $0.endedAt ?? $0.modifiedAt }.min()
            let earliestDay = earliest.map(calendar.startOfDay(for:)) ?? referenceDay
            let start = min(earliestDay, referenceDay)
            let end = calendar.date(byAdding: .day, value: 1, to: referenceDay)
                ?? referenceDate.addingTimeInterval(86_400)
            return ViewingInsightRange(period: period, start: start, end: end)
        }
    }

    private static func accumulate(
        _ values: [(id: String, name: String)],
        watched: Double,
        into accumulators: inout [String: DimensionAccumulator]
    ) {
        var seen = Set<String>()
        for value in values where !value.id.isEmpty && seen.insert(value.id).inserted {
            var accumulator = accumulators[value.id]
                ?? DimensionAccumulator(name: value.name)
            if value.name < accumulator.name { accumulator.name = value.name }
            accumulator.watchedSeconds += watched
            accumulator.sessionCount += 1
            accumulators[value.id] = accumulator
        }
    }

    private static func rankedDimensions(
        _ values: [String: DimensionAccumulator]
    ) -> [ViewingInsightDimension] {
        values.map { id, value in
            ViewingInsightDimension(
                id: id,
                name: value.name,
                watchedSeconds: value.watchedSeconds,
                sessionCount: value.sessionCount
            )
        }.sorted {
            if $0.watchedSeconds != $1.watchedSeconds {
                return $0.watchedSeconds > $1.watchedSeconds
            }
            if $0.sessionCount != $1.sessionCount {
                return $0.sessionCount > $1.sessionCount
            }
            return $0.name < $1.name
        }.prefix(rankingLimit).map { $0 }
    }

    private static func titleRanksBefore(
        _ lhs: ViewingInsightTitle,
        _ rhs: ViewingInsightTitle
    ) -> Bool {
        if lhs.watchedSeconds != rhs.watchedSeconds {
            return lhs.watchedSeconds > rhs.watchedSeconds
        }
        if lhs.sessionCount != rhs.sessionCount {
            return lhs.sessionCount > rhs.sessionCount
        }
        return lhs.title < rhs.title
    }

    private static func longestStreak(in days: [Date], calendar: Calendar) -> Int {
        guard !days.isEmpty else { return 0 }
        var longest = 1
        var current = 1
        for index in 1..<days.count {
            if calendar.dateComponents([.day], from: days[index - 1], to: days[index]).day == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }

    private static func personID(_ value: ProfilePersonSnapshot) -> String {
        if let tmdbID = value.tmdbID, !tmdbID.isEmpty { return "tmdb:\(tmdbID)" }
        if let imdbID = value.imdbID, !imdbID.isEmpty { return "imdb:\(imdbID)" }
        return dimensionID(name: value.name)
    }

    private static func dimensionID(name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct ViewingInsightsService: Sendable {
    private let repository: any ProfileRepository

    public init(repository: any ProfileRepository) {
        self.repository = repository
    }

    public func snapshot(
        profileID: ProfileID,
        period: ViewingInsightPeriod,
        containing referenceDate: Date,
        calendar: Calendar
    ) async throws -> ViewingInsightsSnapshot {
        let sessions = try await repository.viewingSessions(profileID: profileID)
        let keys = Set(sessions.map(\.mediaKey))
        let values = try await repository.mediaSnapshots(keys: keys)
        let snapshots = Dictionary(uniqueKeysWithValues: values.map { ($0.key, $0) })
        return ViewingInsightsProjector.project(
            profileID: profileID,
            period: period,
            containing: referenceDate,
            calendar: calendar,
            sessions: sessions,
            snapshots: snapshots
        )
    }
}
