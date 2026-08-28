import Testing
@testable import CineLarkPluginAPI

@Test func mediaSourceFailureExposesProviderNeutralRetryDecisions() {
    #expect(MediaSourceFailure.transport("offline").retryDecision == .retry(afterSeconds: nil))
    #expect(MediaSourceFailure.unavailable.retryDecision == .retry(afterSeconds: nil))
    #expect(MediaSourceFailure.rateLimited(retryAfterSeconds: 12).retryDecision == .retry(afterSeconds: 12))
    #expect(MediaSourceFailure.unauthorized.retryDecision == .stop)
    #expect(MediaSourceFailure.requestRejected.retryDecision == .stop)
    #expect(MediaSourceFailure.invalidResponse.retryDecision == .stop)
}
