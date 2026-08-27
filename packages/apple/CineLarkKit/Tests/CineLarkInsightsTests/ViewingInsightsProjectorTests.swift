import Foundation
import Testing
import CineLarkDomain
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
