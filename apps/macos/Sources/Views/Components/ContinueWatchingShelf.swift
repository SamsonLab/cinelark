import SwiftUI
import CineLarkDomain

struct ContinueWatchingShelf: View {
    @Environment(\.appLanguage) private var language
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(language.localized("home.continue_watching"))
                .font(.title2.bold())

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 20) {
                    ForEach(model.continueWatching) { item in
                        ContinueWatchingCard(
                            item: item,
                            isPlaying: model.playingItemID == item.id,
                            isPlaybackDisabled: model.playingItemID != nil
                        ) {
                            Task { await model.play(item) }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct ContinueWatchingCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appLanguage) private var language
    let item: ContinueWatchingItem
    let isPlaying: Bool
    let isPlaybackDisabled: Bool
    let play: () -> Void
    @State private var isArtworkHovering = false
    @State private var isTextHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: play) {
                artwork
            }
            .buttonStyle(CineLarkPressButtonStyle())
            .disabled(isPlaybackDisabled)
            .accessibilityLabel(
                language.localized("home.continue_playback", item.title)
            )

            NavigationLink(value: detailItem) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(isTextHovering ? Color.accentColor : .primary)
                        .lineLimit(1)
                        .help(item.title)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(isTextHovering ? Color.accentColor.opacity(0.85) : .secondary)
                            .lineLimit(1)
                    }
                }
                .frame(width: 300, alignment: .topLeading)
                .frame(minHeight: 36, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isTextHovering = $0 }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: isTextHovering
            )
            .accessibilityLabel(
                [item.title, item.subtitle]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            )
            .accessibilityHint(language.localized("home.open_details"))
        }
    }

    private var artwork: some View {
        ZStack {
            ArtworkView(url: item.thumbnailURL ?? item.posterURL)
                .frame(width: 300, height: 169)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(
                            isArtworkHovering
                                ? Color.accentColor.opacity(0.70)
                                : Color.white.opacity(0.10),
                            lineWidth: isArtworkHovering ? 1.5 : 1
                        )
                        .allowsHitTesting(false)
                }
                .shadow(
                    color: .black.opacity(isArtworkHovering ? 0.42 : 0.24),
                    radius: isArtworkHovering ? 18 : 12,
                    y: isArtworkHovering ? 9 : 6
                )

            Circle()
                .fill(
                    isArtworkHovering
                        ? Color.accentColor.opacity(0.88)
                        : Color.black.opacity(0.68)
                )
                .frame(width: 54, height: 54)
                .overlay {
                    if isPlaying {
                        ProgressView()
                    } else {
                        Image(systemName: "play.fill")
                            .font(.title2)
                            .offset(x: 2)
                    }
                }
        }
        .overlay(alignment: .bottom) {
            ProgressView(value: item.userState.progress)
                .progressViewStyle(.linear)
                .tint(Color.accentColor)
                .padding(8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .scaleEffect(isArtworkHovering && !reduceMotion ? 1.008 : 1)
        .offset(y: isArtworkHovering && !reduceMotion ? -1 : 0)
        .onHover { isArtworkHovering = $0 }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: isArtworkHovering
        )
    }

    private var detailItem: MediaSummary {
        switch item.item.kind {
        case .movie:
            MediaSummary(
                id: item.item.id,
                kind: .movie,
                title: item.title,
                durationSeconds: item.durationSeconds,
                posterURL: item.posterURL,
                backdropURL: item.thumbnailURL,
                userState: item.userState
            )
        case .episode:
            MediaSummary(
                id: item.mediaID,
                kind: .series,
                title: item.title,
                posterURL: item.posterURL,
                backdropURL: item.thumbnailURL,
                userState: item.userState
            )
        }
    }
}
