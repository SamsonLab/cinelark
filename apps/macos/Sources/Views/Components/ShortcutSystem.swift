import AppKit
import CineLarkDomain
import Observation
import SwiftUI

enum CineLarkShortcutChord: Hashable {
    case command(Int)
    case commandKey(Character)

    var label: String {
        switch self {
        case .command(let number): "⌘\(number)"
        case .commandKey(let key): "⌘\(key.uppercased())"
        }
    }

    fileprivate var keyEquivalent: KeyEquivalent {
        switch self {
        case .command(let number):
            KeyEquivalent(Character(String(number)))
        case .commandKey(let key):
            KeyEquivalent(key)
        }
    }

    fileprivate var modifiers: EventModifiers {
        switch self {
        case .command, .commandKey: [.command]
        }
    }
}

enum CineLarkFixedCommand: Hashable {
    case navigation(Int)
    case refresh

    fileprivate var keyCode: UInt16? {
        switch self {
        case .navigation(1): 18
        case .navigation(2): 19
        case .navigation(3): 20
        case .navigation(4): 21
        case .navigation(5): 23
        case .refresh: 15
        default: nil
        }
    }
}

enum CineLarkFocusDirection {
    case left
    case right
    case up
    case down
}

@Observable
@MainActor
final class ShortcutCoordinator {
    private(set) var showsHints = false

    @ObservationIgnored private var eventMonitor: Any?
    @ObservationIgnored private var commandHoldTask: Task<Void, Never>?
    @ObservationIgnored private var isCommandPressed = false
    @ObservationIgnored private var backAction: (() -> Bool)?
    @ObservationIgnored private var fixedActions: [UInt16: () -> Bool] = [:]
    @ObservationIgnored private var openMediaAction: ((MediaSummary) -> Bool)?
    @ObservationIgnored private var directionalAction: (
        owner: UUID,
        move: (CineLarkFocusDirection) -> Bool,
        activate: () -> Bool
    )?

    func start() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .swipe]
        ) { [weak self] event in
            guard let self else { return event }
            let type = event.type
            let commandPressed = event.modifierFlags.contains(.command)
            let keyCode = event.keyCode
            let characters = event.charactersIgnoringModifiers
            let deltaX = event.deltaX
            let deltaY = event.deltaY
            let shouldConsume = MainActor.assumeIsolated {
                self.handle(
                    type: type,
                    commandPressed: commandPressed,
                    keyCode: keyCode,
                    characters: characters,
                    deltaX: deltaX,
                    deltaY: deltaY
                )
            }
            return shouldConsume ? nil : event
        }
    }

    func stop() {
        commandHoldTask?.cancel()
        commandHoldTask = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isCommandPressed = false
        showsHints = false
    }

    func setBackAction(_ action: (() -> Bool)?) {
        backAction = action
    }

    func setFixedAction(
        _ command: CineLarkFixedCommand,
        action: (() -> Bool)?
    ) {
        guard let keyCode = command.keyCode else { return }
        fixedActions[keyCode] = action
    }

    func setDirectionalAction(
        owner: UUID,
        move: @escaping (CineLarkFocusDirection) -> Bool,
        activate: @escaping () -> Bool
    ) {
        directionalAction = (owner, move, activate)
    }

    func clearDirectionalAction(owner: UUID) {
        guard directionalAction?.owner == owner else { return }
        directionalAction = nil
    }

    func setOpenMediaAction(_ action: ((MediaSummary) -> Bool)?) {
        openMediaAction = action
    }

    @discardableResult
    func openMedia(_ item: MediaSummary) -> Bool {
        openMediaAction?(item) == true
    }

    @discardableResult
    func navigateBack() -> Bool {
        backAction?() == true
    }

    private func handle(
        type: NSEvent.EventType,
        commandPressed: Bool,
        keyCode: UInt16,
        characters: String?,
        deltaX: CGFloat,
        deltaY: CGFloat
    ) -> Bool {
        switch type {
        case .flagsChanged:
            updateCommandState(commandPressed)
            return false
        case .keyDown:
            if commandPressed, let action = fixedActions[keyCode] {
                return action()
            }
            guard !isEditingText, !hasPresentedModal else { return false }
            if let direction = focusDirection(for: keyCode),
               directionalAction?.move(direction) == true {
                return true
            }
            if isConfirmationKey(keyCode: keyCode, characters: characters),
               directionalAction?.activate() == true {
                return true
            }
            if keyCode == 51 || (commandPressed && (keyCode == 33 || keyCode == 123)) {
                return navigateBack()
            }
            return false
        case .swipe:
            guard !hasPresentedModal,
                  abs(deltaX) > abs(deltaY),
                  deltaX > 0 else {
                return false
            }
            return navigateBack()
        default:
            return false
        }
    }

    private func focusDirection(for keyCode: UInt16) -> CineLarkFocusDirection? {
        switch keyCode {
        case 123: .left
        case 124: .right
        case 125: .down
        case 126: .up
        default: nil
        }
    }

    private func isConfirmationKey(
        keyCode: UInt16,
        characters: String?
    ) -> Bool {
        keyCode == 36 || keyCode == 49 || keyCode == 76 ||
            characters == "\r" || characters == " "
    }

    private func updateCommandState(_ isPressed: Bool) {
        guard isPressed != isCommandPressed else { return }
        isCommandPressed = isPressed
        commandHoldTask?.cancel()

        if isPressed {
            commandHoldTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self, self.isCommandPressed else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    self.showsHints = true
                }
            }
        } else {
            commandHoldTask = nil
            withAnimation(.easeOut(duration: 0.14)) {
                showsHints = false
            }
        }
    }

    private var isEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if let textView = responder as? NSTextView {
            return textView.isEditable
        }
        if let textField = responder as? NSTextField {
            return textField.isEditable
        }
        return false
    }

    private var hasPresentedModal: Bool {
        guard let window = NSApp.keyWindow else { return false }
        return window.sheetParent != nil || window.attachedSheet != nil
    }
}

private struct FixedShortcutModifier: ViewModifier {
    @Environment(ShortcutCoordinator.self) private var coordinator
    let chord: CineLarkShortcutChord
    let alignment: Alignment

    func body(content: Content) -> some View {
        content
            .keyboardShortcut(chord.keyEquivalent, modifiers: chord.modifiers)
            .overlay(alignment: alignment) {
                if coordinator.showsHints {
                    ShortcutHintBadge(chord: chord)
                        .padding(6)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
    }
}

private struct ShortcutHintBadge: View {
    let chord: CineLarkShortcutChord

    var body: some View {
        Text(chord.label)
            .font(.caption2.weight(.semibold).monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .glassEffect(.regular, in: Capsule())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct ShortcutNavigationOverlay: View {
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack(spacing: 10) {
            Text("← ↑ ↓ →")
                .font(.callout.weight(.semibold).monospaced())
            Text(language.localized("shortcut.navigate"))
            Divider()
                .frame(height: 14)
            Text("↩ / Space")
                .font(.callout.weight(.semibold).monospaced())
            Text(language.localized("shortcut.activate"))
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 38)
        .glassEffect(.regular, in: Capsule())
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    @ViewBuilder
    func cineLarkShortcut(
        _ chord: CineLarkShortcutChord?,
        alignment: Alignment = .trailing
    ) -> some View {
        if let chord {
            modifier(FixedShortcutModifier(chord: chord, alignment: alignment))
        } else {
            self
        }
    }

    func cineLarkShortcut(
        _ chord: CineLarkShortcutChord,
        alignment: Alignment = .trailing
    ) -> some View {
        modifier(FixedShortcutModifier(chord: chord, alignment: alignment))
    }

}
