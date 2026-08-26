import ComposableArchitecture
import Sparkle
import SwiftUI

struct CineLarkSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let updater: SPUUpdater
    @Bindable var remote: RemoteCoordinator
    @Bindable var store: StoreOf<AppFeature>
    @State private var remotePresentationID = UUID()

    var body: some View {
        TabView {
            GeneralSettingsView(updater: updater)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            SourceManagerView(
                profileStore: store.scope(state: \.profile, action: \.profile),
                sourceStore: store.scope(state: \.source, action: \.source)
            )
            .tabItem {
                Label("Profiles & Sources", systemImage: "person.2.crop.square.stack")
            }

            RemoteSettingsView(
                store: store.scope(state: \.remote, action: \.remote)
            )
            .onAppear {
                remote.registerPanelPresentation(id: remotePresentationID) {
                    dismiss()
                }
            }
            .onDisappear {
                remote.unregisterPanelPresentation(id: remotePresentationID)
            }
            .tabItem {
                Label("Remote", systemImage: "iphone.and.arrow.forward")
            }

            CacheSettingsView(
                store: store.scope(state: \.cache, action: \.cache)
            )
            .tabItem {
                Label("Storage", systemImage: "internaldrive")
            }
        }
        .frame(width: 720, height: 640)
        .alert(
            "Stop Playback?",
            isPresented: Binding(
                get: { store.pendingSelection != nil },
                set: { if !$0 { store.send(.view(.cancelSelectionChange)) } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                store.send(.view(.cancelSelectionChange))
            }
            Button("Stop and Switch", role: .destructive) {
                store.send(.view(.confirmSelectionChange))
            }
        } message: {
            Text("Changing the active profile or source stops the current playback session.")
        }
    }
}

private struct GeneralSettingsView: View {
    @Environment(\.appLanguage) private var language
    @AppStorage(AppLanguage.storageKey) private var storedLanguage =
        AppLanguage.systemDefault.rawValue
    let updater: SPUUpdater

    var body: some View {
        Form {
            Section("Language") {
                Picker("Application language", selection: $storedLanguage) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(language.displayName(for: option))
                            .tag(option.rawValue)
                    }
                }
            }

            Section("Software Update") {
                LabeledContent("Current version", value: versionLabel)
                SparkleMenuUpdateButton(updater: updater)
            }

            Section("About") {
                LabeledContent("Application", value: "CineLark")
                LabeledContent("Bundle identifier", value: bundleIdentifier)
            }
        }
        .formStyle(.grouped)
    }

    private var versionLabel: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
        return "\(version) (\(build))"
    }

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "—"
    }
}
