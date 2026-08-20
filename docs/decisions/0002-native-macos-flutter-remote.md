# ADR-0002: Native macOS client and Flutter Remote

- **Status:** Accepted
- **Date:** 2026-08-20

## Context

CineLark's primary experience is a TV-first macOS application. It needs precise
macOS focus, keyboard/remote input, window, lifecycle, Keychain, networking, and
IINA integration. A later companion should reach both iOS and Android without
making the Mac implementation portable at the expense of native quality.

Swift and Dart cannot safely share runtime domain modules without a bridge that
would cost more than the reused code. They can, however, share stable wire
semantics, schemas, fixtures, design tokens, and compatibility policy.

## Decision

1. Implement CineLark for Mac with Swift 6, strict concurrency, and SwiftUI as
   the default UI framework.
2. Use AppKit only through narrow adapters where SwiftUI does not provide the
   required focus, input, windowing, or lifecycle behavior.
3. Organize non-UI Apple code as targets in one local Swift package initially.
4. Implement CineLark Remote with Flutter and Dart for iOS and Android.
5. Keep the Mac app authoritative. The Remote sends semantic commands and
   observes sanitized state; it never contacts providers or IINA directly.
6. Share contracts rather than implementation code across Swift, Dart, and the
   IINA plugin:
   - JSON Schema/OpenAPI definitions
   - protocol capabilities and version rules
   - sanitized conformance vectors
   - platform-neutral design tokens and source brand assets
7. Treat generated Swift/Dart/TypeScript models as disposable outputs. Specs
   remain the source of truth and handwritten adapters must pass the same
   conformance vectors.

## Consequences

### Positive

- The Mac experience can use first-class Apple APIs and predictable performance.
- Remote development covers iOS and Android from one UI codebase.
- Protocol compatibility is reviewable independently from implementation.
- Provider credentials and unstable provider DTOs remain isolated on the Mac.
- Platform teams can evolve implementation details without drifting wire
  semantics.

### Costs

- SwiftUI and Flutter presentation code are separate.
- Some conceptual models exist as native Swift and Dart representations.
- Schema/code-generation and cross-runtime conformance tests become required
  infrastructure.
- Bonjour, TLS pinning, background behavior, and secure storage require
  platform validation in Flutter.

## Rejected alternatives

- **Flutter for macOS:** weakens the native focus/window/IINA integration that is
  central to the primary product.
- **Swift-only Remote:** provides the best iOS integration but does not meet the
  cross-platform mobile goal.
- **Sharing provider models with Remote:** leaks volatile and sensitive backend
  details across a security boundary.
- **Hand-maintained duplicate wire contracts:** too likely to drift across
  Swift, Dart, and JavaScript.

## Revisit when

Reconsider only if Flutter cannot satisfy a measured Remote requirement after a
focused native-plugin/platform-channel spike. That does not imply changing the
native macOS decision.
