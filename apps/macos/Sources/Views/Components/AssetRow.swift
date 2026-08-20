import SwiftUI
import CineLarkDomain

struct AssetRow: View {
    let asset: MediaAsset
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
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
                    Text("\(asset.audioTracks.count) audio")
                    Text("\(asset.subtitleTracks.count) subtitles")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: action) {
                HStack {
                    if isPlaying {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text("Play")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPlaying)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
