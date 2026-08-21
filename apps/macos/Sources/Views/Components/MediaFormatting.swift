import Foundation
import CineLarkDomain

extension Double {
    var cineLarkRating: String {
        formatted(.number.precision(.fractionLength(0...1)))
    }
}

extension Int64 {
    var cineLarkByteCount: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension ContinueWatchingItem {
    var mediaSummary: MediaSummary {
        switch item.kind {
        case .movie:
            MediaSummary(
                id: item.id,
                kind: .movie,
                title: title,
                durationSeconds: durationSeconds,
                posterURL: posterURL,
                backdropURL: thumbnailURL,
                userState: userState
            )
        case .episode:
            MediaSummary(
                id: mediaID,
                kind: .series,
                title: title,
                posterURL: posterURL,
                backdropURL: thumbnailURL,
                userState: userState
            )
        }
    }
}
