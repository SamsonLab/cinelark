import Foundation

public enum UHDNowTime {
    public static let ticksPerSecond: Double = 10_000_000

    public static func ticks(fromSeconds seconds: Double) -> Int64 {
        Int64((max(seconds, 0) * ticksPerSecond).rounded())
    }

    public static func seconds(fromTicks ticks: Int64) -> Double {
        Double(max(ticks, 0)) / ticksPerSecond
    }
}
