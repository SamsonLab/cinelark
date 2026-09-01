import Foundation
import Testing
import CineLarkDomain
import CineLarkCatalog
import CineLarkInsights
import CineLarkPluginAPI
import CineLarkProfile

@Test func emptyProjectionProducesAStableZeroSnapshot() {
    let profileID = ProfileID(rawValue: UUID())
    let referenceDate = date(2026, 8, 27)

    let result = ViewingInsightsProjector.project(
        profileID: profileID,
        period: .year,
        containing: referenceDate,
        calendar: utcCalendar(),
        sessions: [],
        snapshots: [:]
    )

    #expect(result.profileID == profileID)
    #expect(result.totalWatchSeconds == 0)
    #expect(result.sessionCount == 0)
    #expect(result.activity.isEmpty)
    #expect(result.topTitles.isEmpty)
    #expect(result.topGenres.isEmpty)
}

@Test func monthProjectionRanksTitlesAndMetadataDimensions() throws {
    let calendar = utcCalendar()
    let profileID = ProfileID(rawValue: UUID())
    let sourceID = SourceID(rawValue: UUID())
    let firstKey = ProfileMediaKey(rawValue: "movie:arrival")
    let secondKey = ProfileMediaKey(rawValue: "movie:blade-runner")
    let sessions = [
        session(profileID: profileID, mediaKey: firstKey, at: date(2026, 8, 1), watched: 10),
        session(
            profileID: profileID,
            mediaKey: firstKey,
            at: date(2026, 8, 15),
            watched: 20,
            status: .completed
        ),
        session(
            profileID: profileID,
            mediaKey: secondKey,
            at: date(2026, 8, 20),
            watched: 40,
            status: .completed
        ),
        session(profileID: profileID, mediaKey: firstKey, at: date(2026, 7, 31), watched: 60)
    ]
    let snapshots = [
        firstKey: snapshot(
            key: firstKey,
            sourceID: sourceID,
            title: "Arrival",
            genres: ["Drama", "Science Fiction"],
            directors: ["Denis Villeneuve"],
            cast: ["Amy Adams"]
        ),
        secondKey: snapshot(
            key: secondKey,
            sourceID: sourceID,
            title: "Blade Runner 2049",
            genres: ["Drama"],
            directors: ["Denis Villeneuve"],
            cast: ["Ryan Gosling"]
        )
    ]

    let result = ViewingInsightsProjector.project(
        profileID: profileID,
        period: .month,
        containing: date(2026, 8, 27),
        calendar: calendar,
        sessions: sessions,
        snapshots: snapshots
    )

    #expect(result.totalWatchSeconds == 70)
    #expect(result.sessionCount == 3)
    #expect(result.completedSessionCount == 2)
    #expect(result.distinctTitleCount == 2)
    #expect(result.activeDayCount == 3)
    #expect(result.longestStreakDays == 1)
    #expect(result.topTitles.map(\.title) == ["Blade Runner 2049", "Arrival"])
    #expect(result.topTitles.map(\.watchedSeconds) == [40, 30])
    #expect(result.topTitles.first?.locator == MediaLocatorID(
        sourceID: sourceID,
        providerItemID: secondKey.rawValue
    ))
    #expect(result.topGenres.map(\.name) == ["Drama", "Science Fiction"])
    #expect(result.topGenres.map(\.watchedSeconds) == [70, 30])
    #expect(result.topDirectors.first?.name == "Denis Villeneuve")
    #expect(result.topDirectors.first?.watchedSeconds == 70)
    #expect(result.topActors.map(\.name) == ["Ryan Gosling", "Amy Adams"])
}

