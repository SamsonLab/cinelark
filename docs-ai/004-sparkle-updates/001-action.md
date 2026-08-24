# 004 — Sparkle Updates: Action

| | |
| --- | --- |
| **Status** | Implemented |
| **Completed** | 2026-08-24 |
| **Plan** | [000-plan.md](000-plan.md) |
| **Decision** | [ADR 0006](../../docs/decisions/0006-sparkle-updates.md) |

## Outcome

CineLark now owns one retained Sparkle 2.9.2 standard updater controller. The
application menu exposes `Check for Updates…`, while the sidebar version row
remains unchanged until Sparkle reports a valid newer appcast item. At that
point a compact glass update action appears, displays the discovered version,
and opens the same standard Sparkle flow. A later no-update result, skip, or
install choice clears the availability state.

The generated application Info.plist pins the HTTPS latest-release appcast URL,
the project public EdDSA key, signed-feed enforcement, and verification before
extraction. `CURRENT_PROJECT_VERSION` is now emitted explicitly as the Sparkle
ordering value.

Tagged releases now:

1. require a positive numeric build version;
2. build and package the existing universal DMG;
3. sign Sparkle's nested updater components from the inside outward;
4. generate a one-item appcast with embedded release notes;
5. sign both the DMG enclosure and complete feed with Sparkle EdDSA; and
6. publish the appcast beside the DMG and checksum before updating Homebrew.

The maintainer Keychain contains the private EdDSA key under the
`com.samsonlab.cinelark` account. The exported CI representation was installed
as the repository `SPARKLE_PRIVATE_KEY` Actions secret and removed from the
temporary filesystem. Only the public key is committed.

## Deviations from plan

- No functional deviation. The final sidebar requirement was clarified during
  implementation: the update action is availability-only, not always visible.
- Feed signing validation uses Sparkle's actual `sparkle-signatures` trailer;
  checking for a nonexistent XML attribute would incorrectly reject a valid
  signed feed.

## Verification

- Debug application build completed successfully without code signing.
- Universal Release build completed successfully for arm64 and x86_64.
- The custom packager signed the host, bridge, Sparkle framework, updater app,
  autoupdate executable, and both XPC services; strict deep verification passed.
- The generated DMG checksum verified successfully.
- A local signed appcast was generated from the DMG and verified successfully
  with Sparkle's `sign_update --verify` command. It contains build `3`, version
  `0.1.2`, an enclosure EdDSA signature, and a signed-feed trailer.
- `actionlint .github/workflows/release.yml` passed.
- `bash -n scripts/package_macos_release.sh` passed.
- `swift test --package-path packages/apple/CineLarkKit` passed 36 tests.
- `npm test --prefix plugins/iina` passed 16 tests.
- `python3 scripts/check_repository.py` remains red on two pre-existing example
  links in `.claude/skills/write-ai-doc/SKILL.md`; this change did not modify
  that file.

## Operational notes

- The first end-to-end update installation can only be exercised after a newer
  genuine tag publishes its DMG and appcast. Local generation and signature
  verification cover the release format but not the remote install transition.
- Every new tag must increase `CURRENT_PROJECT_VERSION`, even when the marketing
  version already changed.
- Losing both the Keychain key and Actions secret strands existing clients on
  the embedded public key. Back up the release credential through an approved
  secret-management path before relying on Sparkle for production recovery.
