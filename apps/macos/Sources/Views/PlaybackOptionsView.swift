import AppKit
import SwiftUI
import CineLarkDomain

struct PlaybackOptionsView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @Environment(ShortcutCoordinator.self) private var shortcuts
    @State private var model: PlaybackOptionsModel
    @State private var bodyContentHeight: CGFloat = 220
    @State private var selectedAssetID: String?
    @State private var pointerSelectedAssetID: String?
    @State private var keyboardOwner = UUID()

    private static let heroHeight: CGFloat = 260

    init(context: PlaybackOptionsContext, playback: PlaybackCoordinator) {
        _model = State(
            initialValue: PlaybackOptionsModel(
                context: context,
                playback: playback
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            hero

            ScrollViewReader { scrollProxy in
                ScrollView {
                    bodyContent
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: PlaybackOptionsContentHeightKey.self,
                                    value: geometry.size.height
                                )
                            }
                        }
                }
                .scrollIndicators(.visible)
                .onAppear {
                    registerKeyboardNavigation(scrollProxy: scrollProxy)
                }
                .onChange(of: model.assets.map(\.id)) {
                    if let selectedAssetID,
                       !model.assets.contains(where: { $0.id == selectedAssetID }) {
                        self.selectedAssetID = nil
                    }
                    if let pointerSelectedAssetID,
                       !model.assets.contains(where: { $0.id == pointerSelectedAssetID }) {
                        self.pointerSelectedAssetID = nil
                    }
                    registerKeyboardNavigation(scrollProxy: scrollProxy)
                }
            }
        }
        .frame(minWidth: 760, idealWidth: 840, maxWidth: 900)
        .frame(height: dialogHeight)
        .background(CineLarkPageBackground())
        .onPreferenceChange(PlaybackOptionsContentHeightKey.self) { height in
            guard height > 0 else { return }
            bodyContentHeight = height
        }
        .task {
            await model.load()
        }
        .onDisappear {
            pointerSelectedAssetID = nil
            shortcuts.removeNavigationSurface(owner: keyboardOwner)
        }
        .alert(
            "CineLark",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.dismissError() } }
            )
        ) {
            Button(language.localized("general.dismiss"), role: .cancel) { model.dismissError() }
        } message: {
            Text(language.userFacingError(model.errorMessage))
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if model.isLoading && model.assets.isEmpty {
            ProgressView(language.localized("playback.loading"))
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 200)
        } else if model.assets.isEmpty {
            ContentUnavailableView(
                language.localized("playback.none"),
                systemImage: "film.stack",
                description: Text(language.localized("playback.none_description"))
            )
            .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            versionContent
        }
    }

    private var dialogHeight: CGFloat {
        min(Self.heroHeight + bodyContentHeight, maximumDialogHeight)
    }

    private var maximumDialogHeight: CGFloat {
        let availableHeight = NSScreen.main?.visibleFrame.height ?? 900
        return max(480, min(900, availableHeight - 80))
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkView(
                url: model.context.artworkURL,
                cachedPreviewSize: model.context.artworkPreviewSize
            )
                .frame(maxWidth: .infinity)
                .frame(height: Self.heroHeight)
                .clipped()
                .overlay {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.18)
                }
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.92)],
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
                Text(model.context.title)
                    .font(.system(size: 38, weight: .bold))
                    .lineLimit(2)
                    .help(model.context.title)
                if let subtitle = model.context.subtitle {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
        .frame(height: Self.heroHeight)
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
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

    private var versionContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(language.localized("playback.media_versions"))
                    .font(.title2.bold())
                Spacer()
                Text(
                    language.localized("playback.available_count", String(model.assets.count))
                )
                    .foregroundStyle(.secondary)
            }

            PlaybackVersionCards(
                model: model,
                selectedAssetID: shortcuts.usesKeyboardNavigation
                    ? selectedAssetID
                    : nil,
                onPointerSelection: updatePointerSelection,
                scrollID: versionScrollID,
                onPlayed: { dismiss() }
            )
        }
        .padding(24)
    }

    private func versionScrollID(_ assetID: String) -> String {
        "playback.version.\(assetID)"
    }

    private func registerKeyboardNavigation(scrollProxy: ScrollViewProxy) {
        let assetIDs = model.assets.map(\.id)
        let selection = $selectedAssetID
        let pointerSelection = $pointerSelectedAssetID
        shortcuts.setNavigationSurface(
            owner: keyboardOwner,
            handlesPresentedModal: true,
            handoffToKeyboard: {
                guard let pointerAssetID = pointerSelection.wrappedValue,
                      assetIDs.contains(pointerAssetID) else {
                    return
                }
                selection.wrappedValue = pointerAssetID
            },
            move: { direction in
                guard !assetIDs.isEmpty else { return false }
                let currentSelection = shortcuts.inputModality == .pointer
                    ? pointerSelection.wrappedValue ?? selection.wrappedValue
                    : selection.wrappedValue
                guard let currentID = currentSelection,
                      let currentIndex = assetIDs.firstIndex(of: currentID) else {
                    selectAsset(assetIDs[0], selection: selection, scrollProxy: scrollProxy)
                    return true
                }
                let targetIndex: Int
                switch direction {
                case .up, .left:
                    targetIndex = max(0, currentIndex - 1)
                case .down, .right:
                    targetIndex = min(assetIDs.count - 1, currentIndex + 1)
                }
                selectAsset(
                    assetIDs[targetIndex],
                    selection: selection,
                    scrollProxy: scrollProxy
                )
                return true
            },
            activate: {
                let currentSelection = shortcuts.inputModality == .pointer
                    ? pointerSelection.wrappedValue ?? selection.wrappedValue
                    : selection.wrappedValue
                guard let selectedAssetID = currentSelection,
                      let asset = model.assets.first(where: { $0.id == selectedAssetID }),
                      model.playingAssetID == nil else {
                    return false
                }
                Task {
                    if await model.play(asset) {
                        dismiss()
                    }
                }
                return true
            },
            navigateBack: {
                dismiss()
                return true
            }
        )
    }

    private func selectAsset(
        _ assetID: String,
        selection: Binding<String?>,
        scrollProxy: ScrollViewProxy
    ) {
        withAnimation(.easeOut(duration: 0.2)) {
            selection.wrappedValue = assetID
            scrollProxy.scrollTo(versionScrollID(assetID), anchor: .top)
        }
    }

    private func updatePointerSelection(_ assetID: String, _ hovering: Bool) {
        if hovering {
            pointerSelectedAssetID = assetID
        } else if pointerSelectedAssetID == assetID {
            pointerSelectedAssetID = nil
        }
    }
}

