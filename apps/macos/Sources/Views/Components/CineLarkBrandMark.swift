import AppKit
import SwiftUI

struct CineLarkBrandMark: View {
    private static let image: NSImage = {
        guard
            let url = Bundle.main.url(forResource: "maskAppIcon", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        else {
            return NSImage()
        }
        return image
    }()

    let size: CGFloat

    var body: some View {
        Image(nsImage: Self.image)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
