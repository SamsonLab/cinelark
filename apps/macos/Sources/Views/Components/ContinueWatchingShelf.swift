import SwiftUI
import CineLarkDomain

struct ContinueWatchingShelf: View {
    @Environment(\.appLanguage) private var language
    @Bindable var model: AppModel
    let headingID: String?
    let selectedItemID: String?
    let isKeyboardNavigationActive: Bool
    let onPointerSelection: ((ContinueWatchingItem, Bool) -> Void)?
    let onHighlight: ((ContinueWatchingItem) -> Void)?

    init(
        model: AppModel,
        headingID: String? = nil,
        selectedItemID: String? = nil,
        isKeyboardNavigationActive: Bool = false,
        onPointerSelection: ((ContinueWatchingItem, Bool) -> Void)? = nil,
        onHighlight: ((ContinueWatchingItem) -> Void)? = nil
    ) {
        self.model = model
        self.headingID = headingID
        self.selectedItemID = selectedItemID
        self.isKeyboardNavigationActive = isKeyboardNavigationActive
        self.onPointerSelection = onPointerSelection
        self.onHighlight = onHighlight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: CineLarkDesign.Layout.shelfSpacing) {
                        ForEach(model.continueWatching) { item in
                            PlaybackLandscapeLockup(
                                item: item,
                                isPlaying: model.playingItemID == item.id,
                                isPlaybackDisabled: model.playingItemID != nil,
                                prefersInitialFocus: item.id == model.continueWatching.first?.id,
                                isKeyboardSelected: selectedItemID == item.id,
                                isKeyboardNavigationActive: isKeyboardNavigationActive,
                                onPointerSelection: onPointerSelection,
                                onHighlight: onHighlight
                            ) {
                                Task { await model.play(item) }
                            }
                            .id(item.id)
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
                .onChange(of: selectedItemID) {
                    guard let selectedItemID else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollProxy.scrollTo(selectedItemID, anchor: .leading)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var heading: some View {
        let title = Text(language.localized("home.continue_watching"))
            .font(CineLarkDesign.Typography.sectionTitle)
            .padding(.horizontal, CineLarkDesign.Layout.contentMargin)

        if let headingID {
            title.id(headingID)
        } else {
            title
        }
    }
}

private struct PlaybackLandscapeLockup: View {
    @Environment(\.appLanguage) private var language
    @Environment(ShortcutCoordinator.self) private var shortcuts
    let item: ContinueWatchingItem
    let isPlaying: Bool
    let isPlaybackDisabled: Bool
    let prefersInitialFocus: Bool
    let isKeyboardSelected: Bool
    let isKeyboardNavigationActive: Bool
    let onPointerSelection: ((ContinueWatchingItem, Bool) -> Void)?
    let onHighlight: ((ContinueWatchingItem) -> Void)?
    let play: () -> Void
    @State private var isHovering = false
    @FocusState private var isPlayFocused: Bool
    @FocusState private var isDetailFocused: Bool

    private var isActive: Bool {
        switch shortcuts.inputModality {
        case .pointer:
            isHovering
        case .keyboard:
            isKeyboardSelected ||
                (!isKeyboardNavigationActive && (isPlayFocused || isDetailFocused))
        }
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
            if !hovering || shortcuts.inputModality == .pointer {
                onPointerSelection?(item, hovering)
            }
            if hovering, shortcuts.inputModality == .pointer {
                onHighlight?(item)
            }
        }
        .onChange(of: shortcuts.inputModality) {
            if shortcuts.inputModality == .pointer, isHovering {
                onPointerSelection?(item, true)
                onHighlight?(item)
            }
        }
        .onDisappear {
            if isHovering { onPointerSelection?(item, false) }
        }
        .onChange(of: isPlayFocused) {
            if isPlayFocused { onHighlight?(item) }
        }
        .onChange(of: isDetailFocused) {
            if isDetailFocused { onHighlight?(item) }
        }
        .defaultFocus(
            $isPlayFocused,
            prefersInitialFocus && !isPlaybackDisabled,
            priority: .userInitiated
        )
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
        .cineLarkKeyboardSelectionHint(isActive: isKeyboardSelected)
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
