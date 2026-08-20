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
                        Button {
                            Task { await model.play(item) }
                        } label: {
                            ContinueWatchingCard(
                                item: item,
                                isPlaying: model.playingItemID == item.id
                            )
                        }
                        .buttonStyle(CineLarkPressButtonStyle())
                        .disabled(model.playingItemID != nil)
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
    let item: ContinueWatchingItem
    let isPlaying: Bool
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                ArtworkView(url: item.thumbnailURL ?? item.posterURL)
                    .frame(width: 300, height: 169)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color.white.opacity(0.10))
                            .allowsHitTesting(false)
                    }
                    .shadow(
                        color: .black.opacity(isHovering ? 0.42 : 0.24),
                        radius: isHovering ? 18 : 12,
                        y: isHovering ? 9 : 6
                    )

                Circle()
                    .fill(
                        isHovering
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

            Text(item.title)
                .font(.headline)
                .lineLimit(1)
                .frame(width: 300, alignment: .leading)
                .help(item.title)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .scaleEffect(isHovering && !reduceMotion ? 1.008 : 1)
        .offset(y: isHovering && !reduceMotion ? -1 : 0)
        .onHover { isHovering = $0 }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: isHovering
        )
    }
}
