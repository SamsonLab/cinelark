import SwiftUI
import CineLarkDomain

struct ContinueWatchingShelf: View {
    @Environment(\.appLanguage) private var language
    @Bindable var model: AppModel
    let onHighlight: ((ContinueWatchingItem) -> Void)?

    init(
        model: AppModel,
        onHighlight: ((ContinueWatchingItem) -> Void)? = nil
    ) {
        self.model = model
        self.onHighlight = onHighlight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.localized("home.continue_watching"))
                .font(.system(size: 26, weight: .semibold))
                .padding(.horizontal, CineLarkTheme.contentMargin)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 26) {
                    ForEach(model.continueWatching) { item in
                        ContinueWatchingCard(
                            item: item,
                            isPlaying: model.playingItemID == item.id,
                            isPlaybackDisabled: model.playingItemID != nil,
                            onHighlight: onHighlight
                        ) {
                            Task { await model.play(item) }
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 26)
            }
            .contentMargins(.horizontal, CineLarkTheme.contentMargin, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .focusSection()
        }
    }
}

private struct ContinueWatchingCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appLanguage) private var language
    let item: ContinueWatchingItem
    let isPlaying: Bool
    let isPlaybackDisabled: Bool
    let onHighlight: ((ContinueWatchingItem) -> Void)?
    let play: () -> Void
    @State private var isHovering = false
    @FocusState private var isPlayFocused: Bool
    @FocusState private var isDetailFocused: Bool

    private var isActive: Bool {
        isHovering || isPlayFocused || isDetailFocused
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Button(action: play) {
                artwork
            }
            .buttonStyle(CineLarkPressButtonStyle())
            .focused($isPlayFocused)
            .focusEffectDisabled()
            .disabled(isPlaybackDisabled)
            .accessibilityLabel(language.localized("home.continue_playback", item.title))

            NavigationLink(value: item.mediaSummary) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isDetailFocused ? .white : .primary)
                        .lineLimit(1)
                        .help(item.title)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(width: CineLarkTheme.landscapeWidth, alignment: .topLeading)
                .frame(minHeight: 38, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($isDetailFocused)
            .focusEffectDisabled()
            .accessibilityLabel(
                [item.title, item.subtitle]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            )
            .accessibilityHint(language.localized("home.open_details"))
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering { onHighlight?(item) }
        }
        .onChange(of: isPlayFocused) {
            if isPlayFocused { onHighlight?(item) }
        }
        .onChange(of: isDetailFocused) {
            if isDetailFocused { onHighlight?(item) }
        }
    }

    private var artwork: some View {
        ZStack {
            ArtworkView(url: item.thumbnailURL ?? item.posterURL)
                .frame(
                    width: CineLarkTheme.landscapeWidth,
                    height: CineLarkTheme.landscapeHeight
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: CineLarkTheme.cardRadius,
                        style: .continuous
                    )
                )

            playControl
                .offset(x: isPlaying ? 0 : 2)
        }
        .overlay(alignment: .bottom) {
            ProgressView(value: item.userState.progress)
                .progressViewStyle(.linear)
                .tint(.blue)
                .padding(10)
        }
        .contentShape(
            RoundedRectangle(cornerRadius: CineLarkTheme.cardRadius, style: .continuous)
        )
        .cineLarkCardLift(
            isActive: isActive,
            cornerRadius: CineLarkTheme.cardRadius,
            scale: reduceMotion ? 1 : 1.04
        )
    }

    @ViewBuilder
    private var playControl: some View {
        let icon = Image(systemName: isPlaying ? "hourglass" : "play.fill")
            .font(.system(size: 21, weight: .semibold))
            .frame(width: 54, height: 54)

        if isActive {
            icon.glassEffect(
                .regular.tint(.white.opacity(0.28)).interactive(),
                in: Circle()
            )
        } else {
            icon
                .background(Color.black.opacity(0.52), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                }
        }
    }
}
