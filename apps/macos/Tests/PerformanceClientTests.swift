import Testing
@testable import CineLark

@Suite("Performance budgets")
struct PerformanceClientTests {
    @Test("Every metric has an ordered positive budget")
    func budgetsAreOrdered() {
        for metric in CineLarkPerformanceMetric.allCases {
            #expect(metric.budget.targetMilliseconds > 0)
            #expect(metric.budget.criticalMilliseconds >= metric.budget.targetMilliseconds)
        }
    }

    @Test("Samples classify at target and critical boundaries")
    func ratingBoundaries() {
        let metric = CineLarkPerformanceMetric.cachedLibraryPage
        #expect(CineLarkPerformanceMonitor.rating(
            metric: metric,
            elapsedMilliseconds: 150
        ) == .withinTarget)
        #expect(CineLarkPerformanceMonitor.rating(
            metric: metric,
            elapsedMilliseconds: 151
        ) == .exceededTarget)
        #expect(CineLarkPerformanceMonitor.rating(
            metric: metric,
            elapsedMilliseconds: 401
        ) == .exceededCritical)
    }

    @Test("Duration conversion retains subsecond precision")
    func durationConversion() {
        #expect(CineLarkPerformanceMonitor.milliseconds(.milliseconds(125)) == 125)
        #expect(CineLarkPerformanceMonitor.milliseconds(.seconds(2)) == 2_000)
    }
}