private struct PlaybackOptionsContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct PlaybackVersionCards: View {
    @Bindable var model: PlaybackOptionsModel
    var selectedAssetID: String?
    var onPointerSelection: ((String, Bool) -> Void)?
    var scrollID: ((String) -> String)?
    var onPlayed: (() -> Void)?

    init(
        model: PlaybackOptionsModel,
        selectedAssetID: String? = nil,
        onPointerSelection: ((String, Bool) -> Void)? = nil,
        scrollID: ((String) -> String)? = nil,
        onPlayed: (() -> Void)? = nil
    ) {
        self.model = model
        self.selectedAssetID = selectedAssetID
        self.onPointerSelection = onPointerSelection
        self.scrollID = scrollID
        self.onPlayed = onPlayed
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(model.assets) { asset in
                PlaybackVersionCard(
                    asset: asset,
                    isExpanded: model.expandedAssetID == asset.id,
                    isPlaying: model.playingAssetID == asset.id,
                    isKeyboardSelected: selectedAssetID == asset.id,
                    isKeyboardNavigationActive: selectedAssetID != nil,
                    onPointerSelection: { hovering in
                        onPointerSelection?(asset.id, hovering)
                    },
                    isResolvingLink: model.resolvingLinkAssetID == asset.id,
                    didCopyLink: model.copiedLinkAssetID == asset.id,
                    onPlay: {
                        Task {
                            if await model.play(asset) {
                                onPlayed?()
                            }
                        }
                    },
                    onToggleDetails: { model.toggleDetails(for: asset) },
                    onCopyPlayback: {
                        Task { await model.copyPlaybackLink(for: asset) }
                    },
                    onCopyDownload: {
                        Task { await model.copyDownloadLink(for: asset) }
                    },
                    onOpenDownload: {
                        Task { await model.openDownload(for: asset) }
                    }
                )
                .id(scrollID?(asset.id) ?? asset.id)
            }
        }
        .focusSection()
    }
}

struct PlaybackVersionCard: View {
    @Environment(\.appLanguage) private var language
    @Environment(ShortcutCoordinator.self) private var shortcuts
    let asset: MediaAsset
    let isExpanded: Bool
    let isPlaying: Bool
    let isKeyboardSelected: Bool
    let isKeyboardNavigationActive: Bool
    let onPointerSelection: (Bool) -> Void
    let isResolvingLink: Bool
    let didCopyLink: Bool
    let onPlay: () -> Void
    let onToggleDetails: () -> Void
    let onCopyPlayback: () -> Void
    let onCopyDownload: () -> Void
    let onOpenDownload: () -> Void

    @State private var isHovering = false
    @FocusState private var isPlayFocused: Bool
    @FocusState private var isDetailsFocused: Bool

