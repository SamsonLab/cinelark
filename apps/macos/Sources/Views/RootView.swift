import SwiftUI
import Sparkle
import ComposableArchitecture
import CineLarkProfile

struct RootView: View {
    @Environment(\.appLanguage) private var language
    @Environment(ShortcutCoordinator.self) private var shortcuts
    let updater: SPUUpdater
    @ObservedObject var updateMonitor: SparkleUpdateMonitor
    @Bindable var remote: RemoteCoordinator
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        Group {
            switch store.bootstrap {
            case .idle, .loading:
                ZStack {
                    CineLarkPageBackground()
                    VStack(spacing: 16) {
                        CineLarkBrandMark(size: 72)
                            .frame(width: 88, height: 88)
                            .glassEffect(.regular, in: Circle())

                        Text("CineLark")
                            .font(.system(size: 34, weight: .bold))

                        if let failure = store.profile.failure {
                            Text(String(describing: failure))
                                .font(.callout)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                            Button("Retry") {
                                store.send(.profile(.view(.reload)))
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            ProgressView()
                                .controlSize(.large)

                            Text(language.localized("root.opening"))
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            case .resolvingProfile:
                ProfileResolutionView(
                    store: store.scope(state: \.profile, action: \.profile)
                )
            case .ready:
                LibraryView(
                    store: store.scope(state: \.navigation, action: \.navigation),
                    libraryStore: store.scope(state: \.library, action: \.library),
                    searchStore: store.scope(state: \.search, action: \.search),
                    profileStore: store.scope(state: \.profile, action: \.profile)
                )
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                if let availableVersion = updateMonitor.availableVersion {
                    SparkleUpdateOverlay(
                        updater: updater,
                        availableVersion: availableVersion
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                if shortcuts.showsHints {
                    ShortcutNavigationOverlay()
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .animation(.easeOut(duration: 0.18), value: updateMonitor.availableVersion)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Open CineLark Settings")
            }
        }
        .onChange(of: store.playback.active, initial: true) { _, active in
            remote.updatePlayback(active.map {
                RemoteCoordinator.PlaybackState(
                    playbackID: $0.id,
                    state: $0.isPaused ? .paused : .playing,
                    title: $0.title,
                    positionSeconds: $0.positionSeconds,
                    durationSeconds: $0.durationSeconds,
                    speed: $0.speed,
                    volume: $0.volume,
                    muted: $0.muted,
                    fullscreen: $0.fullscreen,
                    audioTracks: $0.audioTracks,
                    subtitleTracks: $0.subtitleTracks
                )
            })
        }
        .preferredColorScheme(.dark)
    }
}

private struct ProfileResolutionView: View {
    @Bindable var store: StoreOf<ProfileFeature>

    var body: some View {
        ZStack {
            CineLarkPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose your CineLark Profile")
                            .font(.system(size: 32, weight: .bold))
                        Text("CineLark found existing viewing history in iCloud. Choose how this installation should join it.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    if case let .requiresChoice(provisional, cloudProfiles) =
                        store.bootstrapResolution {
                        provisionalSummary(provisional)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Profiles in iCloud")
                                .font(.headline)
                            ForEach(cloudProfiles) { manifest in
                                cloudProfileCard(
                                    manifest,
                                    hasLocalHistory: provisional.hasMeaningfulData
                                )
                            }
                        }

                        Button {
                            store.send(.view(.resolveProfile(.keepSeparate)))
                        } label: {
                            Label("Keep this installation as a separate Profile", systemImage: "person.crop.circle.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    if let failure = store.failure {
                        Text(String(describing: failure))
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.vertical, 48)
                .frame(maxWidth: .infinity)
            }

            if store.isLoading {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                ProgressView()
                    .controlSize(.large)
            }
        }
    }

    private func provisionalSummary(_ manifest: ProfileManifest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("This installation", systemImage: "macbook")
                .font(.headline)
            Text(manifest.profile.name)
                .font(.title3.weight(.semibold))
            manifestFacts(manifest)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func cloudProfileCard(
        _ manifest: ProfileManifest,
        hasLocalHistory: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(manifest.profile.name)
                    .font(.title3.weight(.semibold))
                manifestFacts(manifest)
            }
            Spacer(minLength: 16)
            Button(hasLocalHistory ? "Merge Local Data" : "Use This Profile") {
                let choice: ProfileResolutionChoice = hasLocalHistory
                    ? .mergeIntoCloud(manifest.id)
                    : .useCloud(manifest.id)
                store.send(.view(.resolveProfile(choice)))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func manifestFacts(_ manifest: ProfileManifest) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Updated \((manifest.lastActivityAt ?? manifest.profile.modifiedAt).formatted(date: .abbreviated, time: .shortened))")
            Text("Last device: \(manifest.lastDeviceName ?? "Unknown")")
            Text("\(manifest.titleCount) titles · \(manifest.viewingSessionCount) sessions · \(manifest.favoriteCount) favorites")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}
