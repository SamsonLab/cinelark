import Foundation
import CineLarkDomain
import CineLarkPluginAPI

extension EmbyService {
    func report(_ event: PlaybackEvent) async throws {
        let token = try await requiredToken()
        let path: String
        let locator: MediaLocatorID
        let position: Double
        let isPaused: Bool
        switch event {
        case let .started(value, seconds):
            path = "Sessions/Playing"
            locator = value
            position = seconds
            isPaused = false
        case let .progress(value, seconds, paused):
            path = "Sessions/Playing/Progress"
            locator = value
            position = seconds
            isPaused = paused
        case let .stopped(value, seconds, _):
            path = "Sessions/Playing/Stopped"
            locator = value
            position = seconds
            isPaused = false
        }
        let payload: [String: Any] = [
            "ItemId": locator.providerItemID,
            "PositionTicks": Int64(max(position, 0) * 10_000_000),
            "IsPaused": isPaused
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let request = try builder.request(path: path, method: "POST", token: token, body: data)
        try await sendMutation(request)
    }

    func importRemoteState() async throws -> RemoteStateSnapshot {
        guard let remoteUserID = configuration.remoteUserID else {
            throw MediaSourceFailure.unauthorized
        }
        let base = MediaQuery(scope: SourceScope(sourceID: configuration.sourceID), limit: 200)
        let favorites = try await collectPages(
            initial: MediaQuery(
                scope: base.scope,
                kinds: [.movie, .series],
                filters: [.favorite(true)],
                limit: base.limit
            ),
            fetch: { try await self.page(query: $0) }
        )
        let resumable = try await collectPages(
            initial: base,
            fetch: { try await self.resume(query: $0) }
        )
        var values: [MediaLocatorID: RemoteMediaState] = [:]
        for item in favorites {
            values[item.locator] = RemoteMediaState(
                locator: item.locator,
                summary: item.summary,
                isFavorite: true,
                playback: item.summary.userState.positionSeconds > 0 || item.summary.userState.played
                    ? item.summary.userState
                    : nil
            )
        }
        for item in resumable {
            let current = values[item.locator]
            values[item.locator] = RemoteMediaState(
                locator: item.locator,
                summary: item.summary,
                isFavorite: current?.isFavorite ?? item.summary.userState.favorite,
                playback: item.summary.userState
            )
        }
        return RemoteStateSnapshot(
            marker: "emby-v1:\(configuration.serverIdentity.serverID):\(remoteUserID)",
            remoteUserID: remoteUserID,
            items: values.values.sorted {
                $0.locator.providerItemID < $1.locator.providerItemID
            }
        )
    }

    func mirrorRemoteState(userID: String, mutation: RemoteStateMutation) async throws {
        let token = try await requiredToken()
        guard configuration.remoteUserID == userID else {
            throw MediaSourceFailure.unauthorized
        }
        switch mutation {
        case let .favorite(locator, isFavorite):
            let request = try builder.request(
                path: "Users/\(userID)/FavoriteItems/\(locator.providerItemID)",
                method: isFavorite ? "POST" : "DELETE",
                token: token
            )
            try await sendMutation(request)

        case let .playback(locator, state):
            try await report(.progress(
                locator: locator,
                positionSeconds: state.positionSeconds,
                isPaused: true
            ))
            let request = try builder.request(
                path: "Users/\(userID)/PlayedItems/\(locator.providerItemID)",
                method: state.played ? "POST" : "DELETE",
                token: token
            )
            try await sendMutation(request)
        }
    }

}
