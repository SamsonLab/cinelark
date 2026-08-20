import Foundation

extension Int64 {
    var cineLarkByteCount: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
