import SwiftUI
import CineLarkDomain

struct MediaDetailRoute: Hashable {
    let item: MediaSummary
    let transitionID: UUID
}

struct PosterLockup: View {
    @Environment(ShortcutCoordinator.self) private var shortcuts
    let item: MediaSummary
    let transitionID: UUID?
    let isFocused: Bool
    let onPointerSelection: ((MediaSummary, Bool) -> Void)?
    let onHighlight: ((MediaSummary) -> Void)?
    @State private var isHovering = false

    init(
        item: MediaSummary,
        transitionID: UUID? = nil,
        isFocused: Bool = false,
        onPointerSelection: ((MediaSummary, Bool) -> Void)? = nil,
        onHighlight: ((MediaSummary) -> Void)? = nil
    ) {
        self.item = item
        self.transitionID = transitionID
        self.isFocused = isFocused
        self.onPointerSelection = onPointerSelection
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
            if !hovering || shortcuts.inputModality == .pointer {
                onPointerSelection?(item, hovering)
            }
            if hovering, shortcuts.inputModality == .pointer {
                onHighlight?(item)
            }
        }
        .onChange(of: shortcuts.inputModality) {
            if shortcuts.inputModality == .pointer, isHovering {
                onPointerSelection?(item, true)
                onHighlight?(item)
            }
        }
        .onDisappear {
            if isHovering { onPointerSelection?(item, false) }
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
            .cineLarkFocusSurface(
                isActive: isFocused ||
                    (shortcuts.inputModality == .pointer && isHovering)
            )
            .cineLarkKeyboardSelectionHint(isActive: isFocused)
    }
}

private struct PosterNavigationLink: View {
    let item: MediaSummary
    let onPointerSelection: ((MediaSummary, Bool) -> Void)?
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
                onPointerSelection: onPointerSelection,
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
    @Environment(ShortcutCoordinator.self) private var shortcuts
    let title: String
    let items: [MediaSummary]
    let viewAllCollection: MediaCollection?
    let selectedItemID: String?
    let isViewAllSelected: Bool
    let isKeyboardNavigationActive: Bool
    let onPointerSelection: ((MediaSummary, Bool) -> Void)?
    let onViewAllPointerSelection: ((MediaCollection, Bool) -> Void)?
    let onHighlight: ((MediaSummary) -> Void)?
    @FocusState private var focusedItemID: String?

    init(
        title: String,
        items: [MediaSummary],
        viewAllCollection: MediaCollection? = nil,
        selectedItemID: String? = nil,
        isViewAllSelected: Bool = false,
        isKeyboardNavigationActive: Bool = false,
        onPointerSelection: ((MediaSummary, Bool) -> Void)? = nil,
        onViewAllPointerSelection: ((MediaCollection, Bool) -> Void)? = nil,
        onHighlight: ((MediaSummary) -> Void)? = nil
    ) {
        self.title = title
        self.items = items
        self.viewAllCollection = viewAllCollection
        self.selectedItemID = selectedItemID
        self.isViewAllSelected = isViewAllSelected
        self.isKeyboardNavigationActive = isKeyboardNavigationActive
        self.onPointerSelection = onPointerSelection
        self.onViewAllPointerSelection = onViewAllPointerSelection
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
                    .focusEffectDisabled()
                    .cineLarkFocusSurface(
                        isActive: isViewAllSelected,
                        cornerRadius: 18,
                        scale: 1.02
                    )
                    .cineLarkPointerSelection { hovering in
                        onViewAllPointerSelection?(viewAllCollection, hovering)
                    }
                    .accessibilityLabel(
                        language.localized(
                            "collection.view_all_accessibility",
                            viewAllCollection.name
                        )
                    )
                }
            }
            .padding(.horizontal, CineLarkDesign.Layout.contentMargin)

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: CineLarkDesign.Layout.shelfSpacing) {
                        ForEach(items) { item in
                            PosterNavigationLink(
                                item: item,
                                onPointerSelection: onPointerSelection,
                                onHighlight: onHighlight,
                                isSelected: shortcuts.usesKeyboardNavigation &&
                                    (isKeyboardNavigationActive
                                        ? selectedItemID == item.id
                                        : focusedItemID == item.id),
                                focusedItemID: $focusedItemID
                            )
                            .id(item.id)
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
                .onChange(of: selectedItemID) {
                    guard let selectedItemID else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollProxy.scrollTo(selectedItemID, anchor: .leading)
                    }
                }
            }
        }
    }
}

struct PosterGridLeadingKeyboardAction {
    let id: String
    let activate: () -> Bool
}

