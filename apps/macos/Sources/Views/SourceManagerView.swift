import SwiftUI
import ComposableArchitecture
import CineLarkProfile
import CineLarkPluginAPI

struct SourceManagerView: View {
    @Bindable var profileStore: StoreOf<ProfileFeature>
    @Bindable var sourceStore: StoreOf<SourceFeature>
    @State private var username = ""
    @State private var password = ""
    @State private var newProfileName = ""

    var body: some View {
        Form {
            Section("Profile") {
                Picker("Active profile", selection: activeProfile) {
                    ForEach(profileStore.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                if let manifest = activeManifest {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 5) {
                        GridRow {
                            Text("Last activity")
                                .foregroundStyle(.secondary)
                            Text((manifest.lastActivityAt ?? manifest.profile.modifiedAt).formatted(
                                date: .abbreviated,
                                time: .shortened
                            ))
                        }
                        GridRow {
                            Text("Last device")
                                .foregroundStyle(.secondary)
                            Text(manifest.lastDeviceName ?? "This device")
                        }
                        GridRow {
                            Text("Saved data")
                                .foregroundStyle(.secondary)
                            Text(
                                "\(manifest.titleCount) titles · "
                                    + "\(manifest.viewingSessionCount) sessions · "
                                    + "\(manifest.favoriteCount) favorites"
                            )
                        }
                        GridRow {
                            Text("Watch time")
                                .foregroundStyle(.secondary)
                            Text(formattedWatchTime(manifest.totalWatchSeconds))
                        }
                    }
                    .font(.caption)
                }
                HStack {
                    TextField("New profile name", text: $newProfileName)
                    Button("Create") {
                        profileStore.send(.view(.createProfile(newProfileName)))
                        newProfileName = ""
                    }
                    .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("Media Sources") {
                if sourceStore.persistedSources.isEmpty {
                    emptySources
                } else {
                    ForEach(sourceStore.persistedSources) { source in
                        let migration = sourceStore.migrationProposals[source.id]
                        Button {
                            if migration != nil {
                                sourceStore.send(.view(.beginMigration(source.id)))
                            } else {
                                profileStore.send(.view(.selectSource(source.id)))
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(source.configuration.displayName)
                                    Text(source.configuration.baseURL.absoluteString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if migration != nil {
                                    Label("Reconnect as Emby", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                } else if profileStore.activeSourceID == source.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Add Source") {
                ForEach(sourceStore.availablePlugins, id: \.id) { plugin in
                    Button {
                        sourceStore.send(.view(.beginSetup(plugin.id)))
                    } label: {
                        Label(plugin.displayName, systemImage: "plus.circle")
                    }
                }
            }

            if activeSourceSupportsRemoteState {
                Section("Remote User State") {
                    Toggle(
                        "Mirror local changes to this Emby user",
                        isOn: Binding(
                            get: { profileStore.activeBinding?.mirrorsRemoteState == true },
                            set: { profileStore.send(.view(.setRemoteMirrorEnabled($0))) }
                        )
                    )
                    Button("Import Favorites & Playback Once") {
                        profileStore.send(.view(.importRemoteState))
                    }
                    .disabled(profileStore.isImportingRemoteState)
                    if profileStore.isImportingRemoteState {
                        ProgressView("Importing remote state…")
                    } else if let applied = profileStore.lastImportApplied {
                        Text(applied ? "Remote state imported." : "This remote state was already imported.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let setup = sourceStore.setup {
                setupSection(setup)
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            sourceStore.send(.view(.cancelSetup))
        }
    }

    private var emptySources: some View {
        HStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 42, height: 42)
                .background(.quaternary, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("No Media Sources")
                    .font(.headline)
                Text("Add an Emby-compatible server or another installed source below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func setupSection(_ setup: SourceFeature.SetupState) -> some View {
        Section(setup.legacyPluginID == nil
            ? "Set Up \(pluginName(setup.pluginID))"
            : "Reconnect \(setup.displayName) as \(pluginName(setup.pluginID))"
        ) {
            if setup.legacyPluginID != nil {
                Text(
                    "Verify the standard Emby server address and sign in again. "
                        + "CineLark keeps this source's local profile history and identity."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            if supportsDiscovery(setup.pluginID) {
                Button {
                    sourceStore.send(.view(.discover))
                } label: {
                    if setup.isDiscovering {
                        ProgressView()
                    } else {
                        Label("Find Servers on Local Network", systemImage: "dot.radiowaves.left.and.right")
                    }
                }
                .disabled(setup.isDiscovering)

                ForEach(setup.discovered, id: \.self) { source in
                    Button {
                        sourceStore.send(.view(.chooseDiscovered(source)))
                    } label: {
                        VStack(alignment: .leading) {
                            Text(source.name)
                            Text(source.address.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            TextField("Server URL", text: setupBinding(\.baseURL, action: SourceFeature.Action.View.updateBaseURL))
                .textContentType(.URL)
            TextField("Display name", text: setupBinding(\.displayName, action: SourceFeature.Action.View.updateDisplayName))

            if setup.validatedConfiguration == nil {
                Button("Verify Server") {
                    sourceStore.send(.view(.validate))
                }
                .disabled(setup.baseURL.isEmpty || setup.isValidating)
            } else {
                TextField("Username", text: $username)
                SecureField("Password", text: $password)
                Button("Sign In & Save") {
                    sourceStore.send(
                        .view(.authenticate(username: username, password: password))
                    )
                    password = ""
                }
                .disabled(username.isEmpty || password.isEmpty || setup.isAuthenticating)
            }

            if setup.isValidating || setup.isAuthenticating {
                ProgressView()
            }
            if let failure = setup.failure {
                Text(String(describing: failure))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button("Cancel", role: .cancel) {
                sourceStore.send(.view(.cancelSetup))
            }
        }
    }

    private var activeProfile: Binding<ProfileID?> {
        Binding(
            get: { profileStore.activeProfileID },
            set: { id in
                if let id { profileStore.send(.view(.selectProfile(id))) }
            }
        )
    }

    private var activeManifest: ProfileManifest? {
        guard let activeProfileID = profileStore.activeProfileID else { return nil }
        return profileStore.manifests.first { $0.id == activeProfileID }
    }

    private func setupBinding(
        _ keyPath: KeyPath<SourceFeature.SetupState, String>,
        action: @escaping (String) -> SourceFeature.Action.View
    ) -> Binding<String> {
        Binding(
            get: { sourceStore.setup?[keyPath: keyPath] ?? "" },
            set: { sourceStore.send(.view(action($0))) }
        )
    }

    private func supportsDiscovery(_ pluginID: PluginID) -> Bool {
        sourceStore.availablePlugins.first { $0.id == pluginID }?
            .setupModes.contains(.localDiscovery) == true
    }

    private func pluginName(_ pluginID: PluginID) -> String {
        sourceStore.availablePlugins.first { $0.id == pluginID }?.displayName ?? "Source"
    }

    private var activeSourceSupportsRemoteState: Bool {
        guard let sourceID = profileStore.activeSourceID else { return false }
        return profileStore.sources.first(where: { $0.id == sourceID })?
            .configuration.remoteUserID != nil
    }

    private func formattedWatchTime(_ seconds: Int64) -> String {
        let minutes = max(seconds, 0) / 60
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 {
            return "\(hours)h \(remainder)m"
        }
        return "\(remainder)m"
    }
}
