import SwiftUI

struct RootView: View {
    @Environment(\.appLanguage) private var language
    @Environment(ShortcutCoordinator.self) private var shortcuts
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .launching:
                ZStack {
                    CineLarkPageBackground()
                    VStack(spacing: 16) {
                        Image(systemName: "bird.fill")
                            .font(.system(size: 40, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
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
            case .signedOut:
                LoginView(model: model)
            case .signedIn:
                LibraryView(model: model)
            }
        }
        .task {
            await model.bootstrap()
        }
        .overlay(alignment: .bottom) {
            if shortcuts.showsHints {
                ShortcutNavigationOverlay()
                    .padding(.bottom, 24)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .preferredColorScheme(.dark)
    }
}