@Test func quarterProjectionCalculatesStreakAndDeterministicTies() throws {
    let calendar = utcCalendar()
    let profileID = ProfileID(rawValue: UUID())
    let firstKey = ProfileMediaKey(rawValue: "movie:a")
    let secondKey = ProfileMediaKey(rawValue: "movie:b")
    let sessions = [
        session(profileID: profileID, mediaKey: secondKey, at: date(2026, 4, 1), watched: 10),
        session(profileID: profileID, mediaKey: firstKey, at: date(2026, 4, 2), watched: 10),
        session(profileID: profileID, mediaKey: firstKey, at: date(2026, 4, 3), watched: 0),
        session(profileID: profileID, mediaKey: firstKey, at: date(2026, 4, 4), watched: 5),
        session(profileID: profileID, mediaKey: firstKey, at: date(2026, 7, 1), watched: 100)
    ]
    let sourceID = SourceID(rawValue: UUID())
    let snapshots = [
        firstKey: snapshot(key: firstKey, sourceID: sourceID, title: "Alpha"),
        secondKey: snapshot(key: secondKey, sourceID: sourceID, title: "Beta")
    ]

    let result = ViewingInsightsProjector.project(
        profileID: profileID,
        period: .quarter,
        containing: date(2026, 5, 10),
        calendar: calendar,
        sessions: sessions,
        snapshots: snapshots
    )

    #expect(result.range.start == date(2026, 4, 1))
    #expect(result.range.end == date(2026, 7, 1))
    #expect(result.totalWatchSeconds == 25)
    #expect(result.sessionCount == 3)
    #expect(result.activeDayCount == 3)
    #expect(result.longestStreakDays == 2)
    #expect(result.activity.map(\.day) == [
        date(2026, 4, 1), date(2026, 4, 2), date(2026, 4, 4)
    ])
    #expect(result.topTitles.map(\.title) == ["Alpha", "Beta"])
}

@Test func allTimeProjectionUsesLocalCalendarAndToleratesMissingMetadata() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    let profileID = ProfileID(rawValue: UUID())
    let mediaKey = ProfileMediaKey(rawValue: "legacy:item")
    let activity = ISO8601DateFormatter().date(from: "2026-01-02T07:30:00Z")!
    let reference = ISO8601DateFormatter().date(from: "2026-08-27T12:00:00Z")!

    let result = ViewingInsightsProjector.project(
        profileID: profileID,
        period: .allTime,
        containing: reference,
        calendar: calendar,
        sessions: [
            session(profileID: profileID, mediaKey: mediaKey, at: activity, watched: 12)
        ],
        snapshots: [:]
    )

    #expect(result.range.start == calendar.startOfDay(for: activity))
    #expect(result.range.end == calendar.date(
        byAdding: .day,
        value: 1,
        to: calendar.startOfDay(for: reference)
    ))
    #expect(result.topTitles.first?.title == "legacy:item")
    #expect(result.topTitles.first?.kind == nil)
    #expect(result.topGenres.isEmpty)
    #expect(result.topDirectors.isEmpty)
    #expect(result.topActors.isEmpty)
}

