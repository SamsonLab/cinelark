import SwiftUI
import CineLarkDomain

struct MediaDetailRoute: Hashable {
    let item: MediaSummary
    let transitionID: UUID
}

struct PosterLockup: View {
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
        VStack(alignment: .leading, spacing: CineLarkDesign.Layout.lockupSpacing) {
            artwork

            Text(item.title)
                .font(CineLarkDesign.Typography.cardTitle)
                .lineLimit(1)
                .frame(width: CineLarkDesign.Media.posterWidth, alignment: .leading)
                .help(item.title)

            MediaFacts(item: item)
                .frame(width: CineLarkDesign.Media.posterWidth, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering { onHighlight?(item) }
        }
    }

    private var artwork: some View {
        MediaArtworkSurface(
            item: item,
            url: item.posterURL ?? item.backdropURL,
            size: CGSize(
                width: CineLarkDesign.Media.posterWidth,
                height: CineLarkDesign.Media.posterHeight
            ),
            role: .discovery,
            transitionID: transitionID
        )
            .cineLarkFocusSurface(isActive: isFocused || isHovering)
    }
}

private struct PosterNavigationLink: View {
    let item: MediaSummary
    let onHighlight: ((MediaSummary) -> Void)?
    @State private var transitionID = UUID()
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationLink(
            value: MediaDetailRoute(item: item, transitionID: transitionID)
        ) {
            PosterLockup(
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

struct PosterShelf: View {
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
                    .font(CineLarkDesign.Typography.sectionTitle)

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
            .padding(.horizontal, CineLarkDesign.Layout.contentMargin)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: CineLarkDesign.Layout.shelfSpacing) {
                    ForEach(items) { item in
                        PosterNavigationLink(item: item, onHighlight: onHighlight)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 26)
            }
            .contentMargins(
                .horizontal,
                CineLarkDesign.Layout.contentMargin,
                for: .scrollContent
            )
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .focusSection()
        }
    }
}

struct PosterGrid: View {
    let items: [MediaSummary]
    let isLoadingMore: Bool
    let canLoadMore: Bool
    private let onLoadMore: (() async -> Void)?

    private let columns = [
        GridItem(
            .adaptive(
                minimum: CineLarkDesign.Media.posterWidth,
                maximum: CineLarkDesign.Media.posterWidth + 26
            ),
            spacing: CineLarkDesign.Layout.posterGridColumnSpacing,
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
                LazyVGrid(
                    columns: columns,
                    alignment: .leading,
                    spacing: CineLarkDesign.Layout.posterGridRowSpacing
                ) {
                    ForEach(items) { item in
                        PosterNavigationLink(item: item, onHighlight: nil)
                            .task(id: item.id == loadMoreTriggerID) {
                                guard item.id == loadMoreTriggerID else { return }
                                await onLoadMore?()
                            }
                    }
                }
                .focusSection()
                .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
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
