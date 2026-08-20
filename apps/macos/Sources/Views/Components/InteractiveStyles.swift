import SwiftUI

struct CineLarkHoverSurface: ViewModifier {
    let cornerRadius: CGFloat
    var normalFillOpacity: Double = 0.05
    var hoverFillOpacity: Double = 0.11
    var normalStrokeOpacity: Double = 0.10
    var hoverStrokeOpacity: Double = 0.24
    var accentOnHover = false
    var liftsOnHover = false

    @State private var isHovering = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(
                    accentOnHover && isHovering
                        ? Color.accentColor.opacity(0.12)
                        : Color.white.opacity(
                            isHovering ? hoverFillOpacity : normalFillOpacity
                        )
                )
            }
            .overlay {
                shape.stroke(
                    accentOnHover && isHovering
                        ? Color.accentColor.opacity(0.65)
                        : Color.white.opacity(
                            isHovering ? hoverStrokeOpacity : normalStrokeOpacity
                        ),
                    lineWidth: 1
                )
            }
            .contentShape(shape)
            .scaleEffect(liftsOnHover && isHovering ? 1.008 : 1)
            .offset(y: liftsOnHover && isHovering ? -1 : 0)
            .shadow(
                color: .black.opacity(liftsOnHover && isHovering ? 0.30 : 0),
                radius: 12,
                y: 6
            )
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.16), value: isHovering)
    }
}

extension View {
    func cineLarkHoverSurface(
        cornerRadius: CGFloat,
        normalFillOpacity: Double = 0.05,
        hoverFillOpacity: Double = 0.11,
        normalStrokeOpacity: Double = 0.10,
        hoverStrokeOpacity: Double = 0.24,
        accentOnHover: Bool = false,
        liftsOnHover: Bool = false
    ) -> some View {
        modifier(
            CineLarkHoverSurface(
                cornerRadius: cornerRadius,
                normalFillOpacity: normalFillOpacity,
                hoverFillOpacity: hoverFillOpacity,
                normalStrokeOpacity: normalStrokeOpacity,
                hoverStrokeOpacity: hoverStrokeOpacity,
                accentOnHover: accentOnHover,
                liftsOnHover: liftsOnHover
            )
        )
    }
}
