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
    case focusSearch

    fileprivate var keyCode: UInt16? {
        switch self {
        case .navigation(1): 18
        case .navigation(2): 19
        case .navigation(3): 20
        case .navigation(4): 21
        case .navigation(5): 23
        case .refresh: 15
        case .focusSearch: 3
        default: nil
        }
    }
}

enum CineLarkFocusDirection: Equatable {
    case left
    case right
    case up
    case down
}

enum CineLarkSection: String, CaseIterable {
    case home
    case movies
    case series
    case favorites
    case search
}

enum CineLarkInputModality: Equatable {
    case pointer
    case keyboard
}

@Observable
@MainActor
final class ShortcutCoordinator {
    private(set) var showsHints = false
    private(set) var inputModality: CineLarkInputModality = .pointer
    private(set) var currentSection: CineLarkSection = .home
    var onSectionChanged: (@MainActor @Sendable () -> Void)?

    var usesKeyboardNavigation: Bool {
        inputModality == .keyboard
    }

    private struct NavigationSurface {
        let owner: UUID
        let registrationOrder: UInt64
        let handlesPresentedModal: Bool
        let handoffToKeyboard: (() -> Void)?
        let move: (CineLarkFocusDirection) -> Bool
        let activate: () -> Bool
        let navigateBack: (() -> Bool)?
    }

    @ObservationIgnored private var eventMonitor: Any?
    @ObservationIgnored private var applicationObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var commandHoldTask: Task<Void, Never>?
    @ObservationIgnored private var isCommandPressed = false
    @ObservationIgnored private var nextRegistrationOrder: UInt64 = 0
    @ObservationIgnored private var backAction: (() -> Bool)?
    @ObservationIgnored private var fixedActions: [UInt16: () -> Bool] = [:]
    @ObservationIgnored private var sectionActions: [CineLarkSection: () -> Bool] = [:]
    @ObservationIgnored private var openMediaAction: ((MediaSummary) -> Bool)?
    @ObservationIgnored private var openCollectionAction: ((MediaCollection) -> Bool)?
    @ObservationIgnored private var openPersonAction: ((PersonCredit) -> Bool)?
    @ObservationIgnored private var navigationSurfaces: [UUID: NavigationSurface] = [:]

    func start() {
        installApplicationObserversIfNeeded()
        installEventMonitorIfNeeded()
        resetCommandState()
    }

