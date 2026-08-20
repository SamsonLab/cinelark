import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .launching:
                ProgressView("Opening CineLark…")
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
