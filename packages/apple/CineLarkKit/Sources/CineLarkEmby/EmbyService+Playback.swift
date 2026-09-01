import Foundation
import CineLarkDomain
import CineLarkPluginAPI

extension EmbyService {
    func playbackVariants(locator: MediaLocatorID) async throws -> [PlaybackVariant] {
        let info = try await playbackInfo(locator: locator)
        return info.mediaSources
            .filter(Self.supportsPlayback)
            .enumerated()
            .compactMap { index, source in
                guard let id = Self.nonEmpty(source.id) else {
                    return nil
                }
                return Self.playbackVariant(source, id: id, index: index)
            }
    }

    func playback(
        locator: MediaLocatorID,
        variantID: String? = nil
    ) async throws -> SourcePlaybackDescriptor {
        let token = try await requiredToken()
        let info = try await playbackInfo(locator: locator, token: token)
        let supported = info.mediaSources.filter(Self.supportsPlayback)
        let source: PlaybackInfoDTO.MediaSourceDTO?
        if let variantID {
            source = supported.first { $0.id == variantID }
        } else {
            source = supported.first
        }
        guard let source else {
            throw MediaSourceFailure.unsupported("No direct-playable Emby media source")
        }
        let url: URL
        var headers = ["X-Emby-Token": token]
        if let streamPath = Self.nonEmpty(source.directStreamURL) {
            let target = try directStreamTarget(from: streamPath)
            url = target.url
            if let authorizationToken = target.authorizationToken {
                headers["Authorization"] = authorizationToken
            }
        } else {
            url = try canonicalStreamURL(
                locator: locator,
                mediaSourceID: source.id,
                token: token
            )
        }
        return SourcePlaybackDescriptor(
            url: url,
            headers: headers,
            mode: source.supportsDirectPlay == true ? .directPlay : .directStream,
            mediaSourceID: source.id
        )
    }

    private func playbackInfo(
        locator: MediaLocatorID,
        token suppliedToken: String? = nil
    ) async throws -> PlaybackInfoDTO {
        let token: String
        if let suppliedToken {
            token = suppliedToken
        } else {
            token = try await requiredToken()
        }
        let body = try encoder.encode(["DeviceProfile": [String: String]()])
        let request = try builder.request(
            path: "Items/\(locator.providerItemID)/PlaybackInfo",
            method: "POST",
            token: token,
            body: body
        )
        return try await response(for: request)
    }

    private static func supportsPlayback(_ source: PlaybackInfoDTO.MediaSourceDTO) -> Bool {
        source.supportsDirectPlay == true || source.supportsDirectStream == true
    }

    private static func playbackVariant(
        _ source: PlaybackInfoDTO.MediaSourceDTO,
        id: String,
        index: Int
    ) -> PlaybackVariant {
        let streams = source.mediaStreams ?? []
        let video = streams.first { $0.type?.caseInsensitiveCompare("Video") == .orderedSame }
        let audio = streams.compactMap { stream -> AudioTrack? in
            guard stream.type?.caseInsensitiveCompare("Audio") == .orderedSame,
                  let streamIndex = stream.index else { return nil }
            return AudioTrack(
                index: streamIndex,
                codec: nonEmpty(stream.codec),
                bitRate: stream.bitRate,
                channels: stream.channels,
                channelLayout: nonEmpty(stream.channelLayout),
                sampleRate: stream.sampleRate.map(String.init),
                language: nonEmpty(stream.language),
                title: nonEmpty(stream.displayTitle) ?? nonEmpty(stream.title),
                isDefault: stream.isDefault ?? false
            )
        }
        let subtitles = streams.compactMap { stream -> SubtitleTrack? in
            guard stream.type?.caseInsensitiveCompare("Subtitle") == .orderedSame,
                  let streamIndex = stream.index else { return nil }
            return SubtitleTrack(
                index: streamIndex,
                codec: nonEmpty(stream.codec),
                language: nonEmpty(stream.language),
                title: nonEmpty(stream.displayTitle) ?? nonEmpty(stream.title),
                isDefault: stream.isDefault ?? false
            )
        }
        return PlaybackVariant(
            id: id,
            displayName: playbackVariantName(source, video: video, index: index),
            container: nonEmpty(source.container),
            durationSeconds: source.runTimeTicks.map { Double($0) / 10_000_000 },
            fileSize: source.size,
            bitRate: source.bitRate,
            width: video?.width,
            height: video?.height,
            videoCodec: nonEmpty(video?.codec),
            videoProfile: nonEmpty(video?.profile),
            videoBitRate: video?.bitRate,
            pixelFormat: nonEmpty(video?.pixelFormat),
            frameRate: video?.realFrameRate,
            colorSpace: nonEmpty(video?.colorSpace),
            colorTransfer: nonEmpty(video?.colorTransfer),
            colorPrimaries: nonEmpty(video?.colorPrimaries),
            videoRange: nonEmpty(video?.videoRange),
            audioTracks: audio,
            subtitleTracks: subtitles,
            isPreferred: index == 0
        )
    }

    private static func playbackVariantName(
        _ source: PlaybackInfoDTO.MediaSourceDTO,
        video: PlaybackInfoDTO.MediaStreamDTO?,
        index: Int
    ) -> String {
        if let name = nonEmpty(source.name) { return name }
        if let displayTitle = nonEmpty(video?.displayTitle) { return displayTitle }
        if let path = nonEmpty(source.path) {
            let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            if !filename.isEmpty { return filename }
        }
        return "Version \(index + 1)"
    }

}
