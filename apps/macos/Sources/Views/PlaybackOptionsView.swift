import SwiftUI
import CineLarkDomain

struct PlaybackOptionsView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlaybackOptionsModel

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
            Divider()

            Group {
                if model.isLoading && model.assets.isEmpty {
                    ProgressView(language.localized("playback.loading"))
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.assets.isEmpty {
                    ContentUnavailableView(
                        language.localized("playback.none"),
                        systemImage: "film.stack",
                        description: Text(language.localized("playback.none_description"))
                    )
                } else {
                    versionContent
                }
            }
        }
        .frame(minWidth: 760, idealWidth: 840, minHeight: 680, idealHeight: 820)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await model.load()
        }
        .alert(
            "CineLark",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.dismissError() } }
            )
        ) {
            Button(language.localized("general.ok"), role: .cancel) { model.dismissError() }
        } message: {
            Text(language.userFacingError(model.errorMessage))
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkView(url: model.context.artworkURL)
                .frame(maxWidth: .infinity)
                .frame(height: 260)
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
                    .foregroundStyle(.orange)
                Text(model.context.title)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .lineLimit(2)
                if let subtitle = model.context.subtitle {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
        .frame(height: 260)
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.bold())
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
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

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.assets) { asset in
                        VersionCard(
                            asset: asset,
                            isSelected: model.selectedAssetID == asset.id,
                            isExpanded: model.expandedAssetID == asset.id,
                            isResolvingLink: model.resolvingLinkAssetID == asset.id,
                            didCopyLink: model.copiedLinkAssetID == asset.id,
                            onSelect: { model.select(asset) },
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
                    }
                }
            }
            .scrollIndicators(.visible)

            HStack {
                Label(
                    language.localized("playback.download_notice"),
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
            }

            Button {
                Task {
                    if await model.playSelected() {
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if model.isPlaying {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(language.localized("playback.play"))
                    if let selectedAsset = model.selectedAsset {
                        Text("· \(selectedAsset.displayName)")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.selectedAsset == nil || model.isPlaying)
        }
        .padding(24)
    }
}

private struct VersionCard: View {
    @Environment(\.appLanguage) private var language
    let asset: MediaAsset
    let isSelected: Bool
    let isExpanded: Bool
    let isResolvingLink: Bool
    let didCopyLink: Bool
    let onSelect: () -> Void
    let onToggleDetails: () -> Void
    let onCopyPlayback: () -> Void
    let onCopyDownload: () -> Void
    let onOpenDownload: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "record.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .orange : .secondary)
                    .font(.title3)

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
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button(action: onCopyPlayback) {
                        Label(
                            language.localized("playback.copy_playback"),
                            systemImage: "doc.on.doc"
                        )
                    }
                    Button(action: onCopyDownload) {
                        Label(
                            language.localized("playback.copy_download"),
                            systemImage: "link"
                        )
                    }
                    .disabled(asset.downloadPath == nil)
                    Divider()
                    Button(action: onOpenDownload) {
                        Label(
                            language.localized("playback.open_download"),
                            systemImage: "arrow.down.circle"
                        )
                    }
                    .disabled(asset.downloadPath == nil)
                } label: {
                    Group {
                        if isResolvingLink {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: didCopyLink ? "checkmark" : "doc.on.doc")
                        }
                    }
                    .frame(width: 34, height: 32)
                    .cineLarkHoverSurface(cornerRadius: 9)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(isResolvingLink)
                .help(language.localized("playback.link_help"))

                Button(action: onToggleDetails) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .frame(width: 42, height: 32)
                        .cineLarkHoverSurface(cornerRadius: 9)
                }
                .buttonStyle(.plain)
                .help(
                    language.localized(
                        isExpanded
                            ? "playback.hide_details"
                            : "playback.show_details"
                    )
                )
            }
            .padding(16)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)

            if isExpanded {
                Divider()
                versionDetails
                    .padding(16)
            }
        }
        .background(
            isSelected ? Color.orange.opacity(0.10) : Color.white.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected ? Color.orange.opacity(0.8) : Color.white.opacity(0.10),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
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
