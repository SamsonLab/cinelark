import AppKit
import SwiftUI
import CineLarkPluginAPI

private final class HorizontalScrollerHiderView: NSView {
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        hideEnclosingHorizontalScroller()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideEnclosingHorizontalScroller()
    }

    override func layout() {
        super.layout()
        hideEnclosingHorizontalScroller()
    }

    private func hideEnclosingHorizontalScroller() {
        guard let scrollView = enclosingScrollView else { return }
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScroller?.isHidden = true
    }
}

private struct HorizontalScrollerHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        HorizontalScrollerHiderView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func cineLarkHorizontalScrollIndicatorsHidden() -> some View {
        background(HorizontalScrollerHider())
    }
}

private struct MediaTransitionNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var mediaTransitionNamespace: Namespace.ID? {
        get { self[MediaTransitionNamespaceKey.self] }
        set { self[MediaTransitionNamespaceKey.self] = newValue }
    }
}

enum CineLarkDesign {
    enum Palette {
        static let canvas = Color(red: 0.025, green: 0.03, blue: 0.04)
        static let elevatedCanvas = Color(red: 0.055, green: 0.065, blue: 0.085)
        static let progress = Color.blue
        static let favorite = Color.orange
        static let watched = Color.green
        static let badgeBackground = Color.black.opacity(0.52)
        static let badgeStroke = Color.white.opacity(0.18)
    }

    enum Layout {
        static let contentMargin: CGFloat = 48
        static let compactMargin: CGFloat = 32
        static let pageTopInset: CGFloat = 34
        static let focusSafeTopInset: CGFloat = 52
        static let focusScrollClearance: CGFloat = 18
        static let shelfSpacing: CGFloat = 26
        static let lockupSpacing: CGFloat = 11
        static let posterGridColumnSpacing: CGFloat = 32
        static let posterGridRowSpacing: CGFloat = 38
    }

    enum Typography {
        static let pageTitle = Font.system(size: 44, weight: .bold)
        static let heroTitle = Font.system(size: 58, weight: .bold)
        static let sectionTitle = Font.system(size: 25, weight: .semibold)
        static let cardTitle = Font.system(size: 16, weight: .semibold)
        static let cardMetadata = Font.caption.weight(.medium)
    }

    enum Media {
        static let posterWidth: CGFloat = 184
        static let posterHeight: CGFloat = 276
        static let landscapeWidth: CGFloat = 320
        static let landscapeHeight: CGFloat = 180
    }

    enum Shape {
        static let cardRadius: CGFloat = 18
    }

    enum Motion {
        static let focus = Animation.spring(duration: 0.26, bounce: 0.16)
        static let hero = Animation.easeInOut(duration: 0.28)
    }
}

struct CineLarkPageBackground: View {
    var body: some View {
        ZStack {
            CineLarkDesign.Palette.canvas
            RadialGradient(
                colors: [Color.blue.opacity(0.09), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 760
            )
        }
        .ignoresSafeArea()
    }
}

struct CineLarkPageHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(CineLarkDesign.Typography.pageTitle)

            if let subtitle {
                Text(subtitle)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
        .padding(.top, CineLarkDesign.Layout.pageTopInset)
        .padding(.bottom, 18)
    }
}

struct CineLarkFilterBar<Content: View>: View {
    private let selectedID: String?
    private let content: Content

    init(selectedID: String? = nil, @ViewBuilder content: () -> Content) {
        self.selectedID = selectedID
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    content
                }
                .scrollTargetLayout()
                .padding(.vertical, 10)
                .cineLarkHorizontalScrollIndicatorsHidden()
            }
            .contentMargins(
                .horizontal,
                CineLarkDesign.Layout.contentMargin,
                for: .scrollContent
            )
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .focusSection()
            .onAppear {
                scrollSelectedID(scrollProxy)
            }
            .onChange(of: selectedID) {
                scrollSelectedID(scrollProxy)
            }
        }
    }

    private func scrollSelectedID(_ scrollProxy: ScrollViewProxy) {
        guard let selectedID else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            scrollProxy.scrollTo(selectedID, anchor: .center)
        }
    }
}

struct CineLarkFilterButton: View {
    @Environment(\.appLanguage) private var language
    @Environment(ShortcutCoordinator.self) private var shortcuts

    let title: String
    let count: Int
    let isSelected: Bool
    let isKeyboardSelected: Bool
    let onPointerSelection: ((Bool) -> Void)?
    let action: () -> Void

    init(
        title: String,
        count: Int,
        isSelected: Bool,
        isKeyboardSelected: Bool = false,
        onPointerSelection: ((Bool) -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.count = count
        self.isSelected = isSelected
        self.isKeyboardSelected = isKeyboardSelected
        self.onPointerSelection = onPointerSelection
        self.action = action
    }

    var body: some View {
        Group {
            if isSelected {
                Button(action: action) {
                    Label(label, systemImage: "checkmark")
                }
                .buttonStyle(.glassProminent)
                .accessibilityValue(language.localized("general.selected"))
            } else {
                Button(label, action: action)
                    .buttonStyle(.glass)
                    .accessibilityValue(language.localized("general.not_selected"))
            }
        }
        .controlSize(.large)
        .focusEffectDisabled()
        .cineLarkFocusSurface(
            isActive: shortcuts.usesKeyboardNavigation && isKeyboardSelected,
            cornerRadius: 18,
            scale: 1.02
        )
        .cineLarkPointerSelection { hovering in
            onPointerSelection?(hovering)
        }
    }

    private var label: String {
        "\(title)  \(count.formatted())"
    }
}

struct CineLarkCinematicBackdrop: View {
    let url: URL?
    var locator: MediaLocatorID?
    var height: CGFloat = 620
    var leadingShade = 0.82

