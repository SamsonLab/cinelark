import Foundation
import CineLarkDomain
import CineLarkPluginAPI

extension EmbyService {
    func page(query: MediaQuery, searchTerm: String? = nil) async throws -> MediaPage {
        let token = try await requiredToken()
        guard let userID = configuration.remoteUserID else {
            throw MediaSourceFailure.unauthorized
        }
        let offset = query.cursor.flatMap { Int($0.rawValue) } ?? 0
        var items = [
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "StartIndex", value: String(offset)),
            URLQueryItem(name: "Limit", value: String(query.limit)),
            URLQueryItem(name: "Fields", value: Self.summaryFields.joined(separator: ","))
        ]
        if !query.kinds.isEmpty {
            items.append(
                URLQueryItem(
                    name: "IncludeItemTypes",
                    value: query.kinds.map(Self.embyType).sorted().joined(separator: ",")
                )
            )
        }
        if let parent = query.parent {
            items.append(URLQueryItem(name: "ParentId", value: parent.providerItemID))
        }
        if let searchTerm, !searchTerm.isEmpty {
            items.append(URLQueryItem(name: "SearchTerm", value: searchTerm))
        }
        for filter in query.filters {
            switch filter {
            case let .favorite(value):
                items.append(URLQueryItem(name: "IsFavorite", value: String(value)))
            case let .played(value):
                items.append(URLQueryItem(name: "IsPlayed", value: String(value)))
            case let .resumable(value) where value:
                items.append(URLQueryItem(name: "Filters", value: "IsResumable"))
            default:
                break
            }
        }
        if let sort = query.sort {
            items.append(URLQueryItem(name: "SortBy", value: Self.embySort(sort.field)))
            items.append(
                URLQueryItem(
                    name: "SortOrder",
                    value: sort.order == .ascending ? "Ascending" : "Descending"
                )
            )
        }
        let request = try builder.request(
            path: "Users/\(userID)/Items",
            query: items,
            token: token
        )
        let page: ItemPageDTO = try await response(for: request)
        let located = page.items.compactMap { map($0) }
        return MediaPage(
            items: located,
            nextCursor: try Self.nextCursor(
                offset: offset,
                consumedCount: page.items.count,
                total: page.totalRecordCount
            ),
            total: page.totalRecordCount
        )
    }

    func collections() async throws -> [MediaCollection] {
        let token = try await requiredToken()
        guard let userID = configuration.remoteUserID else {
            throw MediaSourceFailure.unauthorized
        }
        let request = try builder.request(path: "Users/\(userID)/Views", token: token)
        let page: ItemPageDTO = try await response(for: request)
        return page.items.enumerated().map { index, item in
            MediaCollection(
                id: item.id,
                name: item.name,
                mediaKind: Self.collectionKind(item.collectionType),
                order: index,
                itemCount: item.childCount ?? 0
            )
        }
    }

    func latest(query: MediaQuery) async throws -> MediaPage {
        let token = try await requiredToken()
        guard let userID = configuration.remoteUserID else {
            throw MediaSourceFailure.unauthorized
        }
        var queryItems = [
            URLQueryItem(name: "Limit", value: String(query.limit)),
            URLQueryItem(
                name: "Fields",
                value: (Self.summaryFields + ["People"]).joined(separator: ",")
            )
        ]
        if let parent = query.parent {
            queryItems.append(URLQueryItem(name: "ParentId", value: parent.providerItemID))
        }
        if !query.kinds.isEmpty {
            queryItems.append(URLQueryItem(
                name: "IncludeItemTypes",
                value: query.kinds.map(Self.embyType).sorted().joined(separator: ",")
            ))
        }
        let request = try builder.request(
            path: "Users/\(userID)/Items/Latest",
            query: queryItems,
            token: token
        )
        let items: [ItemDTO] = try await response(for: request)
        let located = items.compactMap(map)
        return MediaPage(items: located, nextCursor: nil, total: located.count)
    }

    func resume(query: MediaQuery) async throws -> MediaPage {
        try await specialPage(pathSuffix: "Items/Resume", query: query)
    }

    func detail(locator: MediaLocatorID) async throws -> MediaDetail {
        let item = try await item(id: locator.providerItemID)
        guard let located = map(item) else { throw MediaSourceFailure.invalidResponse }
        let credits = (item.people ?? []).enumerated().compactMap { index, person
            -> (String?, PersonCredit)? in
            guard let id = person.id else { return nil }
            return (
                person.type?.lowercased(),
                PersonCredit(
                    id: id,
                    name: person.name,
                    character: person.role,
                    avatarURL: person.primaryImageTag == nil
                        ? nil
                        : imageURL(itemID: id, path: "Primary"),
                    order: index
                )
            )
        }
        let directors = credits.compactMap { $0.0 == "director" ? $0.1 : nil }
        let cast = credits.compactMap { $0.0 == "actor" ? $0.1 : nil }
        return MediaDetail(
            summary: located.summary,
            directors: directors,
            cast: cast,
            tmdbID: item.providerIDs?["Tmdb"],
            imdbID: item.providerIDs?["Imdb"]
        )
    }

    func seasons(series: MediaLocatorID) async throws -> [Season] {
        let token = try await requiredToken()
        guard let userID = configuration.remoteUserID else {
            throw MediaSourceFailure.unauthorized
        }
        let request = try builder.request(
            path: "Shows/\(series.providerItemID)/Seasons",
            query: [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "Fields", value: "UserData")
            ],
            token: token
        )
        let page: ItemPageDTO = try await response(for: request)
        return page.items.map { item in
            Season(
                id: item.id,
                seriesID: series.providerItemID,
                number: item.indexNumber ?? 0,
                title: item.name,
                posterURL: item.imageTags?["Primary"] == nil
                    ? nil
                    : imageURL(itemID: item.id, path: "Primary"),
                episodeCount: item.childCount ?? 0,
                userState: Self.userState(item)
            )
        }
    }

    func seriesPlayback(series: MediaLocatorID) async throws -> SeriesPlaybackState {
        let token = try await requiredToken()
        guard let userID = configuration.remoteUserID else {
            throw MediaSourceFailure.unauthorized
        }
        let fields = "Overview,UserData,RunTimeTicks,MediaSourceCount"
        let resumeRequest = try builder.request(
            path: "Users/\(userID)/Items/Resume",
            query: [
                URLQueryItem(name: "ParentId", value: series.providerItemID),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "IncludeItemTypes", value: "Episode"),
                URLQueryItem(name: "Limit", value: "1"),
                URLQueryItem(name: "Fields", value: fields)
            ],
            token: token
        )
        let nextUpRequest = try builder.request(
            path: "Shows/NextUp",
            query: [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "SeriesId", value: series.providerItemID),
                URLQueryItem(name: "Limit", value: "1"),
                URLQueryItem(name: "Fields", value: fields)
            ],
            token: token
        )

        async let resumePage: ItemPageDTO = response(for: resumeRequest)
        async let nextUpPage: ItemPageDTO = response(for: nextUpRequest)
        let (resume, nextUp) = try await (resumePage, nextUpPage)
        return SeriesPlaybackState(
            resume: resume.items.first.flatMap {
                continueWatchingItem($0, series: series)
            },
            nextUp: nextUp.items.first.flatMap {
                continueWatchingItem($0, series: series)
            }
        )
    }

    func episodes(
        series: MediaLocatorID,
        seasonID: String,
        page requestPage: PageRequest
    ) async throws -> Page<Episode> {
        let token = try await requiredToken()
        guard let userID = configuration.remoteUserID else {
            throw MediaSourceFailure.unauthorized
        }
        let start = (requestPage.number - 1) * requestPage.size
        let request = try builder.request(
            path: "Shows/\(series.providerItemID)/Episodes",
            query: [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "SeasonId", value: seasonID),
                URLQueryItem(name: "StartIndex", value: String(start)),
                URLQueryItem(name: "Limit", value: String(requestPage.size)),
                URLQueryItem(name: "Fields", value: "Overview,UserData,RunTimeTicks,MediaSourceCount")
            ],
            token: token
        )
        let page: ItemPageDTO = try await response(for: request)
        return Page(
            number: requestPage.number,
            size: requestPage.size,
            total: page.totalRecordCount,
            items: page.items.map { item in
                Episode(
                    id: item.id,
                    seriesID: item.seriesID ?? series.providerItemID,
                    seasonID: item.seasonID ?? seasonID,
                    number: item.indexNumber ?? 0,
                    title: item.name,
                    synopsis: item.overview,
                    airDate: item.premiereDate,
                    thumbnailURL: item.imageTags?["Primary"] == nil
                        ? nil
                        : imageURL(itemID: item.id, path: "Primary"),
                    durationSeconds: item.runTimeTicks.map { Double($0) / 10_000_000 },
                    versionCount: item.mediaSourceCount ?? 0,
                    hasMultipleVersions: (item.mediaSourceCount ?? 0) > 1,
                    userState: Self.userState(item)
                )
            }
        )
    }

    func person(id: String) async throws -> PersonDetail {
        let value = try await item(id: id)
        return PersonDetail(
            id: value.id,
            name: value.name,
            avatarURL: value.imageTags?["Primary"] == nil
                ? nil
                : imageURL(itemID: value.id, path: "Primary"),
            isFavorite: value.userData?.isFavorite ?? false,
            tmdbID: value.providerIDs?["Tmdb"],
            imdbID: value.providerIDs?["Imdb"]
        )
    }

    func works(personID: String, query: MediaQuery) async throws -> MediaPage {
        try await specialPage(
            pathSuffix: "Items",
            query: query,
            additional: [URLQueryItem(name: "PersonIds", value: personID)]
        )
    }

    func artwork(locator: MediaLocatorID, kind: String) async throws -> ArtworkDescriptor {
        let token = try await requiredToken()
        let imageType = kind.lowercased() == "backdrop" ? "Backdrop/0" : "Primary"
        let request = try builder.request(
            path: "Items/\(locator.providerItemID)/Images/\(imageType)",
            token: token
        )
        return ArtworkDescriptor(
            url: request.url!,
            headers: ["X-Emby-Authorization": request.value(forHTTPHeaderField: "X-Emby-Authorization")!]
        )
    }

}
