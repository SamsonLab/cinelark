# 022 — Emby Mutation Delivery: Action

| | |
| --- | --- |
| **Status** | Implemented and verified locally |
| **Date** | 2026-08-28 |
| **Scope** | Failure normalization, safe Profile mirror retry, and ordered playback check-ins |

## Implemented

- Added provider-neutral `MediaSourceRetryDecision` and explicit rate-limit and
  request-rejection domain failures. TCA does not inspect HTTP status codes.
- Emby maps 401/403 to authentication, 429 to rate limiting, 408/425/5xx to
  transient unavailability, and other non-success responses to permanent
  rejection. Delta-seconds `Retry-After` is clamped to one hour.
- Mutation transport failures use a fixed redacted diagnostic and response
  bodies never enter errors, logs, queue payloads, or Feature state.
- The Profile mirror queue honors provider delay or its existing bounded
  exponential backoff only for retryable failures. Permanent failures complete
  the queue entry, preserve local Profile state, and surface a user-actionable
  failure instead of hot-looping.
- Added an Emby runtime-owned ordered reporter. Started, Progress, and Stopped
  HTTP submissions remain serialized across transport suspension; one failed
  command does not prevent a later lifecycle command from being attempted.
- Live check-ins remain best-effort and are not replayed after ambiguous
  delivery. Favorite and played/progress mirror commands remain durable because
  they are desired-state assignments and safe to retry.

## Validation

- TDD red: plugin tests initially failed to compile because retry decisions,
  rate limiting, and request rejection did not exist.
- TDD red: the new `ProfileFeature` test initially failed because mirror
  outcomes could not represent a terminal delivery failure.
- A suspended HTTP transport test proves that only Started reaches the wire
  until it completes, followed by Progress and Stopped in order.
- Emby tests verify 429 `Retry-After` projection and permanent 400 rejection
  without retaining a private response body.
- `ProfileFeatureTests` verifies provider-directed delay with `TestClock` and
  terminal-entry completion without rescheduling or local rollback.
- `swift test` passes 62 package tests.
- Unsigned `xcodebuild ... test` passes 36 Swift Testing tests across 13 suites
  and 6 XCTest cases.
- `git diff --check` passes.

## Deviations from the plan

- None.

## TCA learning review

Added `L022 — Reducers consume domain retry decisions, not transport errors`.
It records the reusable boundary between provider-specific classification and
Feature-owned clock/cancellation orchestration.

## Remaining release gate

- Live validation against a representative Emby server is still useful for
  provider-specific status behavior, but private responses and credentials
  remain outside the repository.
