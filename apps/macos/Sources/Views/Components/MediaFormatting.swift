import Foundation

extension Double {
    var cineLarkDuration: String {
        let totalMinutes = Int(self) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

extension Int64 {
    var cineLarkByteCount: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
