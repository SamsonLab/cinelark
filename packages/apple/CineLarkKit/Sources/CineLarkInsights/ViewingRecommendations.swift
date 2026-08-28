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

public enum ViewingRecommendationProjector {
    public static let defaultLimit = 12

    public static func project(
        sessions: [ViewingSession],
        favorites: [ProfileFavoriteState],
        snapshots: [ProfileMediaKey: ProfileMediaSnapshot],
        candidates: [LocatedMediaItem],
        referenceDate: Date,
        limit: Int = defaultLimit
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
            let durationWeight = max(session.watchedSeconds / 3_600, 0.25)
            let completionWeight = session.status == .completed ? 1.0 : 0
            add(
                metadata.genres.map(\.name),
                weight: durationWeight + completionWeight,
                to: &affinities
            )
        }
        for favorite in activeFavorites {
            guard let metadata = snapshots[favorite.mediaKey]?.metadata else { continue }
            add(metadata.genres.map(\.name), weight: 2, to: &affinities)
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
            let score = matches.reduce(0) { $0 + $1.weight }
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
