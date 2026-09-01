import SwiftUI
import Sparkle
import ComposableArchitecture

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
            case .ready:
                LibraryView(
                    store: store.scope(state: \.navigation, action: \.navigation),
                    libraryStore: store.scope(state: \.library, action: \.library),
                    searchStore: store.scope(state: \.search, action: \.search),
                    insightsStore: store.scope(state: \.insights, action: \.insights),
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
            remote.updatePlayback(active.flatMap { active in
                guard active.didReportStarted else { return nil }
                return RemoteCoordinator.PlaybackState(
                    playbackID: active.id,
                    state: active.isPaused ? .paused : .playing,
                    title: active.title,
                    positionSeconds: active.positionSeconds,
                    durationSeconds: active.durationSeconds,
                    speed: active.speed,
                    volume: active.volume,
                    muted: active.muted,
                    fullscreen: active.fullscreen,
                    audioTracks: active.audioTracks,
                    subtitleTracks: active.subtitleTracks
                )
            })
        }
        .overlay(alignment: .bottomTrailing) {
            if store.playback.isStarting {
                Label(language.localized("playback.preparing"), systemImage: "play.circle")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .glassEffect(.regular, in: Capsule())
                    .padding(24)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .alert(
            language.localized("playback.unavailable"),
            isPresented: Binding(
                get: { store.playback.failure != nil },
                set: { if !$0 { store.send(.playback(.view(.dismissFailure))) } }
            )
        ) {
            if store.playback.canRetry {
                Button(language.localized("general.retry")) {
                    store.send(.playback(.view(.retry)))
                }
            }
            Button(language.localized("general.dismiss"), role: .cancel) {
                store.send(.playback(.view(.dismissFailure)))
            }
        } message: {
            Text(language.userFacingError(store.playback.failure?.message))
        }
        .preferredColorScheme(.dark)
    }
}
