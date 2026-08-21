import SwiftUI
import CineLarkDomain

struct MediaDetailRoute: Hashable {
    let item: MediaSummary
    let transitionID: UUID
}

struct MediaCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appLanguage) private var language
    @Environment(\.mediaTransitionNamespace) private var transitionNamespace
    let item: MediaSummary
    let transitionID: UUID?
    @State private var isHovering = false

    init(item: MediaSummary, transitionID: UUID? = nil) {
        self.item = item
        self.transitionID = transitionID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArtworkView(url: item.posterURL)
                .frame(width: 178, height: 267)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .mediaMatchedGeometry(
                    id: transitionID,
                    namespace: transitionNamespace,
                    isSource: true
                )
                .overlay(alignment: .bottom) {
                    if item.userState.progress > 0 && !item.userState.played {
                        ProgressView(value: item.userState.progress)
                            .progressViewStyle(.linear)
                            .tint(Color.accentColor)
                            .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    VStack(spacing: 6) {
                        if item.userState.favorite == true {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.orange)
                                .padding(9)
                                .background(.ultraThinMaterial, in: Circle())
                                .accessibilityLabel(language.localized("detail.favorite"))
                        }
                        if item.userState.played {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .padding(9)
                                .background(.ultraThinMaterial, in: Circle())
                                .accessibilityLabel(language.localized("detail.watched"))
                        }
                    }
                    .padding(8)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(
                            isHovering
                                ? Color.accentColor.opacity(0.7)
                                : Color.white.opacity(0.08),
                            lineWidth: isHovering ? 1.5 : 1
                        )
                }
                .shadow(
                    color: .black.opacity(isHovering ? 0.55 : 0.35),
                    radius: isHovering ? 18 : 12,
                    y: isHovering ? 9 : 6
                )

            Text(item.title)
                .font(.headline)
                .lineLimit(1)
                .frame(width: 178, alignment: .leading)
                .help(item.title)

            HStack(spacing: 8) {
                if let year = item.releaseYear {
                    Text(String(year))
                }
                if let rating = item.rating {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .accessibilityHidden(true)
                        Text(rating.cineLarkRating)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        language.localized(
                            "rating.accessibility",
                            rating.cineLarkRating
                        )
                    )
                }
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .scaleEffect(isHovering && !reduceMotion ? 1.012 : 1)
        .offset(y: isHovering && !reduceMotion ? -1 : 0)
        .onHover { isHovering = $0 }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: isHovering
        )
    }
}

private struct MediaNavigationLink: View {
    let item: MediaSummary
    @State private var transitionID = UUID()

    var body: some View {
        NavigationLink(
            value: MediaDetailRoute(item: item, transitionID: transitionID)
        ) {
            MediaCard(item: item, transitionID: transitionID)
        }
        .buttonStyle(CineLarkPressButtonStyle())
    }
}

struct MediaShelf: View {
    @Environment(\.appLanguage) private var language
    let title: String
    let items: [MediaSummary]
    let viewAllCollection: MediaCollection?

    init(
        title: String,
        items: [MediaSummary],
        viewAllCollection: MediaCollection? = nil
    ) {
        self.title = title
        self.items = items
        self.viewAllCollection = viewAllCollection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title2.bold())

                Spacer()

                if let viewAllCollection {
                    NavigationLink(value: viewAllCollection) {
                        HStack(spacing: 5) {
                            Text(language.localized("general.view_all"))
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        language.localized(
                            "collection.view_all_accessibility",
                            viewAllCollection.name
                        )
                    )
                }
            }

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 22) {
                    ForEach(items) { item in
                        MediaNavigationLink(item: item)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct MediaGrid: View {
    let items: [MediaSummary]
    let isLoadingMore: Bool
    let canLoadMore: Bool
    private let onLoadMore: (() async -> Void)?

    private let columns = [
        GridItem(.adaptive(minimum: 178, maximum: 210), spacing: 28, alignment: .top)
    ]

    init(
        items: [MediaSummary],
        isLoadingMore: Bool = false,
        canLoadMore: Bool = false,
        onLoadMore: (() async -> Void)? = nil
    ) {
        self.items = items
        self.isLoadingMore = isLoadingMore
        self.canLoadMore = canLoadMore
        self.onLoadMore = onLoadMore
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 32) {
                    ForEach(items) { item in
                        MediaNavigationLink(item: item)
                            .task(id: item.id == loadMoreTriggerID) {
                                guard item.id == loadMoreTriggerID else { return }
                                await onLoadMore?()
                            }
                    }
                }
                .padding(32)

                if isLoadingMore {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.bottom, 32)
                }
            }
        }
        .background(Color.black.opacity(0.92))
    }

    private var loadMoreTriggerID: String? {
        guard canLoadMore, onLoadMore != nil, !items.isEmpty else { return nil }
        return items[max(items.count - 8, 0)].id
    }
}
