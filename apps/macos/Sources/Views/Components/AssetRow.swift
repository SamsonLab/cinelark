import SwiftUI
import CineLarkDomain

struct AssetRow: View {
    @Environment(\.appLanguage) private var language
    @Environment(ShortcutCoordinator.self) private var shortcuts
    let asset: MediaAsset
    let action: () -> Void
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

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
                .background(Color.accentColor.opacity(isActive ? 1 : 0.82), in: Capsule())
                .foregroundStyle(.white)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(CineLarkPressButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
        .accessibilityHint(language.localized("asset.choose_hint"))
        .background(
            isActive
                ? Color.accentColor.opacity(0.10)
                : Color.white.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .cineLarkFocusSurface(
            isActive: isActive,
            cornerRadius: 14,
            scale: 1.01
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var isActive: Bool {
        switch shortcuts.inputModality {
        case .pointer: isHovering
        case .keyboard: isFocused
        }
    }
}
