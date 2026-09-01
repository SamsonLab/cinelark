import SwiftUI
import ComposableArchitecture
import CineLarkDomain
import CineLarkPluginAPI

struct CatalogEpisodeRow: View {
    @Environment(\.appLanguage) private var language
    @Environment(ShortcutCoordinator.self) private var shortcuts
    let episode: Episode
    let sourceID: SourceID
    let isKeyboardSelected: Bool
    let isKeyboardNavigationActive: Bool
    let onPointerSelection: (Bool) -> Void
    let play: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: play) {
            HStack(spacing: 18) {
                ArtworkView(
                    url: episode.thumbnailURL,
                    cachedPreviewSize: CGSize(width: 220, height: 124),
                    locator: MediaLocatorID(
                        sourceID: sourceID,
                        providerItemID: episode.id
                    )
                )
                .frame(width: 220, height: 124)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottom) {
                    if episode.userState.progress > 0 && !episode.userState.played {
                        ProgressView(value: episode.userState.progress)
                            .progressViewStyle(.linear)
                            .tint(CineLarkDesign.Palette.progress)
                            .padding(10)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(language.localized("episode.number", String(episode.number)))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(episode.title)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                    }

                    if let synopsis = episode.synopsis, !synopsis.isEmpty {
                        Text(synopsis)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }

                    HStack(spacing: 12) {
                        if let duration = episode.durationSeconds {
                            Text(language.duration(duration))
                        }
                        if episode.versionCount > 1 {
                            Label(
                                language.localized(
                                    episode.versionCount == 1
                                        ? "episode.version_one"
                                        : "episode.version_many",
                                    String(episode.versionCount)
                                ),
                                systemImage: "film.stack"
                            )
                            .foregroundStyle(.blue)
                        }
                        if episode.userState.played {
                            Label(
                                language.localized("episode.watched"),
                                systemImage: "checkmark.circle.fill"
                            )
                            .foregroundStyle(.green)
                        } else if episode.userState.progress > 0 {
                            Text(language.progressPercent(episode.userState.progress))
                                .foregroundStyle(.yellow)
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }

                Image(systemName: episode.hasMultipleVersions
                    ? "slider.horizontal.3"
                    : "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.primary)
                    .padding(.trailing, 8)
            }
            .padding(14)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(CineLarkPressButtonStyle())
        .focusEffectDisabled()
        .accessibilityHint(language.localized("episode.choose_hint"))
        .background(
            Color.white.opacity(isActive ? 0.10 : 0.05),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .cineLarkFocusSurface(
            isActive: isActive,
            cornerRadius: 18,
            scale: 1.01
        )
        .onHover { hovering in
            isHovering = hovering
            if !hovering || shortcuts.inputModality == .pointer {
                onPointerSelection(hovering)
            }
        }
        .onChange(of: shortcuts.inputModality) {
            if shortcuts.inputModality == .pointer, isHovering {
                onPointerSelection(true)
            }
        }
    }

    private var isActive: Bool {
        shortcuts.usesKeyboardNavigation
            ? isKeyboardNavigationActive && isKeyboardSelected
            : isHovering
    }
}

struct CatalogPlaybackOptionsView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @Environment(ShortcutCoordinator.self) private var shortcuts
    @Bindable var store: StoreOf<PlaybackOptionsFeature>
    @State private var selectedVariantID: String?
    @State private var pointerVariantID: String?
    @State private var keyboardOwner = UUID()

    private static let heroHeight: CGFloat = 260

    var body: some View {
        VStack(spacing: 0) {
            hero

            ScrollViewReader { scrollProxy in
                ScrollView {
                    bodyContent
                }
                .scrollIndicators(.visible)
                .onAppear { registerKeyboardNavigation(scrollProxy: scrollProxy) }
                .onChange(of: store.variants.map(\.id)) {
                    reconcileSelection()
                    registerKeyboardNavigation(scrollProxy: scrollProxy)
                }
            }
        }
        .frame(minWidth: 760, idealWidth: 840, maxWidth: 900)
        .frame(minHeight: 500, idealHeight: 700, maxHeight: 900)
        .background(CineLarkPageBackground())
        .task { store.send(.view(.appeared)) }
        .onDisappear {
            pointerVariantID = nil
            shortcuts.removeNavigationSurface(owner: keyboardOwner)
        }
        .alert(
            "CineLark",
            isPresented: Binding(
                get: { store.failure != nil },
                set: { if !$0 { store.send(.view(.dismissFailure)) } }
            )
        ) {
            Button(language.localized("general.dismiss"), role: .cancel) {
                store.send(.view(.dismissFailure))
            }
        } message: {
            Text(store.failure.map {
                language.userFacingError(String(describing: $0))
            } ?? "")
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkView(
                url: store.artworkURL,
                locator: store.locator
            )
            .frame(maxWidth: .infinity)
            .frame(height: Self.heroHeight)
            .clipped()
            .overlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.94)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(language.localized("playback.title"))
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(store.title)
                    .font(.system(size: 38, weight: .bold))
                    .lineLimit(2)
                    .help(store.title)
                let subtitle = playbackSubtitle
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
        .frame(height: Self.heroHeight)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title3.bold())
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(language.localized("playback.close"))
            .keyboardShortcut(.cancelAction)
            .padding(18)
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if store.isLoading && store.variants.isEmpty {
            ProgressView(language.localized("playback.loading"))
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 240)
        } else if store.variants.isEmpty {
            ContentUnavailableView(
                language.localized("playback.none"),
                systemImage: "film.stack",
                description: Text(language.localized("playback.none_description"))
            )
            .frame(maxWidth: .infinity, minHeight: 260)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(language.localized("playback.media_versions"))
                        .font(.title2.bold())
                    Spacer()
                    Text(language.localized(
                        "playback.available_count",
                        String(store.variants.count)
                    ))
                    .foregroundStyle(.secondary)
                }

                PlaybackVariantCards(
                    variants: store.variants,
                    expandedVariantID: store.expandedVariantID,
                    selectedVariantID: shortcuts.usesKeyboardNavigation
                        ? selectedVariantID
                        : nil,
                    onPlay: { store.send(.view(.variantSelected($0))) },
                    onToggleDetails: { store.send(.view(.toggleDetails($0))) },
                    onPointerSelection: updatePointerSelection,
                    scrollID: versionScrollID
                )
            }
            .padding(24)
        }
    }

    private var playbackSubtitle: String {
        [
            store.subtitle,
            store.episodeNumber.map { language.localized("episode.number", String($0)) }
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private func versionScrollID(_ variantID: String) -> String {
        "playback.version.\(variantID)"
    }

    private func registerKeyboardNavigation(scrollProxy: ScrollViewProxy) {
        let ids = store.variants.map(\.id)
        let selection = $selectedVariantID
        let pointerSelection = $pointerVariantID
        shortcuts.setNavigationSurface(
            owner: keyboardOwner,
            level: .modal,
            handlesPresentedModal: true,
            handoffToKeyboard: {
                guard let id = pointerSelection.wrappedValue, ids.contains(id) else { return }
                selection.wrappedValue = id
            },
            move: { direction in
                guard !ids.isEmpty else { return false }
                let current = shortcuts.inputModality == .pointer
                    ? pointerSelection.wrappedValue ?? selection.wrappedValue
                    : selection.wrappedValue
                let currentIndex = current.flatMap(ids.firstIndex(of:)) ?? 0
                let targetIndex: Int
                switch direction {
                case .up, .left:
                    targetIndex = max(0, currentIndex - 1)
                case .down, .right:
                    targetIndex = min(ids.count - 1, currentIndex + 1)
                }
                let id = ids[targetIndex]
                selection.wrappedValue = id
                withAnimation(.easeOut(duration: 0.2)) {
                    scrollProxy.scrollTo(versionScrollID(id), anchor: .top)
                }
                return true
            },
            activate: {
                let id = shortcuts.inputModality == .pointer
                    ? pointerSelection.wrappedValue ?? selection.wrappedValue
                    : selection.wrappedValue
                guard let id, ids.contains(id) else { return false }
                store.send(.view(.variantSelected(id)))
                return true
            },
            navigateBack: {
                dismiss()
                return true
            }
        )
    }

    private func reconcileSelection() {
        let ids = Set(store.variants.map(\.id))
        if let selectedVariantID, !ids.contains(selectedVariantID) {
            self.selectedVariantID = nil
        }
        if let pointerVariantID, !ids.contains(pointerVariantID) {
            self.pointerVariantID = nil
        }
    }

    private func updatePointerSelection(_ id: String, _ hovering: Bool) {
        if hovering {
            pointerVariantID = id
        } else if pointerVariantID == id {
            pointerVariantID = nil
        }
    }
}

struct PlaybackVariantCards: View {
    let variants: [PlaybackVariant]
    let expandedVariantID: String?
    let selectedVariantID: String?
    let onPlay: (String) -> Void
    let onToggleDetails: (String) -> Void
    let onPointerSelection: (String, Bool) -> Void
    var scrollID: ((String) -> String)?

    var body: some View {
        VStack(spacing: 12) {
            ForEach(variants) { variant in
                PlaybackVariantCard(
                    variant: variant,
                    isExpanded: expandedVariantID == variant.id,
                    isKeyboardSelected: selectedVariantID == variant.id,
                    isKeyboardNavigationActive: selectedVariantID != nil,
                    onPlay: { onPlay(variant.id) },
                    onToggleDetails: { onToggleDetails(variant.id) },
                    onPointerSelection: { onPointerSelection(variant.id, $0) }
                )
                .id(scrollID?(variant.id) ?? variant.id)
            }
        }
        .focusSection()
    }
}

private struct PlaybackVariantCard: View {
    @Environment(\.appLanguage) private var language
    @Environment(ShortcutCoordinator.self) private var shortcuts
    let variant: PlaybackVariant
    let isExpanded: Bool
    let isKeyboardSelected: Bool
    let isKeyboardNavigationActive: Bool
    let onPlay: () -> Void
    let onToggleDetails: () -> Void
    let onPointerSelection: (Bool) -> Void
    @State private var isHovering = false

    private var isActive: Bool {
        shortcuts.usesKeyboardNavigation
            ? isKeyboardNavigationActive && isKeyboardSelected
            : isHovering
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onPlay) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 8) {
                                Text(variant.displayName)
                                    .font(.headline)
                                if variant.isPreferred {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            HStack(spacing: 8) {
                                chip(variant.resolution?.uppercased())
                                chip(variant.videoRange?.uppercased())
                                chip(variant.videoCodec?.uppercased())
                                if let bitRate = variant.bitRate {
                                    Text(bitRate.cineLarkBitRate)
                                }
                                if let size = variant.fileSize {
                                    Text(size.cineLarkByteCount)
                                }
                                if let duration = variant.durationSeconds {
                                    Text(language.duration(duration))
                                }
                                Text(language.localized(
                                    "asset.audio_count",
                                    String(variant.audioTracks.count)
                                ))
                                Text(language.localized(
                                    "asset.subtitle_count",
                                    String(variant.subtitleTracks.count)
                                ))
                            }
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 12)

                        Label(language.localized("playback.play"), systemImage: "play.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 17)
                            .frame(height: 38)
                            .glassEffect(.regular.tint(.blue).interactive(), in: Capsule())
                    }
                    .padding(.leading, 18)
                    .padding(.vertical, 15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(CineLarkPressButtonStyle())
                .focusEffectDisabled()
                .accessibilityLabel(language.localized(
                    "playback.play_version",
                    variant.displayName
                ))

                Button(action: onToggleDetails) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .frame(width: 42, height: 42)
                        .cineLarkHoverSurface(cornerRadius: 11)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityLabel(language.localized(
                    isExpanded ? "playback.hide_details" : "playback.show_details"
                ))
                .padding(.trailing, 12)
            }

            if isExpanded {
                Divider()
                versionDetails.padding(16)
            }
        }
        .background(
            Color.white.opacity(isActive ? 0.09 : 0.04),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .cineLarkFocusSurface(isActive: isActive, cornerRadius: 16, scale: 1.008)
        .cineLarkKeyboardSelectionHint(isActive: isKeyboardSelected)
        .onHover { hovering in
            isHovering = hovering
            if !hovering || shortcuts.inputModality == .pointer {
                onPointerSelection(hovering)
            }
        }
        .onChange(of: shortcuts.inputModality) {
            if shortcuts.inputModality == .pointer, isHovering {
                onPointerSelection(true)
            }
        }
        .onDisappear {
            if isHovering { onPointerSelection(false) }
        }
    }

    private var versionDetails: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), alignment: .leading),
                    count: 3
                ),
                alignment: .leading,
                spacing: 14
            ) {
                VersionProperty(
                    label: language.localized("playback.container"),
                    value: variant.container?.uppercased()
                )
                VersionProperty(
                    label: language.localized("playback.codec"),
                    value: variant.videoCodec?.uppercased()
                )
                VersionProperty(
                    label: language.localized("playback.profile"),
                    value: variant.videoProfile
                )
                VersionProperty(
                    label: language.localized("playback.dimensions"),
                    value: variant.dimensionsDescription
                )
                VersionProperty(
                    label: language.localized("playback.frame_rate"),
                    value: variant.frameRate.map {
                        $0.formatted(.number.precision(.fractionLength(0...3))) + " fps"
                    }
                )
                VersionProperty(
                    label: language.localized("playback.pixel_format"),
                    value: variant.pixelFormat
                )
                VersionProperty(
                    label: language.localized("playback.dynamic_range"),
                    value: variant.videoRange?.uppercased()
                )
                VersionProperty(
                    label: language.localized("playback.color"),
                    value: variant.colorDescription
                )
                VersionProperty(
                    label: language.localized("playback.video_bitrate"),
                    value: variant.videoBitRate.map(\.cineLarkBitRate)
                )
                VersionProperty(
                    label: language.localized("playback.total_bitrate"),
                    value: variant.bitRate.map(\.cineLarkBitRate)
                )
                VersionProperty(
                    label: language.localized("playback.file_size"),
                    value: variant.fileSize.map(\.cineLarkByteCount)
                )
                VersionProperty(
                    label: language.localized("playback.duration"),
                    value: variant.durationSeconds.map(language.duration)
                )
            }

            if !variant.audioTracks.isEmpty {
                Text(language.localized(
                    "playback.audio",
                    variant.audioTracks.map(\.displayDescription).joined(separator: " · ")
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if !variant.subtitleTracks.isEmpty {
                Text(language.localized(
                    "playback.subtitles",
                    variant.subtitleTracks.map(\.displayDescription).joined(separator: " · ")
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func chip(_ value: String?) -> some View {
        if let value, !value.isEmpty {
            Text(value)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.6))
                }
        }
    }
}

private struct VersionProperty: View {
    let label: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value ?? "—")
                .font(.callout)
                .textSelection(.enabled)
        }
    }
}

private extension Int64 {
    var cineLarkBitRate: String {
        let megabits = Double(self) / 1_000_000
        return megabits.formatted(.number.precision(.fractionLength(1))) + " Mbps"
    }
}

private extension PlaybackVariant {
    var resolution: String? {
        guard let height else { return nil }
        return "\(height)p"
    }

    var dimensionsDescription: String? {
        guard let width, let height else { return resolution }
        return "\(width) × \(height)"
    }

    var colorDescription: String? {
        [colorSpace, colorTransfer, colorPrimaries]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            .nilIfEmpty
    }
}

private extension AudioTrack {
    var displayDescription: String {
        [language, title, codec?.uppercased(), channels.map { "\($0)ch" }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension SubtitleTrack {
    var displayDescription: String {
        [language, title, codec?.uppercased()]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
