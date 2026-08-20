import SwiftUI

struct RootView: View {
    @Environment(\.appLanguage) private var language
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .launching:
                ProgressView(language.localized("root.opening"))
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                LoginView(model: model)
            case .signedIn:
                LibraryView(model: model)
            }
        }
        .task {
            await model.bootstrap()
        }
        .preferredColorScheme(.dark)
    }
}
