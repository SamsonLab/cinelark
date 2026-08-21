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
                .font(CineLarkDesign.Typography.sectionTitle)
                .padding(.horizontal, CineLarkDesign.Layout.contentMargin)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: CineLarkDesign.Layout.shelfSpacing) {
                    ForEach(model.continueWatching) { item in
                        PlaybackLandscapeLockup(
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
            .contentMargins(
                .horizontal,
                CineLarkDesign.Layout.contentMargin,
                for: .scrollContent
            )
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .focusSection()
        }
    }
}

private struct PlaybackLandscapeLockup: View {
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
        VStack(alignment: .leading, spacing: CineLarkDesign.Layout.lockupSpacing) {
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
                        .font(CineLarkDesign.Typography.cardTitle)
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
                .frame(width: CineLarkDesign.Media.landscapeWidth, alignment: .topLeading)
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
            MediaArtworkSurface(
                item: item.mediaSummary,
                url: item.thumbnailURL ?? item.posterURL,
                size: CGSize(
                    width: CineLarkDesign.Media.landscapeWidth,
                    height: CineLarkDesign.Media.landscapeHeight
                ),
                role: .playback
            )

            playControl
                .offset(x: isPlaying ? 0 : 2)
        }
        .contentShape(
            RoundedRectangle(
                cornerRadius: CineLarkDesign.Shape.cardRadius,
                style: .continuous
            )
        )
        .cineLarkFocusSurface(
            isActive: isActive,
            cornerRadius: CineLarkDesign.Shape.cardRadius,
            scale: 1.04
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
                .background(CineLarkDesign.Palette.badgeBackground, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(CineLarkDesign.Palette.badgeStroke, lineWidth: 0.75)
                }
        }
    }
}
