import SwiftUI
import Kingfisher
import CineLarkPluginAPI

struct ArtworkView: View {
    let url: URL?
    var contentMode: SwiftUI.ContentMode = .fill
    var placeholderSystemImage = "film"
    var cachedPreviewSize: CGSize?
    var locator: MediaLocatorID?
    var artworkKind = "primary"

    @Environment(\.displayScale) private var displayScale
    @Environment(\.artworkResolutionClient) private var artworkResolver

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                unavailablePlaceholder(size: proxy.size)

                if let url {
                    KFImage(source: imageSource(url))
                        .targetCache(CineLarkImagePipeline.cache)
                        .cacheOriginalImage()
                        .requestModifier(requestModifier)
                        .redirectHandler(redirectHandler)
                        .setProcessor(
                            DownsamplingImageProcessor(
                                size: bucketedPixelSize(for: proxy.size)
                            )
                        )
                        .loadDiskFileSynchronously(false)
                        .fade(duration: 0.15)
                        .startLoadingBeforeViewAppear()
                        .cancelOnDisappear(true)
                        .reducePriorityOnDisappear(true)
                        .placeholder {
                            if let cachedPreviewSize {
                                cachedPreview(
                                    url: url,
                                    sourceSize: cachedPreviewSize,
                                    displaySize: proxy.size
                                )
                            } else {
                                loadingPlaceholder(size: proxy.size)
                            }
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

    private func cachedPreview(
        url: URL,
        sourceSize: CGSize,
        displaySize: CGSize
    ) -> some View {
        KFImage(source: imageSource(url))
            .targetCache(CineLarkImagePipeline.cache)
            .requestModifier(requestModifier)
            .redirectHandler(redirectHandler)
            .setProcessor(
                DownsamplingImageProcessor(
                    size: bucketedPixelSize(for: sourceSize)
                )
            )
            .loadDiskFileSynchronously(true)
            .startLoadingBeforeViewAppear()
            .placeholder {
                loadingPlaceholder(size: displaySize)
            }
            .resizable()
            .aspectRatio(contentMode: contentMode)
            .frame(width: displaySize.width, height: displaySize.height)
            .clipped()
    }

    private var reference: ArtworkRequestReference? {
        locator.map { ArtworkRequestReference(locator: $0, kind: artworkKind) }
    }

    private var requestModifier: ArtworkRequestModifier {
        ArtworkRequestModifier(reference: reference, resolver: artworkResolver)
    }

    private var redirectHandler: ArtworkRedirectHandler {
        ArtworkRedirectHandler(enforcesSameOrigin: reference != nil)
    }

    private func imageSource(_ url: URL) -> Source {
        let resource = KF.ImageResource(
            downloadURL: url,
            cacheKey: reference.map {
                ArtworkRequestPolicy.cacheKey(reference: $0, fallbackURL: url)
            }
        )
        return .network(resource)
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
