import SwiftUI

struct CineLarkBrandMark: View {
    let size: CGFloat

    var body: some View {
        Image("maskAppIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
