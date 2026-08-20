import SwiftUI
import CineLarkDomain

struct PlaybackOptionsView: View {
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
                    ProgressView("Loading available versions…")
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.assets.isEmpty {
                    ContentUnavailableView(
                        "No playable versions",
                        systemImage: "film.stack",
                        description: Text("The provider returned no media assets.")
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
            Button("OK", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
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
                Text("PLAYBACK OPTIONS")
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

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3.bold())
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                }
                Spacer()
            }
            .padding(18)
        }
    }

    private var versionContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Media Versions")
                    .font(.title2.bold())
                Spacer()
                Text("\(model.assets.count) available")
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
                    "Download links are short-lived and copied only when requested.",
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
                    Text("Play")
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
                            Text(duration.cineLarkDuration)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button(action: onCopyPlayback) {
                        Label("Copy Playback Link", systemImage: "doc.on.doc")
                    }
                    Button(action: onCopyDownload) {
                        Label("Copy Download Link", systemImage: "link")
                    }
                    .disabled(asset.downloadPath == nil)
                    Divider()
                    Button(action: onOpenDownload) {
                        Label("Download in Browser", systemImage: "arrow.down.circle")
                    }
                    .disabled(asset.downloadPath == nil)
                } label: {
                    if isResolvingLink {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: didCopyLink ? "checkmark" : "doc.on.doc")
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(isResolvingLink)
                .help("Playback and download links")

                Button(action: onToggleDetails) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .help(isExpanded ? "Hide version details" : "Show version details")
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
                VersionProperty(label: "Container", value: asset.container?.uppercased())
                VersionProperty(label: "Codec", value: asset.encoding?.uppercased())
                VersionProperty(label: "Profile", value: asset.profile)
                VersionProperty(label: "Dimensions", value: asset.dimensionsDescription)
                VersionProperty(label: "Frame Rate", value: asset.frameRate.map { "\($0) fps" })
                VersionProperty(label: "Pixel Format", value: asset.pixelFormat)
                VersionProperty(label: "Dynamic Range", value: asset.videoRange?.uppercased())
                VersionProperty(label: "Color", value: asset.colorDescription)
                VersionProperty(
                    label: "Video Bitrate",
                    value: asset.videoBitRate.map(\.cineLarkBitRate)
                )
                VersionProperty(
                    label: "Total Bitrate",
                    value: asset.bitRate.map(\.cineLarkBitRate)
                )
                VersionProperty(
                    label: "File Size",
                    value: asset.fileSize.map(\.cineLarkByteCount)
                )
                VersionProperty(
                    label: "Duration",
                    value: asset.durationSeconds.map(\.cineLarkDuration)
                )
            }

            if !asset.audioTracks.isEmpty {
                Text("Audio: \(asset.audioTracks.map(\.displayDescription).joined(separator: " · "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !asset.subtitleTracks.isEmpty {
                Text(
                    "Subtitles: " +
                    asset.subtitleTracks.map(\.displayDescription).joined(separator: " · ")
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
