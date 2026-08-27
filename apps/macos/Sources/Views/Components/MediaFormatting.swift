import Foundation
import SwiftUI
import CineLarkDomain
import CineLarkPluginAPI

struct MediaFactSet: OptionSet, Sendable {
    let rawValue: Int

    static let year = Self(rawValue: 1 << 0)
    static let rating = Self(rawValue: 1 << 1)
    static let duration = Self(rawValue: 1 << 2)
    static let seasonCount = Self(rawValue: 1 << 3)

    static let compact: Self = [.year, .rating]
    static let extended: Self = [.year, .rating, .duration, .seasonCount]
}

struct MediaFacts: View {
    @Environment(\.appLanguage) private var language

    let item: MediaSummary
    let fields: MediaFactSet
    let spacing: CGFloat
    let font: Font

    init(
        item: MediaSummary,
        fields: MediaFactSet = .compact,
        spacing: CGFloat = 8,
        font: Font = CineLarkDesign.Typography.cardMetadata
    ) {
        self.item = item
        self.fields = fields
        self.spacing = spacing
        self.font = font
    }

    var body: some View {
        HStack(spacing: spacing) {
            if fields.contains(.year), let year = item.releaseYear {
                Text(String(year))
            }

            if fields.contains(.rating), let rating = item.rating {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .accessibilityHidden(true)
                    Text(rating.cineLarkRating)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    language.localized("rating.accessibility", rating.cineLarkRating)
                )
            }

            if fields.contains(.duration), let duration = item.durationSeconds {
                Text(language.duration(duration))
            }

            if fields.contains(.seasonCount), let seasons = item.totalSeasons {
                Text(
                    language.localized(
                        seasons == 1 ? "detail.season_count_one" : "detail.season_count_many",
                        String(seasons)
                    )
                )
            }
        }
        .font(font)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
}

enum MediaArtworkRole {
    case discovery
    case playback

    var showsStateBadges: Bool {
        self == .discovery
    }
}

struct MediaArtworkSurface: View {
    @Environment(\.mediaTransitionNamespace) private var transitionNamespace
    @Environment(\.activeMediaSourceID) private var activeSourceID

    let item: MediaSummary
    let url: URL?
    let locator: MediaLocatorID?
    let size: CGSize
    let role: MediaArtworkRole
    let transitionID: UUID?
    let isTransitionSource: Bool

    init(
        item: MediaSummary,
        url: URL?,
        locator: MediaLocatorID? = nil,
        size: CGSize,
        role: MediaArtworkRole,
        transitionID: UUID? = nil,
        isTransitionSource: Bool = true
    ) {
        self.item = item
        self.url = url
        self.locator = locator
        self.size = size
        self.role = role
        self.transitionID = transitionID
        self.isTransitionSource = isTransitionSource
    }

    var body: some View {
        ArtworkView(
            url: url,
            locator: resolvedLocator,
            artworkKind: resolvedArtworkKind
        )
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
            .clipShape(shape)
            .mediaMatchedGeometry(
                id: transitionID,
                namespace: transitionNamespace,
                isSource: isTransitionSource
            )
            .overlay(alignment: .bottom) {
                MediaPlaybackProgress(item: item)
            }
            .overlay(alignment: .topTrailing) {
                if role.showsStateBadges {
                    MediaStateBadges(item: item)
                        .padding(10)
                }
            }
            .contentShape(shape)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: CineLarkDesign.Shape.cardRadius,
            style: .continuous
        )
    }

    private var resolvedLocator: MediaLocatorID? {
        locator ?? activeSourceID.map {
            MediaLocatorID(sourceID: $0, providerItemID: item.id)
        }
    }

    private var resolvedArtworkKind: String {
        url == item.backdropURL && item.posterURL != item.backdropURL
            ? "backdrop"
            : "primary"
    }
}

struct MediaStateBadges: View {
    @Environment(\.appLanguage) private var language

    let item: MediaSummary
    var size: CGFloat = 32
    var spacing: CGFloat = 7

    var body: some View {
        VStack(spacing: spacing) {
            if item.userState.favorite == true {
                badge(
                    systemImage: "heart.fill",
                    color: CineLarkDesign.Palette.favorite,
                    accessibilityLabel: language.localized("detail.favorite")
                )
            }

            if item.userState.played {
                badge(
                    systemImage: "checkmark",
                    color: CineLarkDesign.Palette.watched,
                    accessibilityLabel: language.localized("detail.watched")
                )
            }
        }
    }

    private func badge(
        systemImage: String,
        color: Color,
        accessibilityLabel: String
    ) -> some View {
        Image(systemName: systemImage)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(CineLarkDesign.Palette.badgeBackground, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(CineLarkDesign.Palette.badgeStroke, lineWidth: 0.75)
            }
            .accessibilityLabel(accessibilityLabel)
    }
}

struct MediaPlaybackProgress: View {
    let item: MediaSummary
    var inset: CGFloat = 10

    var body: some View {
        if item.userState.progress > 0 && !item.userState.played {
            ProgressView(value: item.userState.progress)
                .progressViewStyle(.linear)
                .tint(CineLarkDesign.Palette.progress)
                .padding(inset)
        }
    }
}

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
