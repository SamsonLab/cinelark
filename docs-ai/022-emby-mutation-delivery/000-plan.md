# 022 — Emby Mutation Delivery: Plan

| | |
| --- | --- |
| **Status** | Implemented and verified locally |
| **Anchor date** | 2026-08-28 |
| **Primary refs** | Pending |
| **Related** | [Media source platform](../011-media-source-platform/000-plan.md), [Emby integration](../../docs/integrations/emby.md), [Viewing identity and sync](../014-viewing-identity-and-sync/000-plan.md) |

## Background

CineLark already persists local Profile facts before attempting optional Emby
delivery. However, the provider boundary currently collapses nearly every HTTP
failure into `unavailable`, so the persistent mirror queue retries permanent
client failures indefinitely and ignores server `Retry-After` guidance.
Playback check-ins also originate from independent TCA effects and reach an
actor that may re-enter while awaiting HTTP, which does not prove
Started/Progress/Stopped wire ordering.

## Goals

- Normalize Emby HTTP responses into stable domain failures that distinguish
  authentication, rate limiting, retryable service failures, and permanent
  request rejection without retaining response bodies or credentials.
- Expose a provider-neutral retry decision on `MediaSourceFailure`.
- Retry only safely idempotent outbound Profile state assignments, honoring a
  bounded `Retry-After` value before exponential backoff.
- Stop automatic retry for permanent failures while preserving the local
  Profile as the UI authority and presenting a recoverable Feature failure.
- Serialize playback check-ins per configured Emby runtime so wire submission
  follows the event order even while individual HTTP requests suspend.
- Verify failure mapping, queue policy, exact-user enforcement, and check-in
  ordering with deterministic package and `TestStore` tests.

### Non-goals

- Making Emby the source of truth for Profile state.
- Persisting live playback check-ins in the Profile mirror queue.
- Retrying an arbitrary provider mutation whose idempotency is not declared.
- Logging or persisting HTTP bodies, access tokens, authorization headers, or
  account identifiers in failure diagnostics.
- Adding an application-level network reachability state machine.

## Design / Approach

`MediaSourceFailure` gains domain cases for rate limiting and request rejection
plus a value-typed retry decision. The Emby adapter maps 401/403 to
authentication, 429 to rate limiting with a clamped delta-seconds hint,
408/425/5xx to retryable unavailability, and other non-success responses to
permanent rejection.

Profile favorites and played/progress mirror commands are exact desired-state
assignments, so the existing durable queue may retry only failures whose domain
decision permits it. Permanent entries are completed instead of hot-looped;
the current Feature retains a redacted failure so the user can reauthenticate
or change mirror configuration. Local state is never rolled back.

An Emby-owned ordered playback reporter chains submissions independently of
the service actor's reentrancy. One failed command does not cancel later
commands, and check-ins are not automatically replayed because their delivery
outcome may be ambiguous.

## Alternatives & decisions

- **Retry every failure with capped backoff:** rejected because malformed,
  unsupported, or unauthorized requests cannot heal through time alone.
- **Retry inside the generic plugin platform:** rejected because mutation
  idempotency and protocol response semantics belong to each plugin.
- **Let the Emby service actor imply ordering:** rejected because actors are
  reentrant across suspension points.
- **Queue live check-ins durably:** deferred because stale Started/Progress
  events delivered after playback ends can corrupt remote session state.

## Validation

- Plugin tests for HTTP status and `Retry-After` normalization.
- A controlled suspended transport test proving check-in request order.
- `ProfileFeature` tests for retryable, rate-limited, and terminal failures.
- Full SwiftPM and unsigned macOS test suites.
- `TCA-learn.md` review after implementation; add an entry only if the tested
  orchestration boundary is reusable beyond this Feature.

## Amendments

- None.