struct PosterGrid: View {
    @Environment(ShortcutCoordinator.self) private var shortcuts
    let items: [MediaSummary]
    let isLoadingMore: Bool
    let canLoadMore: Bool
    let autoFocusFirst: Bool
    let topContentInset: CGFloat
    private let pointerSelectedLeadingActionID: String?
    private let preferredLeadingKeyboardID: String?
    private let leadingKeyboardActions: [PosterGridLeadingKeyboardAction]
    private let onLeadingSelectionChange: ((String?) -> Void)?
    private let onLoadMore: (() async -> Void)?
    @FocusState private var focusedItemID: String?
    @State private var selectedItemID: String?
    @State private var focusOwner = UUID()
    @State private var availableWidth: CGFloat = 0
    @State private var selectedLeadingKeyboardID: String?
    @State private var rememberedItemID: String?
    @State private var rememberedLeadingKeyboardID: String?
    @State private var pointerSelectedItemID: String?

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
        topContentInset: CGFloat = 34,
        pointerSelectedLeadingActionID: String? = nil,
        preferredLeadingKeyboardID: String? = nil,
        leadingKeyboardActions: [PosterGridLeadingKeyboardAction] = [],
        onLeadingSelectionChange: ((String?) -> Void)? = nil,
        onLoadMore: (() async -> Void)? = nil
    ) {
        self.items = items
        self.isLoadingMore = isLoadingMore
        self.canLoadMore = canLoadMore
        self.autoFocusFirst = autoFocusFirst
        self.topContentInset = topContentInset
        self.pointerSelectedLeadingActionID = pointerSelectedLeadingActionID
        self.preferredLeadingKeyboardID = preferredLeadingKeyboardID
        self.leadingKeyboardActions = leadingKeyboardActions
        self.onLeadingSelectionChange = onLeadingSelectionChange
        self.onLoadMore = onLoadMore
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 0) {
                    LazyVGrid(
                        columns: columns,
                        alignment: .leading,
                        spacing: max(
                            0,
                            CineLarkDesign.Layout.posterGridRowSpacing -
                                CineLarkDesign.Layout.focusScrollClearance
                        )
                    ) {
                        ForEach(items) { item in
                            VStack(spacing: 0) {
                                Color.clear
                                    .frame(height: CineLarkDesign.Layout.focusScrollClearance)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)

                                PosterNavigationLink(
                                    item: item,
                                    onPointerSelection: updatePointerSelection,
                                    onHighlight: nil,
                                    isSelected: shortcuts.usesKeyboardNavigation &&
                                        (selectedItemID == item.id ||
                                            (selectedItemID == nil &&
                                                focusedItemID == item.id)),
                                    focusedItemID: $focusedItemID
                                )
                            }
                            .id(item.id)
                            .task(id: item.id == loadMoreTriggerID) {
                                guard item.id == loadMoreTriggerID else { return }
                                await onLoadMore?()
                            }
                        }
                    }
                    .focusSection()
                    .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
                    .padding(
                        .top,
                        max(
                            0,
                            topContentInset - CineLarkDesign.Layout.focusScrollClearance
                        )
                    )
                    .padding(.bottom, 34)

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
                registerDirectionalAction(scrollProxy: scrollProxy)
            }
            .onAppear {
                if autoFocusFirst, selectedItemID == nil {
                    selectedItemID = items.first?.id
                    rememberedItemID = items.first?.id
                }
                restorePreferredLeadingSelectionIfNeeded()
                registerDirectionalAction(scrollProxy: scrollProxy)
            }
            .onDisappear {
                shortcuts.removeNavigationSurface(owner: focusOwner)
                pointerSelectedItemID = nil
            }
            .onChange(of: items.map(\.id)) {
                if let focusedItemID, !items.contains(where: { $0.id == focusedItemID }) {
                    self.focusedItemID = nil
                }
                if let selectedItemID, !items.contains(where: { $0.id == selectedItemID }) {
                    self.selectedItemID = items.first?.id
                }
                if let rememberedItemID,
                   !items.contains(where: { $0.id == rememberedItemID }) {
                    self.rememberedItemID = nil
                }
                if let pointerSelectedItemID,
                   !items.contains(where: { $0.id == pointerSelectedItemID }) {
                    self.pointerSelectedItemID = nil
                }
                restorePreferredLeadingSelectionIfNeeded()
                registerDirectionalAction(scrollProxy: scrollProxy)
            }
            .onChange(of: leadingKeyboardActions.map(\.id)) {
                if let selectedLeadingKeyboardID,
                   !leadingKeyboardActions.contains(where: {
                       $0.id == selectedLeadingKeyboardID
                   }) {
                    self.selectedLeadingKeyboardID = nil
                    onLeadingSelectionChange?(nil)
                }
                if let rememberedLeadingKeyboardID,
                   !leadingKeyboardActions.contains(where: {
                       $0.id == rememberedLeadingKeyboardID
                   }) {
                    self.rememberedLeadingKeyboardID = nil
                }
                registerDirectionalAction(scrollProxy: scrollProxy)
            }
            .onChange(of: pointerSelectedLeadingActionID) {
                registerDirectionalAction(scrollProxy: scrollProxy)
            }
            .onChange(of: preferredLeadingKeyboardID) {
                restorePreferredLeadingSelectionIfNeeded()
                registerDirectionalAction(scrollProxy: scrollProxy)
            }
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

    private func registerDirectionalAction(scrollProxy: ScrollViewProxy) {
        let itemIDs = items.map(\.id)
        let columnCount = columnsPerRow
        let focusedItem = $focusedItemID
        let selectedItem = $selectedItemID
        let leadingSelection = $selectedLeadingKeyboardID
        let rememberedItem = $rememberedItemID
        let rememberedLeading = $rememberedLeadingKeyboardID
        let pointerItemSelection = $pointerSelectedItemID
        let pointerLeadingSelection = pointerSelectedLeadingActionID
        let leadingActions = leadingKeyboardActions
        shortcuts.setNavigationSurface(
            owner: focusOwner,
            handoffToKeyboard: {
                if let pointerItemID = pointerItemSelection.wrappedValue,
                   itemIDs.contains(pointerItemID) {
                    selectedItem.wrappedValue = pointerItemID
                    focusedItem.wrappedValue = pointerItemID
                    rememberedItem.wrappedValue = pointerItemID
                    leadingSelection.wrappedValue = nil
                    onLeadingSelectionChange?(nil)
                } else if let pointerLeadingSelection,
                          leadingActions.contains(where: {
                              $0.id == pointerLeadingSelection
                          }) {
                    selectedItem.wrappedValue = nil
                    focusedItem.wrappedValue = nil
                    leadingSelection.wrappedValue = pointerLeadingSelection
                    rememberedLeading.wrappedValue = pointerLeadingSelection
                    onLeadingSelectionChange?(pointerLeadingSelection)
                }
            },
            move: { direction in
                let handedPointerItemID = shortcuts.inputModality == .pointer
                    ? pointerItemSelection.wrappedValue
                    : nil
                let handedPointerLeadingID = shortcuts.inputModality == .pointer &&
                    handedPointerItemID == nil
                    ? pointerLeadingSelection
                    : nil
                if let selectedLeadingID = handedPointerLeadingID ??
                    leadingSelection.wrappedValue,
                   let selectedLeadingIndex = leadingActions.firstIndex(where: {
                       $0.id == selectedLeadingID
                   }) {
                    if direction == .left || direction == .right {
                        let delta = direction == .left ? -1 : 1
                        let targetIndex = min(
                            max(0, selectedLeadingIndex + delta),
                            leadingActions.count - 1
                        )
                        selectLeading(
                            leadingActions[targetIndex].id,
                            selectedItem: selectedItem,
                            focusedItem: focusedItem,
                            leadingSelection: leadingSelection
                        )
                        return true
                    }
                    guard direction == .down,
                          let targetItemID = rememberedItem.wrappedValue.flatMap({
                              itemIDs.contains($0) ? $0 : nil
                          }) ?? itemIDs.first else {
                        return true
                    }
                    select(
                        targetItemID,
                        selectedItem: selectedItem,
                        focusedItem: focusedItem,
                        leadingSelection: leadingSelection,
                        scrollProxy: scrollProxy
                    )
                    return true
                }
                guard !itemIDs.isEmpty else {
                    guard let targetLeadingID = rememberedLeading.wrappedValue.flatMap({ id in
                        leadingActions.contains(where: { $0.id == id }) ? id : nil
                    }) ?? preferredLeadingKeyboardID.flatMap({ id in
                        leadingActions.contains(where: { $0.id == id }) ? id : nil
                    }) ?? leadingActions.first?.id else {
                        return false
                    }
                    selectLeading(
                        targetLeadingID,
                        selectedItem: selectedItem,
                        focusedItem: focusedItem,
                        leadingSelection: leadingSelection
                    )
                    return true
                }
                let currentID = handedPointerItemID ?? selectedItem.wrappedValue ??
                    focusedItem.wrappedValue
                guard let currentID,
                      let currentIndex = itemIDs.firstIndex(of: currentID) else {
                    if let targetLeadingID = rememberedLeading.wrappedValue.flatMap({ id in
                        leadingActions.contains(where: { $0.id == id }) ? id : nil
                    }) ?? preferredLeadingKeyboardID.flatMap({ id in
                        leadingActions.contains(where: { $0.id == id }) ? id : nil
                    }) ?? leadingActions.first?.id {
                        selectLeading(
                            targetLeadingID,
                            selectedItem: selectedItem,
                            focusedItem: focusedItem,
                            leadingSelection: leadingSelection
                        )
                        return true
                    }
                    select(
                        itemIDs[0],
                        selectedItem: selectedItem,
                        focusedItem: focusedItem,
                        leadingSelection: leadingSelection,
                        scrollProxy: scrollProxy
                    )
                    return true
                }

                let targetIndex: Int
                switch direction {
                case .left:
                    targetIndex = max(0, currentIndex - 1)
                case .right:
                    targetIndex = min(itemIDs.count - 1, currentIndex + 1)
                case .up:
                    if currentIndex < columnCount, !leadingActions.isEmpty {
                        let fallbackIndex = min(currentIndex, leadingActions.count - 1)
                        let targetLeadingID = rememberedLeading.wrappedValue.flatMap { id in
                            leadingActions.contains(where: { $0.id == id }) ? id : nil
                        } ?? preferredLeadingKeyboardID.flatMap { id in
                            leadingActions.contains(where: { $0.id == id }) ? id : nil
                        } ?? leadingActions[fallbackIndex].id
                        selectLeading(
                            targetLeadingID,
                            selectedItem: selectedItem,
                            focusedItem: focusedItem,
                            leadingSelection: leadingSelection
                        )
                        return true
                    }
                    targetIndex = max(0, currentIndex - columnCount)
                case .down:
                    targetIndex = min(itemIDs.count - 1, currentIndex + columnCount)
                }
                select(
                    itemIDs[targetIndex],
                    selectedItem: selectedItem,
                    focusedItem: focusedItem,
                    leadingSelection: leadingSelection,
                    scrollProxy: scrollProxy
                )
                return true
            },
            activate: { [weak shortcuts] in
                let handedPointerItemID = shortcuts?.inputModality == .pointer
                    ? pointerItemSelection.wrappedValue
                    : nil
                let handedPointerLeadingID = shortcuts?.inputModality == .pointer &&
                    handedPointerItemID == nil
                    ? pointerLeadingSelection
                    : nil
                if let selectedLeadingID = handedPointerLeadingID ??
                    leadingSelection.wrappedValue,
                   let action = leadingActions.first(where: {
                       $0.id == selectedLeadingID
                   }) {
                    return action.activate()
                }
                guard let selectedID = handedPointerItemID ?? selectedItem.wrappedValue ??
                    focusedItem.wrappedValue,
                      let item = items.first(where: { $0.id == selectedID }) else {
                    return false
                }
                return shortcuts?.openMedia(item) == true
            }
        )
    }

    private func updatePointerSelection(_ item: MediaSummary, _ hovering: Bool) {
        if hovering {
            pointerSelectedItemID = item.id
        } else if pointerSelectedItemID == item.id {
            pointerSelectedItemID = nil
        }
    }

    private func restorePreferredLeadingSelectionIfNeeded() {
        guard items.isEmpty,
              selectedLeadingKeyboardID == nil,
              let preferredLeadingKeyboardID,
              leadingKeyboardActions.contains(where: {
                  $0.id == preferredLeadingKeyboardID
              }) else {
            return
        }
        selectedLeadingKeyboardID = preferredLeadingKeyboardID
        rememberedLeadingKeyboardID = preferredLeadingKeyboardID
        onLeadingSelectionChange?(preferredLeadingKeyboardID)
    }

    private func select(
        _ itemID: String,
        selectedItem: Binding<String?>,
        focusedItem: FocusState<String?>.Binding,
        leadingSelection: Binding<String?>,
        scrollProxy: ScrollViewProxy
    ) {
        withAnimation(.easeOut(duration: 0.2)) {
            leadingSelection.wrappedValue = nil
            onLeadingSelectionChange?(nil)
            selectedItem.wrappedValue = itemID
            rememberedItemID = itemID
            focusedItem.wrappedValue = itemID
            scrollProxy.scrollTo(itemID, anchor: .top)
        }
    }

    private func selectLeading(
        _ leadingID: String,
        selectedItem: Binding<String?>,
        focusedItem: FocusState<String?>.Binding,
        leadingSelection: Binding<String?>
    ) {
        withAnimation(.easeOut(duration: 0.2)) {
            selectedItem.wrappedValue = nil
            focusedItem.wrappedValue = nil
            leadingSelection.wrappedValue = leadingID
            rememberedLeadingKeyboardID = leadingID
            onLeadingSelectionChange?(leadingID)
        }
    }
}