@Test func recommendationsArePrivateExplainableAndExcludeViewedLocators() throws {
    let profileID = ProfileID(rawValue: UUID())
    let sourceID = SourceID(rawValue: UUID())
    let watched = MediaLocatorID(sourceID: sourceID, providerItemID: "watched")
    let favorite = MediaLocatorID(sourceID: sourceID, providerItemID: "favorite")
    let watchedKey = ProfileMediaKey(locator: watched)
    let favoriteKey = ProfileMediaKey(locator: favorite)
    let snapshots = [
        watchedKey: snapshot(
            key: watchedKey,
            sourceID: sourceID,
            title: "Watched",
            genres: ["Drama"]
        ),
        favoriteKey: snapshot(
            key: favoriteKey,
            sourceID: sourceID,
            title: "Favorite",
            genres: ["Science Fiction"]
        )
    ]
    let candidates = [
        candidate(locator: watched, title: "Already Watched", genres: ["Drama"], rating: 10),
        candidate(
            locator: favorite,
            title: "Already Favorited",
            genres: ["Science Fiction"],
            rating: 10
        ),
        candidate(
            sourceID: sourceID,
            id: "mixed",
            title: "Mixed",
            genres: ["Drama", "Science Fiction"],
            rating: 7,
            summaryID: "catalog-identity"
        ),
        candidate(
            sourceID: sourceID,
            id: "drama",
            title: "Drama Only",
            genres: ["Drama"],
            rating: 9
        ),
        candidate(
            sourceID: sourceID,
            id: "irrelevant",
            title: "Irrelevant",
            genres: ["Comedy"],
            rating: 10
        )
    ]
    let recommendations = ViewingRecommendationProjector.project(
        sessions: [
            session(
                profileID: profileID,
                mediaKey: watchedKey,
                at: date(2026, 8, 20),
                watched: 3_600,
                status: .completed
            )
        ],
        favorites: [
            ProfileFavoriteState(
                profileID: profileID,
                mediaKey: favoriteKey,
                isFavorite: true,
                modifiedAt: date(2026, 8, 21),
                deviceID: "device"
            )
        ],
        snapshots: snapshots,
        candidates: candidates,
        referenceDate: date(2026, 8, 27)
    )

    #expect(recommendations.map(\.summary.title) == ["Mixed", "Drama Only"])
    #expect(recommendations.first?.summary.id == "mixed")
    #expect(recommendations.first?.reasons == [
        .matchingGenre("Science Fiction"),
        .matchingGenre("Drama")
    ])
    #expect(recommendations.allSatisfy { $0.summary.userState == .empty })
    #expect(!recommendations.contains { $0.locator == watched })
    #expect(!recommendations.contains { $0.locator == favorite })
}

@Test func recommendationSignalsAreBoundedAndTimeAware() throws {
    let profileID = ProfileID(rawValue: UUID())
    let sourceID = SourceID(rawValue: UUID())
    let referenceDate = date(2026, 8, 27)
    let oldDate = referenceDate.addingTimeInterval(-180 * 86_400)
    let evidence: [(String, String, Double, ViewingSessionStatus, Date)] = [
        ("long", "Long", 14_400, .stopped, referenceDate),
        ("old", "Old", 7_200, .completed, oldDate),
        ("completed", "Completed", 300, .completed, referenceDate),
        ("short", "Short", 60, .stopped, referenceDate)
    ]
    var snapshots: [ProfileMediaKey: ProfileMediaSnapshot] = [:]
    let sessions = evidence.map { id, genre, watched, status, timestamp in
        let locator = MediaLocatorID(sourceID: sourceID, providerItemID: id)
        let key = ProfileMediaKey(locator: locator)
        snapshots[key] = snapshot(
            key: key,
            sourceID: sourceID,
            title: id,
            genres: [genre]
        )
        return session(
            profileID: profileID,
            mediaKey: key,
            at: timestamp,
            watched: watched,
            status: status
        )
    }
    let favoriteLocator = MediaLocatorID(sourceID: sourceID, providerItemID: "favorite")
    let favoriteKey = ProfileMediaKey(locator: favoriteLocator)
    snapshots[favoriteKey] = snapshot(
        key: favoriteKey,
        sourceID: sourceID,
        title: "favorite",
        genres: ["Favorite"]
    )
    let candidates = ["Favorite", "Long", "Old", "Completed", "Short"].map {
        candidate(sourceID: sourceID, id: "candidate-\($0.lowercased())", title: $0, genres: [$0])
    }

    let recommendations = ViewingRecommendationProjector.project(
        sessions: sessions,
        favorites: [
            ProfileFavoriteState(
                profileID: profileID,
                mediaKey: favoriteKey,
                isFavorite: true,
                modifiedAt: referenceDate,
                deviceID: "device"
            )
        ],
        snapshots: snapshots,
        candidates: candidates,
        referenceDate: referenceDate
    )

    #expect(recommendations.map(\.summary.title) == [
        "Favorite", "Long", "Old", "Completed", "Short"
    ])
    #expect(abs((recommendations.first { $0.summary.title == "Long" }?.score ?? 0) - 2) < 0.000_1)
    #expect(abs((recommendations.first { $0.summary.title == "Old" }?.score ?? 0) - 1.75) < 0.000_1)
    #expect((recommendations.last?.score ?? 1) < 0.02)
}