    private var isActive: Bool {
        switch shortcuts.inputModality {
        case .pointer:
            isHovering
        case .keyboard:
            isKeyboardSelected ||
                (!isKeyboardNavigationActive && (isPlayFocused || isDetailsFocused))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onPlay) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(asset.displayName)
                                .font(.headline)
                            HStack(spacing: 8) {
                                chip(asset.resolution?.uppercased())
                                chip(asset.videoRange?.uppercased())
                                chip(asset.encoding?.uppercased())
                                if let bitRate = asset.bitRate {
                                    Text(bitRate.cineLarkBitRate)
                                }
                                if let size = asset.fileSize {
                                    Text(size.cineLarkByteCount)
                                }
                                if let duration = asset.durationSeconds {
                                    Text(language.duration(duration))
                                }
                                Text(
                                    language.localized(
                                        "asset.audio_count",
                                        String(asset.audioTracks.count)
                                    )
                                )
                                Text(
                                    language.localized(
                                        "asset.subtitle_count",
                                        String(asset.subtitleTracks.count)
                                    )
                                )
                            }
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 12)

                        HStack(spacing: 8) {
                            if isPlaying {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(language.localized("playback.play"))
                        }
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 17)
                        .frame(height: 38)
                        .glassEffect(
                            .regular.tint(.blue).interactive(),
                            in: Capsule()
                        )
                    }
                    .padding(.leading, 18)
                    .padding(.vertical, 15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(CineLarkPressButtonStyle())
                .focused($isPlayFocused)
                .focusEffectDisabled()
                .disabled(isPlaying)
                .accessibilityLabel(
                    language.localized("playback.play_version", asset.displayName)
                )

                Button(action: onToggleDetails) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .frame(width: 42, height: 42)
                        .cineLarkHoverSurface(cornerRadius: 11)
                }
                .buttonStyle(.plain)
                .focused($isDetailsFocused)
                .focusEffectDisabled()
                .accessibilityLabel(
                    language.localized(
                        isExpanded
                            ? "playback.hide_details"
                            : "playback.show_details"
                    )
                )
                .help(
                    language.localized(
                        isExpanded
                            ? "playback.hide_details"
                            : "playback.show_details"
                    )
                )
                .padding(.trailing, 12)
            }

            if isExpanded {
                Divider()
                versionDetails
                    .padding(16)
            }
        }
        .background(
            isActive ? Color.white.opacity(0.09) : Color.white.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .cineLarkFocusSurface(
            isActive: isActive,
            cornerRadius: 16,
            scale: 1.008
        )
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
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var versionDetails: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
                alignment: .leading,
                spacing: 14
            ) {
                VersionProperty(
                    label: language.localized("playback.container"),
                    value: asset.container?.uppercased()
                )
                VersionProperty(
                    label: language.localized("playback.codec"),
                    value: asset.encoding?.uppercased()
                )
                VersionProperty(
                    label: language.localized("playback.profile"),
                    value: asset.profile
                )
                VersionProperty(
                    label: language.localized("playback.dimensions"),
                    value: asset.dimensionsDescription
                )
                VersionProperty(
                    label: language.localized("playback.frame_rate"),
                    value: asset.frameRate.map { "\($0) fps" }
                )
                VersionProperty(
                    label: language.localized("playback.pixel_format"),
                    value: asset.pixelFormat
                )
                VersionProperty(
                    label: language.localized("playback.dynamic_range"),
                    value: asset.videoRange?.uppercased()
                )
                VersionProperty(
                    label: language.localized("playback.color"),
                    value: asset.colorDescription
                )
                VersionProperty(
                    label: language.localized("playback.video_bitrate"),
                    value: asset.videoBitRate.map(\.cineLarkBitRate)
                )
                VersionProperty(
                    label: language.localized("playback.total_bitrate"),
                    value: asset.bitRate.map(\.cineLarkBitRate)
                )
                VersionProperty(
                    label: language.localized("playback.file_size"),
                    value: asset.fileSize.map(\.cineLarkByteCount)
                )
                VersionProperty(
                    label: language.localized("playback.duration"),
                    value: asset.durationSeconds.map(language.duration)
                )
            }

            if !asset.audioTracks.isEmpty {
                Text(
                    language.localized(
                        "playback.audio",
                        asset.audioTracks.map(\.displayDescription).joined(separator: " · ")
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !asset.subtitleTracks.isEmpty {
                Text(
                    language.localized(
                        "playback.subtitles",
                        asset.subtitleTracks.map(\.displayDescription).joined(separator: " · ")
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 10) {
                Button(action: onCopyPlayback) {
                    Label(
                        language.localized("playback.copy_playback"),
                        systemImage: didCopyLink ? "checkmark" : "doc.on.doc"
                    )
                }
                Button(action: onCopyDownload) {
                    Label(
                        language.localized("playback.copy_download"),
                        systemImage: "link"
                    )
                }
                .disabled(asset.downloadPath == nil)
                Button(action: onOpenDownload) {
                    Label(
                        language.localized("playback.open_download"),
                        systemImage: "arrow.down.circle"
                    )
                }
                .disabled(asset.downloadPath == nil)
                if isResolvingLink {
                    ProgressView().controlSize(.small)
                }
            }
            .buttonStyle(.glass)
            .disabled(isResolvingLink)

            Label(
                language.localized("playback.download_notice"),
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
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

private extension MediaAsset {
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
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
