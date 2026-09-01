import SwiftUI
import ComposableArchitecture
import CineLarkProfile
import CineLarkPluginAPI

struct SourceManagerView: View {
    @Bindable var profileStore: StoreOf<ProfileFeature>
    @Bindable var sourceStore: StoreOf<SourceFeature>
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                CineLarkSettingsPageHeader(
                    title: "Viewing & Sources",
                    subtitle: "One personal Profile, private iCloud sync, and media servers.",
                    systemImage: "person.crop.circle"
                )

                personalViewingCard
                syncCard
                mediaSourcesCard

                if activeSourceSupportsRemoteState {
                    remoteStateCard
                }

                if let setup = sourceStore.setup {
                    setupSection(setup)
                }
            }
            .padding(28)
        }
        .background(CineLarkPageBackground())
        .onDisappear {
            sourceStore.send(.view(.cancelSetup))
        }
    }

    private var personalViewingCard: some View {
        CineLarkSettingsCard(
            "Personal Viewing",
            subtitle: "One private viewing history is used for this iCloud account.",
            systemImage: "person.fill"
        ) {
            if let manifest = activeManifest {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 9) {
                    GridRow {
                        Text("Last activity").foregroundStyle(.secondary)
                        Text((manifest.lastActivityAt ?? manifest.profile.modifiedAt).formatted(
                            date: .abbreviated,
                            time: .shortened
                        ))
                    }
                    GridRow {
                        Text("Last device").foregroundStyle(.secondary)
                        Text(manifest.lastDeviceName ?? "This device")
                    }
                    GridRow {
                        Text("Saved data").foregroundStyle(.secondary)
                        Text(
                            "\(manifest.titleCount) titles · "
                                + "\(manifest.viewingSessionCount) sessions · "
                                + "\(manifest.favoriteCount) favorites"
                        )
                    }
                    GridRow {
                        Text("Watch time").foregroundStyle(.secondary)
                        Text(formattedWatchTime(manifest.totalWatchSeconds))
                    }
                }
                .font(.callout)
            } else {
                ProgressView("Preparing personal viewing history…")
                    .controlSize(.small)
            }
        }
    }

    private var syncCard: some View {
        CineLarkSettingsCard(
            "iCloud Sync",
            subtitle: "Viewing state remains local-first and synchronizes automatically.",
            systemImage: syncStatusSymbol
        ) {
            LabeledContent("Status") {
                Label(syncStatusTitle, systemImage: syncStatusSymbol)
                    .foregroundStyle(syncStatusColor)
            }

            if !profileStore.cloudSyncStatus.activeOperations.isEmpty {
                Divider()
                LabeledContent("Activity", value: syncActivityDescription)
            }

            if let lastSuccessfulAt = profileStore.cloudSyncStatus.lastSuccessfulAt {
                Divider()
                LabeledContent(
                    "Last successful event",
                    value: lastSuccessfulAt.formatted(date: .abbreviated, time: .shortened)
                )
            }

            Text(syncStatusDetail)
                .font(.callout)
                .foregroundStyle(.secondary)

            if profileStore.cloudSyncStatus.phase == .failed,
               let failure = profileStore.cloudSyncStatus.failureDescription {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Button {
                profileStore.send(.view(.refreshCloudSyncStatus))
            } label: {
                if profileStore.isRefreshingCloudSyncStatus {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Recheck iCloud", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.glass)
            .disabled(profileStore.isRefreshingCloudSyncStatus)
        }
    }

    private var mediaSourcesCard: some View {
        CineLarkSettingsCard(
            "Media Sources",
            subtitle: "Choose the active server or connect another Emby service.",
            systemImage: "externaldrive.connected.to.line.below"
        ) {
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
                        HStack(spacing: 12) {
                            Image(systemName: "server.rack")
                                .font(.title3)
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(source.configuration.displayName)
                                    .font(.headline)
                                Text(source.configuration.baseURL.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if migration != nil {
                                Label(
                                    "Reconnect as Emby",
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                .font(.caption)
                                .foregroundStyle(.orange)
                            } else if profileStore.activeSourceID == source.id {
                                Label("Active", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(12)
                    }
                    .buttonStyle(.plain)
                    .cineLarkHoverSurface(cornerRadius: 14)
                }
            }

            Divider()

            HStack {
                ForEach(sourceStore.availablePlugins, id: \.id) { plugin in
                    Button {
                        sourceStore.send(.view(.beginSetup(plugin.id)))
                    } label: {
                        Label("Add \(plugin.displayName)", systemImage: "plus.circle")
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    private var remoteStateCard: some View {
        CineLarkSettingsCard(
            "Emby User State",
            subtitle: "Optional compatibility with the selected Emby user.",
            systemImage: "arrow.triangle.2.circlepath.icloud"
        ) {
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
            .buttonStyle(.glass)
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
        CineLarkSettingsCard(
            setup.legacyPluginID == nil
                ? "Set Up \(pluginName(setup.pluginID))"
                : "Reconnect \(setup.displayName) as \(pluginName(setup.pluginID))",
            subtitle: setup.validatedConfiguration == nil
                ? "Verify the server before entering account credentials."
                : "Server verified. Sign in to finish configuration.",
            systemImage: "server.rack"
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
                .buttonStyle(.glass)
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    }
                    .buttonStyle(.plain)
                    .cineLarkHoverSurface(cornerRadius: 12)
                }
            }

            TextField("Server URL", text: setupBinding(\.baseURL, action: SourceFeature.Action.View.updateBaseURL))
                .textContentType(.URL)
                .textFieldStyle(.roundedBorder)
            TextField("Display name", text: setupBinding(\.displayName, action: SourceFeature.Action.View.updateDisplayName))
                .textFieldStyle(.roundedBorder)

            if setup.validatedConfiguration == nil {
                Button("Verify Server") {
                    sourceStore.send(.view(.validate))
                }
                .buttonStyle(.glassProminent)
                .disabled(setup.baseURL.isEmpty || setup.isValidating)
            } else {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                Button("Sign In & Save") {
                    sourceStore.send(
                        .view(.authenticate(username: username, password: password))
                    )
                    password = ""
                }
                .buttonStyle(.glassProminent)
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
            .buttonStyle(.glass)
        }
    }

    private var activeManifest: ProfileManifest? {
        profileStore.manifest
    }

    private var syncStatusTitle: String {
        switch profileStore.cloudSyncStatus.phase {
        case .localOnly:
            return "Local Only"
        case .checking:
            return "Checking iCloud"
        case .synchronizing:
            return "Synchronizing"
        case .upToDate:
            return "Up to Date"
        case .failed:
            return "Needs Attention"
        }
    }

    private var syncStatusSymbol: String {
        switch profileStore.cloudSyncStatus.phase {
        case .localOnly:
            return "icloud.slash"
        case .checking:
            return "icloud.and.arrow.down"
        case .synchronizing:
            return "icloud.and.arrow.up"
        case .upToDate:
            return "checkmark.icloud"
        case .failed:
            return "exclamationmark.icloud"
        }
    }

    private var syncStatusColor: Color {
        switch profileStore.cloudSyncStatus.phase {
        case .localOnly, .checking:
            return .secondary
        case .synchronizing:
            return .blue
        case .upToDate:
            return .green
        case .failed:
            return .red
        }
    }

    private var syncStatusDetail: String {
        switch profileStore.cloudSyncStatus.phase {
        case .localOnly:
            return "Personal viewing history remains available on this Mac. Sign in to iCloud to synchronize it."
        case .checking:
            return "CineLark is waiting for the initial iCloud import. Local viewing history remains usable."
        case .synchronizing:
            return "Changes are being exchanged with your private iCloud database. Local data remains authoritative in the UI."
        case .upToDate:
            return "iCloud is available. Synchronization continues automatically when local or remote facts change."
        case .failed:
            return "Viewing history remains safe locally while the persistent container retries automatically."
        }
    }

    private var syncActivityDescription: String {
        profileStore.cloudSyncStatus.activeOperations
            .sorted { $0.rawValue < $1.rawValue }
            .map {
                switch $0 {
                case .setup: "Preparing"
                case .importing: "Downloading"
                case .exporting: "Uploading"
                }
            }
            .joined(separator: ", ")
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