@Test func recommendationRankingDiscountsSecondaryGenreMatches() throws {
    let profileID = ProfileID(rawValue: UUID())
    let sourceID = SourceID(rawValue: UUID())
    let referenceDate = date(2026, 8, 27)
    let evidence: [(String, String, Double)] = [
        ("strong", "Strong", 7_200),
        ("weak-a", "Weak A", 3_600),
        ("weak-b", "Weak B", 3_600)
    ]
    var snapshots: [ProfileMediaKey: ProfileMediaSnapshot] = [:]
    let sessions = evidence.map { id, genre, watched in
        let locator = MediaLocatorID(sourceID: sourceID, providerItemID: id)
        let key = ProfileMediaKey(locator: locator)
        snapshots[key] = snapshot(
            key: key,
            sourceID: sourceID,
            title: id,
            genres: [genre]
        )
        return session(
            profileID: profileID,
            mediaKey: key,
            at: referenceDate,
            watched: watched,
            status: .stopped
        )
    }

    let recommendations = ViewingRecommendationProjector.project(
        sessions: sessions,
        favorites: [],
        snapshots: snapshots,
        candidates: [
            candidate(sourceID: sourceID, id: "broad", title: "Broad", genres: ["Weak A", "Weak B"]),
            candidate(sourceID: sourceID, id: "focused", title: "Focused", genres: ["Strong"])
        ],
        referenceDate: referenceDate
    )

    #expect(recommendations.map(\.summary.title) == ["Focused", "Broad"])
    #expect(recommendations.map(\.score) == [2, 1.35])
}

@Test func serviceEnrichesHistoryFromCatalogBeforeProjectingRecommendations() async throws {
    let repository = try CoreDataProfileRepository(configuration: .init(inMemory: true))
    let catalog = try CoreDataCatalogStore(inMemory: true)
    let profileID = ProfileID(rawValue: UUID())
    let clientID = ClientID(rawValue: UUID())
    let sourceID = SourceID(rawValue: UUID())
    let watched = MediaLocatorID(sourceID: sourceID, providerItemID: "watched")
    let watchedKey = ProfileMediaKey(locator: watched)
    let activityDate = date(2026, 8, 20)
    let originalStamp = MutationStamp(date: activityDate, clientID: clientID.description)
    try await repository.saveProfile(Profile(
        id: profileID,
        name: "Personal",
        createdAt: activityDate,
        modifiedAt: activityDate,
        deviceID: clientID.description,
        mutationStamp: originalStamp
    ))
    try await repository.savePlayback(ProfilePlaybackWrite(
        state: ProfilePlaybackState(
            profileID: profileID,
            mediaKey: watchedKey,
            state: UserPlaybackState(
                played: true,
                positionSeconds: 7_200,
                progress: 1,
                lastPlayedAt: activityDate
            ),
            modifiedAt: activityDate,
            deviceID: clientID.description,
            mutationStamp: originalStamp
        ),
        snapshot: ProfileMediaSnapshot(
            key: watchedKey,
            locator: watched,
            title: "Watched",
            kind: .movie,
            artworkURL: nil,
            modifiedAt: activityDate,
            deviceID: clientID.description,
            mutationStamp: originalStamp
        ),
        session: session(
            profileID: profileID,
            mediaKey: watchedKey,
            at: activityDate,
            watched: 7_200,
            status: .completed
        ),
        event: nil,
        deviceRecord: nil
    ))
    let artworkURL = URL(string: "https://example.invalid/poster.jpg")!
    try await catalog.upsert([
        candidate(locator: watched, title: "Watched", genres: ["Drama"], artworkURL: artworkURL),
        candidate(
            sourceID: sourceID,
            id: "recommendation",
            title: "Recommendation",
            genres: ["Drama"]
        )
    ], refreshedAt: activityDate)

    let service = ViewingInsightsService(
        repository: repository,
        catalog: catalog,
        clientID: clientID
    )
    let result = try await service.snapshot(
        profileID: profileID,
        sourceID: sourceID,
        period: .year,
        containing: date(2026, 8, 27),
        calendar: utcCalendar()
    )

    #expect(result.topGenres.map(\.name) == ["Drama"])
    #expect(result.recommendations.map(\.summary.title) == ["Recommendation"])
    let persisted = try #require(
        try await repository.mediaSnapshots(keys: [watchedKey]).first
    )
    #expect(persisted.metadata?.genres.map(\.name) == ["Drama"])
    #expect(persisted.artworkURL == artworkURL)
    #expect(persisted.effectiveMutationStamp > originalStamp)

    _ = try await service.snapshot(
        profileID: profileID,
        sourceID: sourceID,
        period: .year,
        containing: date(2026, 8, 28),
        calendar: utcCalendar()
    )
    #expect(
        try await repository.mediaSnapshots(keys: [watchedKey]).first?
            .effectiveMutationStamp == persisted.effectiveMutationStamp
    )
}