    var body: some View {
        ArtworkView(url: url, locator: locator, artworkKind: "backdrop")
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .overlay {
                LinearGradient(
                    colors: [
                        .black.opacity(leadingShade),
                        .black.opacity(0.25),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .overlay {
                LinearGradient(
                    colors: [
                        .clear,
                        CineLarkDesign.Palette.canvas.opacity(0.55),
                        CineLarkDesign.Palette.canvas
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .backgroundExtensionEffect()
            .allowsHitTesting(false)
    }
}

private struct CineLarkFocusSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isActive: Bool
    let cornerRadius: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        let activeScale = reduceMotion ? 1 : scale
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(isActive ? 0.58 : 0.06),
                        lineWidth: isActive ? 1.25 : 0.75
                    )
                    .allowsHitTesting(false)
            }
            .scaleEffect(isActive ? activeScale : 1)
            .offset(y: isActive && !reduceMotion ? -5 : 0)
            .shadow(
                color: isActive ? .black.opacity(0.58) : .clear,
                radius: isActive ? 16 : 0,
                y: isActive ? 9 : 0
            )
            .zIndex(isActive ? 1 : 0)
            .animation(reduceMotion ? nil : CineLarkDesign.Motion.focus, value: isActive)
    }
}

struct CineLarkHoverSurface: ViewModifier {
    @Environment(ShortcutCoordinator.self) private var shortcuts
    let cornerRadius: CGFloat
    var normalFillOpacity: Double = 0.05
    var hoverFillOpacity: Double = 0.11
    var normalStrokeOpacity: Double = 0.10
    var hoverStrokeOpacity: Double = 0.24

    @State private var isHovering = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let presentsHover = shortcuts.inputModality == .pointer && isHovering
        content
            .background {
                shape.fill(
                    Color.white.opacity(presentsHover ? hoverFillOpacity : normalFillOpacity)
                )
            }
            .overlay {
                shape.stroke(
                    Color.white.opacity(
                        presentsHover ? hoverStrokeOpacity : normalStrokeOpacity
                    ),
                    lineWidth: 1
                )
            }
            .contentShape(shape)
            .onHover { hovering in
                isHovering = hovering
            }
            .animation(.easeOut(duration: 0.14), value: presentsHover)
    }
}

private struct CineLarkPointerSelectionModifier: ViewModifier {
    @Environment(ShortcutCoordinator.self) private var shortcuts
    let selectionChanged: (Bool) -> Void
    @State private var isPointerInside = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isPointerInside = hovering
                if !hovering || shortcuts.inputModality == .pointer {
                    selectionChanged(hovering)
                }
            }
            .onChange(of: shortcuts.inputModality) {
                if shortcuts.inputModality == .pointer, isPointerInside {
                    selectionChanged(true)
                }
            }
            .onDisappear {
                if isPointerInside { selectionChanged(false) }
            }
    }
}

struct CineLarkPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

struct CineLarkSettingsPageHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 15))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CineLarkSettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.white.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }
}

extension View {
    @ViewBuilder
    func mediaMatchedGeometry<ID: Hashable>(
        id: ID?,
        namespace: Namespace.ID?,
        isSource: Bool
    ) -> some View {
        if let id, let namespace {
            matchedGeometryEffect(
                id: id,
                in: namespace,
                properties: .frame,
                anchor: .center,
                isSource: isSource
            )
        } else {
            self
        }
    }

    func cineLarkFocusSurface(
        isActive: Bool,
        cornerRadius: CGFloat = CineLarkDesign.Shape.cardRadius,
        scale: CGFloat = 1.055
    ) -> some View {
        modifier(
            CineLarkFocusSurfaceModifier(
                isActive: isActive,
                cornerRadius: cornerRadius,
                scale: scale
            )
        )
    }

    func cineLarkHoverSurface(
        cornerRadius: CGFloat,
        normalFillOpacity: Double = 0.05,
        hoverFillOpacity: Double = 0.11,
        normalStrokeOpacity: Double = 0.10,
        hoverStrokeOpacity: Double = 0.24
    ) -> some View {
        modifier(
            CineLarkHoverSurface(
                cornerRadius: cornerRadius,
                normalFillOpacity: normalFillOpacity,
                hoverFillOpacity: hoverFillOpacity,
                normalStrokeOpacity: normalStrokeOpacity,
                hoverStrokeOpacity: hoverStrokeOpacity
            )
        )
    }

    func cineLarkPointerSelection(
        _ selectionChanged: @escaping (Bool) -> Void
    ) -> some View {
        modifier(
            CineLarkPointerSelectionModifier(selectionChanged: selectionChanged)
        )
    }
}
