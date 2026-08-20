import SwiftUI

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
                    Color.white.opacity(
                        isHovering ? hoverFillOpacity : normalFillOpacity
                    )
                )
            }
            .overlay {
                shape.stroke(
                    Color.white.opacity(
                        isHovering ? hoverStrokeOpacity : normalStrokeOpacity
                    ),
                    lineWidth: 1
                )
            }
            .contentShape(shape)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

struct CineLarkPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

extension View {
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