    private func installEventMonitorIfNeeded() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .flagsChanged,
                .keyDown,
                .swipe,
                .mouseMoved,
                .leftMouseDown,
                .rightMouseDown,
                .otherMouseDown,
                .leftMouseDragged,
                .rightMouseDragged,
                .otherMouseDragged,
                .scrollWheel
            ]
        ) { [weak self] event in
            guard let self else { return event }
            let shouldConsume = MainActor.assumeIsolated {
                self.handle(event)
            }
            return shouldConsume ? nil : event
        }
    }

    func stop() {
        resetCommandState()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        for observer in applicationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        applicationObservers.removeAll()
        navigationSurfaces.removeAll()
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

    func setNavigationSurface(
        owner: UUID,
        handlesPresentedModal: Bool = false,
        handoffToKeyboard: (() -> Void)? = nil,
        move: @escaping (CineLarkFocusDirection) -> Bool,
        activate: @escaping () -> Bool,
        navigateBack: (() -> Bool)? = nil
    ) {
        let registrationOrder: UInt64
        if let existing = navigationSurfaces[owner] {
            registrationOrder = existing.registrationOrder
        } else {
            nextRegistrationOrder &+= 1
            registrationOrder = nextRegistrationOrder
        }
        navigationSurfaces[owner] = NavigationSurface(
            owner: owner,
            registrationOrder: registrationOrder,
            handlesPresentedModal: handlesPresentedModal,
            handoffToKeyboard: handoffToKeyboard,
            move: move,
            activate: activate,
            navigateBack: navigateBack
        )
    }

    func setSectionAction(_ section: CineLarkSection, action: (() -> Bool)?) {
        sectionActions[section] = action
    }

    func removeNavigationSurface(owner: UUID) {
        navigationSurfaces.removeValue(forKey: owner)
    }

    func setOpenMediaAction(_ action: ((MediaSummary) -> Bool)?) {
        openMediaAction = action
    }

    func setOpenCollectionAction(_ action: ((MediaCollection) -> Bool)?) {
        openCollectionAction = action
    }

    func setOpenPersonAction(_ action: ((PersonCredit) -> Bool)?) {
        openPersonAction = action
    }

    @discardableResult
    func openMedia(_ item: MediaSummary) -> Bool {
        openMediaAction?(item) == true
    }

    @discardableResult
    func openCollection(_ collection: MediaCollection) -> Bool {
        openCollectionAction?(collection) == true
    }

    @discardableResult
    func openPerson(_ person: PersonCredit) -> Bool {
        openPersonAction?(person) == true
    }

    @discardableResult
    func navigateBack() -> Bool {
        backAction?() == true
    }

    @discardableResult
    func moveFocus(_ direction: CineLarkFocusDirection) -> Bool {
        guard !isEditingText else { return false }
        let surface = activeNavigationSurface
        if hasPresentedModal, surface?.handlesPresentedModal != true { return false }
        handoffSelectionIfNeeded(to: surface)
        guard surface?.move(direction) == true else { return false }
        setInputModality(.keyboard)
        return true
    }

    @discardableResult
    func activateFocusedItem() -> Bool {
        guard !isEditingText else { return false }
        let surface = activeNavigationSurface
        if hasPresentedModal, surface?.handlesPresentedModal != true { return false }
        handoffSelectionIfNeeded(to: surface)
        guard surface?.activate() == true else { return false }
        setInputModality(.keyboard)
        return true
    }

    @discardableResult
    func navigateBackSemantically() -> Bool {
        guard !isEditingText else { return false }
        let surface = activeNavigationSurface
        if surface?.navigateBack?() == true {
            setInputModality(.keyboard)
            return true
        }
        guard !hasPresentedModal, navigateBack() else { return false }
        setInputModality(.keyboard)
        return true
    }

    @discardableResult
    func openSection(_ section: CineLarkSection) -> Bool {
        guard !hasPresentedModal, sectionActions[section]?() == true else { return false }
        reportSection(section)
        setInputModality(.keyboard)
        return true
    }

    func reportSection(_ section: CineLarkSection) {
        guard currentSection != section else { return }
        currentSection = section
        onSectionChanged?()
    }

    private func activatePointerInput() {
        setInputModality(.pointer)
    }

    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .flagsChanged:
            updateCommandState(event.modifierFlags.contains(.command))
            return false
        case .mouseMoved,
             .leftMouseDown,
             .rightMouseDown,
             .otherMouseDown,
             .leftMouseDragged,
             .rightMouseDragged,
             .otherMouseDragged,
             .scrollWheel:
            activatePointerInput()
            return false
        case .keyDown:
            let commandPressed = event.modifierFlags.contains(.command)
            let keyCode = event.keyCode
            let characters = event.charactersIgnoringModifiers
            if commandPressed, !hasPresentedModal, let action = fixedActions[keyCode] {
                guard action() else { return false }
                setInputModality(.keyboard)
                return true
            }
            guard !isEditingText else { return false }
            let navigationSurface = activeNavigationSurface
            if hasPresentedModal,
               navigationSurface?.handlesPresentedModal != true {
                return false
            }
            if let direction = focusDirection(for: keyCode) {
                return moveFocus(direction)
            }
            if isConfirmationKey(keyCode: keyCode, characters: characters) {
                return activateFocusedItem()
            }
            if isBackKey(
                keyCode: keyCode,
                characters: characters,
                commandPressed: commandPressed
            ) {
                return navigateBackSemantically()
            }
            return false
        case .swipe:
            activatePointerInput()
            let deltaX = event.deltaX
            let deltaY = event.deltaY
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

    private func setInputModality(_ modality: CineLarkInputModality) {
        guard modality != inputModality else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            inputModality = modality
        }
    }

    private func handoffSelectionIfNeeded(to surface: NavigationSurface?) {
        guard inputModality == .pointer else { return }
        surface?.handoffToKeyboard?()
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

    private func isBackKey(
        keyCode: UInt16,
        characters: String?,
        commandPressed: Bool
    ) -> Bool {
        keyCode == 51 || keyCode == 53 || characters == "\u{1B}" ||
            (commandPressed && (keyCode == 33 || keyCode == 123))
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

    private var activeNavigationSurface: NavigationSurface? {
        navigationSurfaces.values.max {
            $0.registrationOrder < $1.registrationOrder
        }
    }

    private func installApplicationObserversIfNeeded() {
        guard applicationObservers.isEmpty else { return }
        let center = NotificationCenter.default
        applicationObservers = [
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.installEventMonitorIfNeeded()
                    self?.resetCommandState()
                }
            },
            center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.resetCommandState()
                }
            }
        ]
    }

    private func resetCommandState() {
        commandHoldTask?.cancel()
        commandHoldTask = nil
        isCommandPressed = false
        showsHints = false
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

private struct KeyboardSelectionHintModifier: ViewModifier {
    @Environment(\.appLanguage) private var language
    @Environment(ShortcutCoordinator.self) private var coordinator
    let isActive: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if isActive && coordinator.usesKeyboardNavigation {
                HStack(spacing: 5) {
                    Text("↩")
                        .font(.caption.weight(.bold).monospaced())
                    Text(language.localized("shortcut.activate"))
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .glassEffect(.regular, in: Capsule())
                .padding(8)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
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
            Divider()
                .frame(height: 14)
            Text("Esc / ⌫")
                .font(.callout.weight(.semibold).monospaced())
            Text(language.localized("shortcut.back"))
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

    func cineLarkKeyboardSelectionHint(isActive: Bool) -> some View {
        modifier(KeyboardSelectionHintModifier(isActive: isActive))
    }

}
