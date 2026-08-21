import SwiftUI
import CineLarkDomain

struct MediaDetailRoute: Hashable {
    let item: MediaSummary
    let transitionID: UUID
}

struct MediaCard: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.mediaTransitionNamespace) private var transitionNamespace
    let item: MediaSummary
    let transitionID: UUID?
    let isFocused: Bool
    let onHighlight: ((MediaSummary) -> Void)?
    @State private var isHovering = false

    init(
        item: MediaSummary,
        transitionID: UUID? = nil,
        isFocused: Bool = false,
        onHighlight: ((MediaSummary) -> Void)? = nil
    ) {
        self.item = item
        self.transitionID = transitionID
        self.isFocused = isFocused
        self.onHighlight = onHighlight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            artwork

            Text(item.title)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
                .frame(width: CineLarkTheme.posterWidth, alignment: .leading)
                .help(item.title)

            metadata
                .frame(width: CineLarkTheme.posterWidth, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering { onHighlight?(item) }
        }
    }

    private var artwork: some View {
        ArtworkView(url: item.posterURL)
            .frame(width: CineLarkTheme.posterWidth, height: CineLarkTheme.posterHeight)
            .clipShape(RoundedRectangle(cornerRadius: CineLarkTheme.cardRadius, style: .continuous))
            .mediaMatchedGeometry(
                id: transitionID,
                namespace: transitionNamespace,
                isSource: true
            )
            .overlay(alignment: .bottom) {
                if item.userState.progress > 0 && !item.userState.played {
                    ProgressView(value: item.userState.progress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .padding(10)
                }
            }
            .overlay(alignment: .topTrailing) {
                stateBadges
                    .padding(10)
            }
            .cineLarkCardLift(isActive: isFocused || isHovering)
    }

    @ViewBuilder
    private var stateBadges: some View {
        VStack(spacing: 7) {
            if item.userState.favorite == true {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.orange)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.52), in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                    }
                    .accessibilityLabel(language.localized("detail.favorite"))
            }
            if item.userState.played {
                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.52), in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                    }
                    .accessibilityLabel(language.localized("detail.watched"))
            }
        }
    }

    private var metadata: some View {
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
                    language.localized("rating.accessibility", rating.cineLarkRating)
                )
            }
        }
        .font(.caption.weight(.medium))
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
}

private struct MediaNavigationLink: View {
    let item: MediaSummary
    let onHighlight: ((MediaSummary) -> Void)?
    @State private var transitionID = UUID()
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationLink(
            value: MediaDetailRoute(item: item, transitionID: transitionID)
        ) {
            MediaCard(
                item: item,
                transitionID: transitionID,
                isFocused: isFocused,
                onHighlight: onHighlight
            )
        }
        .buttonStyle(CineLarkPressButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
        .onChange(of: isFocused) {
            if isFocused { onHighlight?(item) }
        }
    }
}

struct MediaShelf: View {
    @Environment(\.appLanguage) private var language
    let title: String
    let items: [MediaSummary]
    let viewAllCollection: MediaCollection?
    let onHighlight: ((MediaSummary) -> Void)?

    init(
        title: String,
        items: [MediaSummary],
        viewAllCollection: MediaCollection? = nil,
        onHighlight: ((MediaSummary) -> Void)? = nil
    ) {
        self.title = title
        self.items = items
        self.viewAllCollection = viewAllCollection
        self.onHighlight = onHighlight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 25, weight: .semibold))

                Spacer()

                if let viewAllCollection {
                    NavigationLink(value: viewAllCollection) {
                        Label(
                            language.localized("general.view_all"),
                            systemImage: "chevron.right"
                        )
                        .labelStyle(.titleAndIcon)
                        .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(
                        language.localized(
                            "collection.view_all_accessibility",
                            viewAllCollection.name
                        )
                    )
                }
            }
            .padding(.horizontal, CineLarkTheme.contentMargin)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 26) {
                    ForEach(items) { item in
                        MediaNavigationLink(item: item, onHighlight: onHighlight)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 26)
            }
            .contentMargins(.horizontal, CineLarkTheme.contentMargin, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .focusSection()
        }
    }
}

struct MediaGrid: View {
    let items: [MediaSummary]
    let isLoadingMore: Bool
    let canLoadMore: Bool
    private let onLoadMore: (() async -> Void)?

    private let columns = [
        GridItem(
            .adaptive(
                minimum: CineLarkTheme.posterWidth,
                maximum: CineLarkTheme.posterWidth + 26
            ),
            spacing: 32,
            alignment: .top
        )
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
                LazyVGrid(columns: columns, alignment: .leading, spacing: 38) {
                    ForEach(items) { item in
                        MediaNavigationLink(item: item, onHighlight: nil)
                            .task(id: item.id == loadMoreTriggerID) {
                                guard item.id == loadMoreTriggerID else { return }
                                await onLoadMore?()
                            }
                    }
                }
                .focusSection()
                .padding(.horizontal, CineLarkTheme.contentMargin)
                .padding(.vertical, 34)

                if isLoadingMore {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.bottom, 40)
                }
            }
        }
        .background(CineLarkPageBackground())
    }

    private var loadMoreTriggerID: String? {
        guard canLoadMore, onLoadMore != nil, !items.isEmpty else { return nil }
        return items[max(items.count - 8, 0)].id
    }
}
