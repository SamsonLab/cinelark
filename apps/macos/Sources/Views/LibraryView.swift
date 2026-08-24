import SwiftUI
import Sparkle
import CineLarkDomain

private enum LibrarySelection: Hashable {
    case home
    case movies
    case series
    case favorites
    case search
}

struct LibraryView: View {
    @Environment(\.appLanguage) private var language
    @Environment(ShortcutCoordinator.self) private var shortcuts
    @Bindable var model: AppModel
    let updater: SPUUpdater
    @ObservedObject var updateMonitor: SparkleUpdateMonitor
    @State private var selection: LibrarySelection? = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var navigationPath = NavigationPath()
    @Namespace private var mediaTransitionNamespace

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    Section {
                        navigationLink(.home, titleKey: "nav.home", symbol: "house", shortcut: 1)
                        navigationLink(.movies, titleKey: "nav.movies", symbol: "film.stack", shortcut: 2)
                        navigationLink(.series, titleKey: "nav.series", symbol: "tv", shortcut: 3)
                        navigationLink(.favorites, titleKey: "nav.favorites", symbol: "heart", shortcut: 4)
                        navigationLink(.search, titleKey: "nav.search", symbol: "magnifyingglass", shortcut: 5)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                sidebarUtilities
            }
            .navigationTitle("CineLark")
            .navigationSplitViewColumnWidth(min: 190, ideal: 228, max: 280)
        } detail: {
            NavigationStack(path: $navigationPath) {
                destination
                    .navigationDestination(for: MediaSummary.self) { item in
                        MediaDetailView(
                            item: item,
                            provider: model.provider,
                            playback: model.playback
                        )
                        .onAppear { columnVisibility = .detailOnly }
                        .onDisappear { columnVisibility = .all }
                    }
                    .navigationDestination(for: MediaDetailRoute.self) { route in
                        MediaDetailView(
                            item: route.item,
                            provider: model.provider,
                            playback: model.playback,
                            transitionID: route.transitionID
                        )
                        .onAppear { columnVisibility = .detailOnly }
                        .onDisappear { columnVisibility = .all }
                    }
                    .navigationDestination(for: MediaCollection.self) { collection in
                        CollectionView(collection: collection, model: model)
                    }
                    .navigationDestination(for: PersonCredit.self) { person in
                        PersonDetailView(person: person, provider: model.provider)
                            .onAppear { columnVisibility = .detailOnly }
                            .onDisappear { columnVisibility = .all }
                    }
            }
            .environment(\.mediaTransitionNamespace, mediaTransitionNamespace)
            .background(CineLarkPageBackground())
        }
        .navigationSplitViewStyle(.prominentDetail)
        .task {
            let path = $navigationPath
            let selectedSection = $selection
            shortcuts.setBackAction {
                guard !path.wrappedValue.isEmpty else { return false }
                path.wrappedValue.removeLast()
                return true
            }
            shortcuts.setOpenMediaAction { item in
                path.wrappedValue.append(
                    MediaDetailRoute(item: item, transitionID: UUID())
                )
                return true
            }
            shortcuts.setOpenCollectionAction { collection in
                path.wrappedValue.append(collection)
                return true
            }
            shortcuts.setOpenPersonAction { person in
                path.wrappedValue.append(person)
                return true
            }
            shortcuts.setFixedAction(.navigation(1)) {
                path.wrappedValue = NavigationPath()
                selectedSection.wrappedValue = .home
                return true
            }
            shortcuts.setFixedAction(.navigation(2)) {
                path.wrappedValue = NavigationPath()
                selectedSection.wrappedValue = .movies
                return true
            }
            shortcuts.setFixedAction(.navigation(3)) {
                path.wrappedValue = NavigationPath()
                selectedSection.wrappedValue = .series
                return true
            }
            shortcuts.setFixedAction(.navigation(4)) {
                path.wrappedValue = NavigationPath()
                selectedSection.wrappedValue = .favorites
                return true
            }
            shortcuts.setFixedAction(.navigation(5)) {
                path.wrappedValue = NavigationPath()
                selectedSection.wrappedValue = .search
                return true
            }
            shortcuts.setFixedAction(.refresh) {
                guard !model.isLoadingHome else { return false }
                Task { await model.refreshHome() }
                return true
            }
        }
        .onDisappear {
            shortcuts.setBackAction(nil)
            shortcuts.setOpenMediaAction(nil)
            shortcuts.setOpenCollectionAction(nil)
            shortcuts.setOpenPersonAction(nil)
            for number in 1...5 {
                shortcuts.setFixedAction(.navigation(number), action: nil)
            }
            shortcuts.setFixedAction(.refresh, action: nil)
        }
        .onChange(of: selection) {
            navigationPath = NavigationPath()
        }
        .onExitCommand {
            shortcuts.navigateBack()
        }
        .alert(
            "CineLark",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.dismissError() } }
            )
        ) {
            if model.errorRecovery == .installIINA {
                Button(language.localized("error.download_iina")) {
                    model.performErrorRecovery()
                }
            }
            Button(language.localized("general.dismiss"), role: .cancel) {
                model.dismissError()
            }
        } message: {
            Text(language.userFacingError(model.errorMessage))
        }
    }

    private var sidebarUtilities: some View {
        VStack(spacing: 6) {
            LanguageMenu(
                fillsAvailableWidth: true
            )
                .buttonStyle(SidebarUtilityButtonStyle())

            SidebarUtilityButton(shortcut: .commandKey("r")) {
                Task { await model.refreshHome() }
            } label: {
                Label(
                    language.localized("general.refresh"),
                    systemImage: "arrow.clockwise"
                )
            }
            .disabled(model.isLoadingHome)

            SidebarUtilityButton {
                Task { await model.signOut() }
            } label: {
                Label(
                    language.localized("nav.sign_out"),
                    systemImage: "rectangle.portrait.and.arrow.right"
                )
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(appVersionLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 4)

                if let availableVersion = updateMonitor.availableVersion {
                    SparkleSidebarUpdateButton(
                        updater: updater,
                        availableVersion: availableVersion
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .animation(.easeOut(duration: 0.18), value: updateMonitor.availableVersion)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
    }

    private var appVersionLabel: String {
        guard let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String else {
            return "CineLark"
        }
        return "CineLark v\(version)"
    }

    private func navigationLink(
        _ value: LibrarySelection,
        titleKey: String,
        symbol: String,
        shortcut: Int
    ) -> some View {
        NavigationLink(value: value) {
            Label(
                language.localized(titleKey),
                systemImage: selection == value && symbol != "magnifyingglass"
                    ? "\(symbol).fill"
                    : symbol
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .cineLarkShortcut(.command(shortcut))
    }

    @ViewBuilder
    private var destination: some View {
        switch selection ?? .home {
        case .home:
            HomeView(model: model)
        case .movies:
            MediaCategoryView(kind: .movie, model: model)
        case .series:
            MediaCategoryView(kind: .series, model: model)
        case .favorites:
            FavoritesView(provider: model.provider)
        case .search:
            SearchView(model: model)
        }
    }
}

private struct SidebarUtilityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .cineLarkHoverSurface(
                cornerRadius: 10,
                normalFillOpacity: 0,
                hoverFillOpacity: 0.10,
                normalStrokeOpacity: 0,
                hoverStrokeOpacity: 0.08
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct SidebarUtilityButton<Label: View>: View {
    let action: () -> Void
    let shortcut: CineLarkShortcutChord?
    @ViewBuilder let label: () -> Label

    init(
        shortcut: CineLarkShortcutChord? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.shortcut = shortcut
        self.action = action
        self.label = label
    }

    var body: some View {
        GeometryReader { proxy in
            Button(action: action) {
                label()
                    .padding(.horizontal, 10)
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: .leading
                    )
                    .background(Color.primary.opacity(0.001))
                    .contentShape(Rectangle())
            }
            .buttonStyle(SidebarUtilityButtonStyle())
            .cineLarkShortcut(shortcut)
        }
        .frame(height: 36)
    }
}
