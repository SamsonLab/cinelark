# 003.018 — Compact Detail Scroll Progression

## Context

Series detail uses visible-target tracking to discard stale semantic selection
after manual scrolling. In a compact window, a keyboard-selected target can also
remain outside the visibility threshold while its animated `scrollTo` is still
settling. A subsequent Down event then mistakes that temporary state for manual
scroll divergence and rebases from the old visible boundary, so focus and scroll
progression may repeat, jump, or stall.

## Change

- Preserve a valid semantic selection while keyboard input remains active,
  independent of transient visibility callbacks during programmatic scrolling.
- Continue requiring visibility when the event hands control from pointer input
  back to keyboard input, preserving manual-scroll boundary recovery.
- Add policy-level regression coverage for both input modes.

## Validation

- Two focused origin-policy tests were added first and failed to compile because
  the policy did not exist. Both passed after implementation.
- `xcodebuild -quiet -project apps/macos/CineLark.xcodeproj -scheme CineLark
  -configuration Debug -derivedDataPath build/DerivedData -destination
  'platform=macOS' CODE_SIGNING_ALLOWED=NO test` passed all 65 tests.
- The corresponding unsigned Debug build completed successfully, and
  `git diff --check` reported no whitespace errors.
- The installed 0.1.10 application was exercised at its compact window width;
  six consecutive Down events moved the detail scrollbar from the top to the
  bottom. That release predates the current working-tree visibility logic and is
  only a baseline, not validation of this fix.
- The current Debug binary launched with its test-only in-memory Profile path,
  avoiding the unavailable CloudKit provisioning profile, but that path has no
  configured catalog source and therefore could not exercise a detail route.

## Current state

Implemented on 2026-09-01.

Offscreen selection is stale only at a pointer-to-keyboard handoff. Once keyboard
navigation is active, semantic selection remains authoritative while animated
scrolling and visibility callbacks converge. This keeps rapid Down input
monotonic in compact viewports while retaining manual-scroll recovery.
