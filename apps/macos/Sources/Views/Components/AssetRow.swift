import SwiftUI
import CineLarkDomain

struct AssetRow: View {
    @Environment(\.appLanguage) private var language
    let asset: MediaAsset
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(asset.displayName)
                        .font(.headline)
                    HStack(spacing: 10) {
                        if let resolution = asset.resolution {
                            Text(resolution)
                        }
                        if let encoding = asset.encoding {
                            Text(encoding.uppercased())
                        }
                        if let range = asset.videoRange {
                            Text(range.uppercased())
                        }
                        if let size = asset.fileSize {
                            Text(size.cineLarkByteCount)
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
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Label(
                    language.localized("asset.options"),
                    systemImage: "slider.horizontal.3"
                )
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Color.accentColor.opacity(isHovering ? 1 : 0.82), in: Capsule())
                .foregroundStyle(.white)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(CineLarkPressButtonStyle())
        .accessibilityHint(language.localized("asset.choose_hint"))
        .background(
            isHovering ? Color.accentColor.opacity(0.10) : Color.white.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isHovering
                        ? Color.accentColor.opacity(0.6)
                        : Color.white.opacity(0.10)
                )
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
