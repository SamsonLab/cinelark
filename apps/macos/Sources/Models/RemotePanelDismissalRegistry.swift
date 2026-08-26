import Foundation

@MainActor
final class RemotePanelDismissalRegistry {
    private var presentation: (id: UUID, dismiss: @MainActor () -> Void)?

    func register(id: UUID, dismiss: @escaping @MainActor () -> Void) {
        presentation = (id, dismiss)
    }

    func unregister(id: UUID) {
        guard presentation?.id == id else { return }
        presentation = nil
    }

    @discardableResult
    func dismissIfPresented() -> Bool {
        guard let presentation else { return false }
        self.presentation = nil
        presentation.dismiss()
        return true
    }
}
