import SwiftUI
import Kingfisher

struct ArtworkView: View {
    let url: URL?
    var contentMode: SwiftUI.ContentMode = .fill
    var placeholderSystemImage = "film"

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            if let url {
                KFImage(url)
                    .targetCache(CineLarkImagePipeline.cache)
                    .setProcessor(
                        DownsamplingImageProcessor(
                            size: bucketedPixelSize(for: proxy.size)
                        )
                    )
                    .loadDiskFileSynchronously(false)
                    .fade(duration: 0.15)
                    .cancelOnDisappear(true)
                    .placeholder {
                        placeholder
                            .overlay { ProgressView().controlSize(.small) }
                    }
                    .onFailureView { placeholder }
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
    }

    private func bucketedPixelSize(for size: CGSize) -> CGSize {
        CGSize(
            width: bucket(size.width * displayScale),
            height: bucket(size.height * displayScale)
        )
    }

    private func bucket(_ value: CGFloat) -> CGFloat {
        let bucketSize: CGFloat = 128
        return min(max(ceil(value / bucketSize) * bucketSize, bucketSize), 4_096)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: placeholderSystemImage)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
        }
    }
}
