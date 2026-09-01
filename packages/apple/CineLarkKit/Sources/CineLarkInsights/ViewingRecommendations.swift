import Foundation
import CineLarkDomain
import CineLarkPluginAPI
import CineLarkProfile

public enum ViewingRecommendationReason: Codable, Hashable, Sendable {
    case matchingGenre(String)
}

public struct ViewingRecommendation: Codable, Hashable, Sendable, Identifiable {
    public var id: MediaLocatorID { locator }
    public let locator: MediaLocatorID
    public let summary: MediaSummary
    public let score: Double
    public let reasons: [ViewingRecommendationReason]

    public init(
        locator: MediaLocatorID,
        summary: MediaSummary,
        score: Double,
        reasons: [ViewingRecommendationReason]
    ) {
        self.locator = locator
        self.summary = summary
        self.score = max(score, 0)
        self.reasons = reasons
    }
}

public struct ViewingRecommendationWeights: Equatable, Sendable {
    public var watchHourWeight: Double
    public var maximumWatchHoursPerSession: Double
    public var completionWeight: Double
    public var favoriteWeight: Double
    public var sessionHalfLifeDays: Double
    public var secondaryGenreWeight: Double
    public var maximumMatchedGenres: Int

    public init(
        watchHourWeight: Double = 1,
        maximumWatchHoursPerSession: Double = 2,
        completionWeight: Double = 1.5,
        favoriteWeight: Double = 2.5,
        sessionHalfLifeDays: Double = 180,
        secondaryGenreWeight: Double = 0.35,
        maximumMatchedGenres: Int = 3
    ) {
        self.watchHourWeight = max(watchHourWeight, 0)
        self.maximumWatchHoursPerSession = max(maximumWatchHoursPerSession, 0)
        self.completionWeight = max(completionWeight, 0)
        self.favoriteWeight = max(favoriteWeight, 0)
        self.sessionHalfLifeDays = max(sessionHalfLifeDays, 1)
        self.secondaryGenreWeight = max(secondaryGenreWeight, 0)
        self.maximumMatchedGenres = max(maximumMatchedGenres, 1)
    }

    public static let `default` = Self()
}

public enum ViewingRecommendationProjector {
    public static let defaultLimit = 12

    public static func project(
        sessions: [ViewingSession],
        favorites: [ProfileFavoriteState],
        snapshots: [ProfileMediaKey: ProfileMediaSnapshot],
        candidates: [LocatedMediaItem],
        referenceDate: Date,
        limit: Int = defaultLimit,
        weights: ViewingRecommendationWeights = .default
    ) -> [ViewingRecommendation] {
        guard limit > 0 else { return [] }
        let includedSessions = sessions.filter { session in
            let activityDate = session.endedAt ?? session.modifiedAt
            return activityDate <= referenceDate
                && (session.watchedSeconds > 0 || session.status == .completed)
        }
        let viewedKeys = Set(includedSessions.map(\.mediaKey))
        let activeFavorites = favorites.filter {
            $0.isFavorite && $0.modifiedAt <= referenceDate
        }
        let engagedKeys = viewedKeys.union(activeFavorites.map(\.mediaKey))
        var affinities: [String: Affinity] = [:]

        for session in includedSessions {
            guard let metadata = snapshots[session.mediaKey]?.metadata else { continue }
            let watchedHours = min(
                max(session.watchedSeconds / 3_600, 0),
                weights.maximumWatchHoursPerSession
            )
            let durationWeight = watchedHours * weights.watchHourWeight
            let completionWeight = session.status == .completed
                ? weights.completionWeight
                : 0
            let activityDate = session.endedAt ?? session.modifiedAt
            let age = max(referenceDate.timeIntervalSince(activityDate), 0)
            let halfLife = weights.sessionHalfLifeDays * 86_400
            let recencyWeight = pow(0.5, age / halfLife)
            add(
                metadata.genres.map(\.name),
                weight: (durationWeight + completionWeight) * recencyWeight,
                to: &affinities
            )
        }
        for favorite in activeFavorites {
            guard let metadata = snapshots[favorite.mediaKey]?.metadata else { continue }
            add(
                metadata.genres.map(\.name),
                weight: weights.favoriteWeight,
                to: &affinities
            )
        }

        let values = candidates.compactMap { candidate -> ViewingRecommendation? in
            guard candidate.summary.kind == .movie || candidate.summary.kind == .series else {
                return nil
            }
            let mediaKey = ProfileMediaKey(locator: candidate.locator)
            guard !engagedKeys.contains(mediaKey) else { return nil }
            let matches = uniqueGenres(candidate.summary.genres.map(\.name)).compactMap { genre in
                affinities[genre.id].map { (name: genre.name, weight: $0.weight) }
            }.sorted {
                if $0.weight != $1.weight { return $0.weight > $1.weight }
                return $0.name < $1.name
            }
            guard let strongest = matches.first else { return nil }
            let secondary = matches
                .dropFirst()
                .prefix(weights.maximumMatchedGenres - 1)
                .reduce(0) { $0 + $1.weight * weights.secondaryGenreWeight }
            let score = strongest.weight + secondary
            guard score > 0 else { return nil }
            return ViewingRecommendation(
                locator: candidate.locator,
                summary: candidate.summary
                    .replacingID(candidate.locator.providerItemID)
                    .replacingUserState(.empty),
                score: score,
                reasons: matches.prefix(2).map { .matchingGenre($0.name) }
            )
        }

        var unique: [MediaLocatorID: ViewingRecommendation] = [:]
        for value in values {
            if let existing = unique[value.locator], ranksBefore(existing, value) {
                continue
            }
            unique[value.locator] = value
        }
        return unique.values.sorted(by: ranksBefore).prefix(limit).map { $0 }
    }

    private struct Affinity {
        var name: String
        var weight: Double
    }

    private static func add(
        _ names: [String],
        weight: Double,
        to affinities: inout [String: Affinity]
    ) {
        for genre in uniqueGenres(names) {
            var value = affinities[genre.id] ?? Affinity(name: genre.name, weight: 0)
            if genre.name < value.name {
                value.name = genre.name
            }
            value.weight += weight
            affinities[genre.id] = value
        }
    }

    private static func uniqueGenres(
        _ names: [String]
    ) -> [(id: String, name: String)] {
        var values: [String: String] = [:]
        let locale = Locale(identifier: "en_US_POSIX")
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = trimmed.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: locale
            ).lowercased(with: locale)
            guard !id.isEmpty else { continue }
            if let existing = values[id], existing <= trimmed {
                continue
            }
            values[id] = trimmed
        }
        return values.map { (id: $0.key, name: $0.value) }
    }

    private static func ranksBefore(
        _ lhs: ViewingRecommendation,
        _ rhs: ViewingRecommendation
    ) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        let lhsRating = lhs.summary.rating ?? 0
        let rhsRating = rhs.summary.rating ?? 0
        if lhsRating != rhsRating { return lhsRating > rhsRating }
        if lhs.summary.title != rhs.summary.title {
            return lhs.summary.title < rhs.summary.title
        }
        return locatorIdentity(lhs.locator) < locatorIdentity(rhs.locator)
    }

    private static func locatorIdentity(_ locator: MediaLocatorID) -> String {
        "\(locator.sourceID.rawValue.uuidString):\(locator.providerItemID)"
    }
}
