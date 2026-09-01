import ComposableArchitecture
import Foundation
import OSLog

enum CineLarkPerformanceMetric: String, CaseIterable, Sendable {
    case appBootstrap
    case cachedLibraryPage
    case refreshedLibraryPage
    case mediaDetail
    case playbackFileLoad
    case remoteCommand
    case focusMutation

    var budget: CineLarkPerformanceBudget {
        switch self {
        case .appBootstrap:
            CineLarkPerformanceBudget(targetMilliseconds: 1_500, criticalMilliseconds: 4_000)
        case .cachedLibraryPage:
            CineLarkPerformanceBudget(targetMilliseconds: 150, criticalMilliseconds: 400)
        case .refreshedLibraryPage:
            CineLarkPerformanceBudget(targetMilliseconds: 1_500, criticalMilliseconds: 5_000)
        case .mediaDetail:
            CineLarkPerformanceBudget(targetMilliseconds: 800, criticalMilliseconds: 2_500)
        case .playbackFileLoad:
            CineLarkPerformanceBudget(targetMilliseconds: 3_000, criticalMilliseconds: 10_000)
        case .remoteCommand:
            CineLarkPerformanceBudget(targetMilliseconds: 100, criticalMilliseconds: 300)
        case .focusMutation:
            CineLarkPerformanceBudget(targetMilliseconds: 16.67, criticalMilliseconds: 33.34)
        }
    }

    var signpostName: StaticString {
        switch self {
        case .appBootstrap: "App Bootstrap"
        case .cachedLibraryPage: "Cached Library Page"
        case .refreshedLibraryPage: "Refreshed Library Page"
        case .mediaDetail: "Media Detail"
        case .playbackFileLoad: "Playback File Load"
        case .remoteCommand: "Remote Command"
        case .focusMutation: "Focus Mutation"
        }
    }
}

struct CineLarkPerformanceBudget: Equatable, Sendable {
    let targetMilliseconds: Double
    let criticalMilliseconds: Double

    init(targetMilliseconds: Double, criticalMilliseconds: Double) {
        precondition(targetMilliseconds > 0)
        precondition(criticalMilliseconds >= targetMilliseconds)
        self.targetMilliseconds = targetMilliseconds
        self.criticalMilliseconds = criticalMilliseconds
    }
}

enum CineLarkPerformanceRating: String, Equatable, Sendable {
    case withinTarget
    case exceededTarget
    case exceededCritical
}

enum CineLarkPerformanceOutcome: String, Equatable, Sendable {
    case success
    case failure
    case cancelled
}

struct CineLarkPerformanceInterval: Equatable, Hashable, Sendable {
    let id: UUID
    let metric: CineLarkPerformanceMetric
}

struct PerformanceClient: Sendable {
    var start: @Sendable (CineLarkPerformanceMetric) -> CineLarkPerformanceInterval
    var finish: @Sendable (CineLarkPerformanceInterval, CineLarkPerformanceOutcome) -> Void
}

extension PerformanceClient: DependencyKey {
    static let liveValue = Self(
        start: { CineLarkPerformanceMonitor.shared.start($0) },
        finish: { CineLarkPerformanceMonitor.shared.finish($0, outcome: $1) }
    )

    static let testValue = Self(
        start: { CineLarkPerformanceInterval(id: UUID(), metric: $0) },
        finish: { _, _ in }
    )
}

extension DependencyValues {
    var performance: PerformanceClient {
        get { self[PerformanceClient.self] }
        set { self[PerformanceClient.self] = newValue }
    }
}

final class CineLarkPerformanceMonitor: @unchecked Sendable {
    static let shared = CineLarkPerformanceMonitor()

    private struct ActiveInterval {
        let startedAt: ContinuousClock.Instant
        let signpostState: OSSignpostIntervalState
    }

    private static let logger = Logger(
        subsystem: "com.samsonlab.cinelark",
        category: "Performance"
    )

    private let lock = NSLock()
    private let clock = ContinuousClock()
    private let signposter = OSSignposter(
        subsystem: "com.samsonlab.cinelark",
        category: "Performance"
    )
    private var active: [CineLarkPerformanceInterval: ActiveInterval] = [:]

    func start(_ metric: CineLarkPerformanceMetric) -> CineLarkPerformanceInterval {
        let token = CineLarkPerformanceInterval(id: UUID(), metric: metric)
        let state = signposter.beginInterval(metric.signpostName)
        lock.lock()
        active[token] = ActiveInterval(startedAt: clock.now, signpostState: state)
        lock.unlock()
        return token
    }

    func finish(
        _ token: CineLarkPerformanceInterval,
        outcome: CineLarkPerformanceOutcome
    ) {
        lock.lock()
        let interval = active.removeValue(forKey: token)
        lock.unlock()
        guard let interval else { return }

        let elapsed = interval.startedAt.duration(to: clock.now)
        let milliseconds = Self.milliseconds(elapsed)
        let rating = Self.rating(metric: token.metric, elapsedMilliseconds: milliseconds)
        signposter.endInterval(token.metric.signpostName, interval.signpostState)
        Self.logger.log(
            level: rating == .exceededCritical ? .error : .info,
            "metric=\(token.metric.rawValue, privacy: .public) elapsed_ms=\(milliseconds, privacy: .public) rating=\(rating.rawValue, privacy: .public) outcome=\(outcome.rawValue, privacy: .public)"
        )
    }

    static func rating(
        metric: CineLarkPerformanceMetric,
        elapsedMilliseconds: Double
    ) -> CineLarkPerformanceRating {
        let budget = metric.budget
        if elapsedMilliseconds > budget.criticalMilliseconds {
            return .exceededCritical
        }
        if elapsedMilliseconds > budget.targetMilliseconds {
            return .exceededTarget
        }
        return .withinTarget
    }

    static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