private func session(
    profileID: ProfileID,
    mediaKey: ProfileMediaKey,
    at date: Date,
    watched: Double,
    status: ViewingSessionStatus = .stopped
) -> ViewingSession {
    let clientID = ClientID(rawValue: UUID())
    return ViewingSession(
        id: ViewingSessionID(rawValue: UUID()),
        profileID: profileID,
        mediaKey: mediaKey,
        deviceRecordID: DeviceRecordID(clientID: clientID),
        startedAt: date.addingTimeInterval(-watched),
        endedAt: date,
        startPositionSeconds: 0,
        endPositionSeconds: watched,
        watchedSeconds: watched,
        status: status,
        modifiedAt: date,
        deviceID: clientID.description
    )
}

private func snapshot(
    key: ProfileMediaKey,
    sourceID: SourceID,
    title: String,
    genres: [String] = [],
    directors: [String] = [],
    cast: [String] = []
) -> ProfileMediaSnapshot {
    ProfileMediaSnapshot(
        key: key,
        locator: MediaLocatorID(sourceID: sourceID, providerItemID: key.rawValue),
        title: title,
        kind: .movie,
        artworkURL: nil,
        metadata: ProfileMediaMetadataSnapshot(
            genres: genres.map { ProfileGenreSnapshot(name: $0) },
            directors: directors.map { ProfilePersonSnapshot(name: $0) },
            cast: cast.map { ProfilePersonSnapshot(name: $0) }
        ),
        modifiedAt: date(2026, 8, 1),
        deviceID: "device"
    )
}

private func candidate(
    locator: MediaLocatorID,
    title: String,
    genres: [String],
    rating: Double? = nil,
    artworkURL: URL? = nil,
    summaryID: String? = nil
) -> LocatedMediaItem {
    LocatedMediaItem(
        locator: locator,
        summary: MediaSummary(
            id: summaryID ?? locator.providerItemID,
            kind: .movie,
            title: title,
            rating: rating,
            posterURL: artworkURL,
            genres: genres.compactMap { Genre.normalized(name: $0) },
            userState: UserPlaybackState(
                played: true,
                positionSeconds: 10,
                progress: 1
            )
        )
    )
}

private func candidate(
    sourceID: SourceID,
    id: String,
    title: String,
    genres: [String],
    rating: Double? = nil,
    summaryID: String? = nil
) -> LocatedMediaItem {
    candidate(
        locator: MediaLocatorID(sourceID: sourceID, providerItemID: id),
        title: title,
        genres: genres,
        rating: rating,
        summaryID: summaryID
    )
}

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var components = DateComponents()
    components.calendar = utcCalendar()
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = year
    components.month = month
    components.day = day
    return components.date!
}
