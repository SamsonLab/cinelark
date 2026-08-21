import SwiftUI

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
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                content
            }
            .padding(.vertical, 10)
        }
        .contentMargins(
            .horizontal,
            CineLarkDesign.Layout.contentMargin,
            for: .scrollContent
        )
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .focusSection()
    }
}

struct CineLarkFilterButton: View {
    @Environment(\.appLanguage) private var language

    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

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
    }

    private var label: String {
        "\(title)  \(count.formatted())"
    }
}

struct CineLarkCinematicBackdrop: View {
    let url: URL?
    var height: CGFloat = 620
    var leadingShade = 0.82

    var body: some View {
        ArtworkView(url: url)
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
    let cornerRadius: CGFloat
    var normalFillOpacity: Double = 0.05
    var hoverFillOpacity: Double = 0.11
    var normalStrokeOpacity: Double = 0.10
    var hoverStrokeOpacity: Double = 0.24

    @State private var isHovering = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(
                    Color.white.opacity(isHovering ? hoverFillOpacity : normalFillOpacity)
                )
            }
            .overlay {
                shape.stroke(
                    Color.white.opacity(isHovering ? hoverStrokeOpacity : normalStrokeOpacity),
                    lineWidth: 1
                )
            }
            .contentShape(shape)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.14), value: isHovering)
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
}
