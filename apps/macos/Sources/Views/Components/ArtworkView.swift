import SwiftUI
import Kingfisher

struct ArtworkView: View {
    let url: URL?
    var contentMode: SwiftUI.ContentMode = .fill
    var placeholderSystemImage = "film"

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                unavailablePlaceholder(size: proxy.size)

                if let url {
                    KFImage(url)
                        .targetCache(CineLarkImagePipeline.cache)
                        .cacheOriginalImage()
                        .setProcessor(
                            DownsamplingImageProcessor(
                                size: bucketedPixelSize(for: proxy.size)
                            )
                        )
                        .loadDiskFileSynchronously(false)
                        .fade(duration: 0.15)
                        .startLoadingBeforeViewAppear()
                        // Finish off-screen requests so scrolling warms the disk cache.
                        .cancelOnDisappear(false)
                        .reducePriorityOnDisappear(true)
                        .placeholder {
                            loadingPlaceholder(size: proxy.size)
                        }
                        .onFailureView {
                            unavailablePlaceholder(size: proxy.size)
                        }
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height
                        )
                        .clipped()
                }
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height
            )
            .clipped()
        }
        .accessibilityHidden(true)
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

    private func loadingPlaceholder(size: CGSize) -> some View {
        placeholderBackground
            .overlay {
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)
            }
            .frame(width: size.width, height: size.height)
    }

    private func unavailablePlaceholder(size: CGSize) -> some View {
        placeholderBackground
            .overlay {
                Image(systemName: placeholderSystemImage)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: size.width, height: size.height)
    }

    private var placeholderBackground: some View {
        LinearGradient(
            colors: [Color.white.opacity(0.11), Color.white.opacity(0.035)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
