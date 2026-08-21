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
    let isSelected: Bool
    let focusedItemID: FocusState<String?>.Binding
    @State private var transitionID = UUID()

    var body: some View {
        NavigationLink(
            value: MediaDetailRoute(item: item, transitionID: transitionID)
        ) {
            PosterLockup(
                item: item,
                transitionID: transitionID,
                isFocused: isSelected || focusedItemID.wrappedValue == item.id,
                onHighlight: onHighlight
            )
        }
        .buttonStyle(CineLarkPressButtonStyle())
        .focused(focusedItemID, equals: item.id)
        .focusEffectDisabled()
        .onChange(of: isFocused) {
            if focusedItemID.wrappedValue == item.id { onHighlight?(item) }
        }
    }

    private var isFocused: Bool {
        focusedItemID.wrappedValue == item.id
    }
}

struct PosterShelf: View {
    @Environment(\.appLanguage) private var language
    let title: String
    let items: [MediaSummary]
    let viewAllCollection: MediaCollection?
    let onHighlight: ((MediaSummary) -> Void)?
    @FocusState private var focusedItemID: String?

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
                        PosterNavigationLink(
                            item: item,
                            onHighlight: onHighlight,
                            isSelected: focusedItemID == item.id,
                            focusedItemID: $focusedItemID
                        )
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
    @Environment(ShortcutCoordinator.self) private var shortcuts
    let items: [MediaSummary]
    let isLoadingMore: Bool
    let canLoadMore: Bool
    let autoFocusFirst: Bool
    private let onLoadMore: (() async -> Void)?
    @FocusState private var focusedItemID: String?
    @State private var selectedItemID: String?
    @State private var focusOwner = UUID()
    @State private var availableWidth: CGFloat = 0

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
        autoFocusFirst: Bool = true,
        onLoadMore: (() async -> Void)? = nil
    ) {
        self.items = items
        self.isLoadingMore = isLoadingMore
        self.canLoadMore = canLoadMore
        self.autoFocusFirst = autoFocusFirst
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
                        PosterNavigationLink(
                            item: item,
                            onHighlight: nil,
                            isSelected: selectedItemID == item.id,
                            focusedItemID: $focusedItemID
                        )
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
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            availableWidth = width
            registerDirectionalAction()
        }
        .onAppear {
            if autoFocusFirst, selectedItemID == nil {
                selectedItemID = items.first?.id
            }
            registerDirectionalAction()
        }
        .onDisappear {
            shortcuts.clearDirectionalAction(owner: focusOwner)
        }
        .onChange(of: items.map(\.id)) {
            if let focusedItemID, !items.contains(where: { $0.id == focusedItemID }) {
                self.focusedItemID = nil
            }
            if let selectedItemID, !items.contains(where: { $0.id == selectedItemID }) {
                self.selectedItemID = items.first?.id
            }
            registerDirectionalAction()
        }
    }

    private var loadMoreTriggerID: String? {
        guard canLoadMore, onLoadMore != nil, !items.isEmpty else { return nil }
        return items[max(items.count - 8, 0)].id
    }

    private var columnsPerRow: Int {
        let contentWidth = max(
            0,
            availableWidth - (CineLarkDesign.Layout.contentMargin * 2)
        )
        let itemWidth = CineLarkDesign.Media.posterWidth +
            CineLarkDesign.Layout.posterGridColumnSpacing
        return max(
            1,
            Int(
                (contentWidth + CineLarkDesign.Layout.posterGridColumnSpacing) /
                    itemWidth
            )
        )
    }

    private func registerDirectionalAction() {
        let itemIDs = items.map(\.id)
        let columnCount = columnsPerRow
        let focusedItem = $focusedItemID
        let selectedItem = $selectedItemID
        shortcuts.setDirectionalAction(
            owner: focusOwner,
            move: { direction in
                guard !itemIDs.isEmpty else { return false }
                let currentID = selectedItem.wrappedValue ?? focusedItem.wrappedValue
                guard let currentID,
                      let currentIndex = itemIDs.firstIndex(of: currentID) else {
                    selectedItem.wrappedValue = itemIDs[0]
                    focusedItem.wrappedValue = itemIDs[0]
                    return true
                }

                let targetIndex: Int
                switch direction {
                case .left:
                    targetIndex = max(0, currentIndex - 1)
                case .right:
                    targetIndex = min(itemIDs.count - 1, currentIndex + 1)
                case .up:
                    targetIndex = max(0, currentIndex - columnCount)
                case .down:
                    targetIndex = min(itemIDs.count - 1, currentIndex + columnCount)
                }
                selectedItem.wrappedValue = itemIDs[targetIndex]
                focusedItem.wrappedValue = itemIDs[targetIndex]
                return true
            },
            activate: { [weak shortcuts] in
                guard let selectedID = selectedItem.wrappedValue ?? focusedItem.wrappedValue,
                      let item = items.first(where: { $0.id == selectedID }) else {
                    return false
                }
                return shortcuts?.openMedia(item) == true
            }
        )
    }
}
