import Foundation

extension Double {
    var cineLarkRating: String {
        formatted(.number.precision(.fractionLength(0...1)))
    }
}

extension Int64 {
    var cineLarkByteCount: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
