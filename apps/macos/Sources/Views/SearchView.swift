import SwiftUI
import ComposableArchitecture
import CineLarkDomain

struct SearchView: View {
    @Environment(\.appLanguage) private var language
    @Environment(ShortcutCoordinator.self) private var shortcuts
    @Environment(RemoteTextInputCoordinator.self) private var remoteTextInput
    @Bindable var store: StoreOf<SearchFeature>
    @State private var keyboardOwner = UUID()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                Text(language.localized("nav.search"))
                    .font(CineLarkDesign.Typography.pageTitle)

                HStack(spacing: 14) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(language.localized("search.prompt"), text: queryBinding)
                        .textFieldStyle(.plain)
                        .font(.title2)
                        .focused($isSearchFocused)
                        .onSubmit {
                            isSearchFocused = false
                            store.send(.view(.submitted))
                        }
                        .onKeyPress(.escape) {
                            if store.query.isEmpty {
                                isSearchFocused = false
                            } else {
                                store.send(.view(.queryChanged("")))
                            }
                            return .handled
                        }
                    if !store.query.isEmpty {
                        Button {
                            store.send(.view(.queryChanged("")))
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(language.localized("general.dismiss"))
                    }
                }
                .padding(.horizontal, 22)
                .frame(maxWidth: 720)
                .frame(height: 58)
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .cineLarkShortcut(.commandKey("f"))
            }
            .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
            .padding(.top, CineLarkDesign.Layout.pageTopInset)
            .padding(.bottom, 24)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(CineLarkPageBackground())
        .navigationTitle(language.localized("nav.search"))
        .onAppear {
            registerKeyboardNavigation()
            focusSearchInput()
        }
        .onDisappear {
            shortcuts.removeNavigationSurface(owner: keyboardOwner)
            shortcuts.setFixedAction(.focusSearch, action: nil)
            remoteTextInput.close(owner: keyboardOwner)
        }
        .onChange(of: store.query) {
            remoteTextInput.localTextChanged(store.query, owner: keyboardOwner)
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                language.localized("search.empty"),
                systemImage: "sparkles.tv",
                description: Text(language.localized("search.empty_description"))
            )
        } else if store.isSearching && store.orderedResults.isEmpty {
            ProgressView(language.localized("search.searching"))
                .controlSize(.large)
        } else if store.orderedResults.isEmpty {
            ContentUnavailableView.search(text: store.query)
        } else {
            PosterGrid(
                items: store.orderedResults,
                isLoadingMore: store.isLoadingMore,
                canLoadMore: store.nextCursor != nil,
                autoFocusFirst: false,
                topContentInset: CineLarkDesign.Layout.focusSafeTopInset,
                onLoadMore: {
                    await store.send(.view(.loadMore)).finish()
                }
            )
        }
    }

    private func registerKeyboardNavigation() {
        let searchFocus = $isSearchFocused
        shortcuts.setFixedAction(.focusSearch) {
            searchFocus.wrappedValue = true
            return true
        }
        shortcuts.setNavigationSurface(
            owner: keyboardOwner,
            move: { _ in
                searchFocus.wrappedValue = true
                return true
            },
            activate: {
                searchFocus.wrappedValue = true
                return true
            }
        )
        remoteTextInput.open(
            owner: keyboardOwner,
            kind: "search",
            text: store.query,
            update: { text in
                store.send(.view(.queryChanged(text)))
                searchFocus.wrappedValue = true
            },
            commit: {
                searchFocus.wrappedValue = false
                store.send(.view(.submitted))
            },
            cancel: {
                store.send(.view(.queryChanged("")))
                searchFocus.wrappedValue = false
            }
        )
    }

    private func focusSearchInput() {
        isSearchFocused = true
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { store.query },
            set: { store.send(.view(.queryChanged($0))) }
        )
    }
}
