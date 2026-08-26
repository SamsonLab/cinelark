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
            if store.bootstrap != .ready {
                ZStack {
                    CineLarkPageBackground()
                    VStack(spacing: 16) {
                        CineLarkBrandMark(size: 72)
                            .frame(width: 88, height: 88)
                            .glassEffect(.regular, in: Circle())

                        Text("CineLark")
                            .font(.system(size: 34, weight: .bold))

                        ProgressView()
                            .controlSize(.large)

                        Text(language.localized("root.opening"))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
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
