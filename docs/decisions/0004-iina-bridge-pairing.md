# ADR-0004: Keychain-provisioned IINA bridge pairing

- **Status:** Accepted for Phase 0 implementation; signed-build validation required
- **Date:** 2026-08-20

## Context

The IINA plugin must authenticate to a loopback Rust broker without embedding a
shared secret in source, a plugin archive, command-line arguments, environment
variables, preferences, or an unauthenticated bootstrap response. A local
process can probe the reserved port range, so loopback reachability is not an
authorization boundary.

IINA prefixes plugin Keychain services with the plugin identifier. A generic
password created by CineLark for that exact service can therefore be read by
the CineLark plugin inside IINA, subject to the macOS Keychain authorization
prompt for IINA.

## Decision

1. CineLark generates a random 256-bit pairing key with `SecRandomCopyBytes`.
2. It stores the key as a generic password using service
   `com.samsonlab.cinelark.iina - bridge` and account `pairing-key`.
3. The plugin reads only that item through `iina.utils.keychainRead`. Other
   JavaScript plugins receive a different IINA-enforced service prefix.
4. The first IINA read is authorized through the macOS Keychain prompt. The
   prompt is the user-approved cross-application provisioning step; the key is
   never copied through HTTP or a file. Choosing **Always Allow** persists this
   approval across signed IINA launches.
5. The plugin discovers a live CineLark broker before reading Keychain and
   caches the key only in memory for the IINA process lifetime. Automatic
   reconnects do not repeat Keychain reads; explicit reconnect or a 401 clears
   the cached key.
6. CineLark sends the key to its supervised Rust child only in the initial
   length-prefixed stdin frame. The helper retains it in memory only.
7. Plugin HTTP requests use HMAC-SHA-256 over method, request target, Unix
   timestamp, and a unique nonce. The helper enforces a 30-second window and a
   bounded replay cache.
8. Every command and event envelope uses HMAC-SHA-256 over the versioned
   canonical envelope representation. Each direction enforces monotonically
   increasing sequence numbers.
9. Revocation rotates/deletes the Keychain item and restarts the helper. UI for
   manual reset remains a follow-up hardening task.

## Threat model

This prevents an unpaired same-user process from polling commands, obtaining a
playback URL, injecting player events, or replaying an accepted request. Health
responses disclose only protocol and broker versions. Authentication failures
return no title, URL, player state, or detailed diagnostic.

The design does not defend against root, a debugger attached to CineLark/IINA,
a compromised IINA process, or a user approving an unexpected Keychain prompt
for a malicious native application. Those actors can already inspect process
memory or media traffic and are outside the local bridge boundary.

## Required release validation

Before calling the pairing flow production-ready:

- verify the Keychain ACL prompt and persistence with signed/notarized CineLark
  and stock IINA;
- verify denial, later approval, key rotation, IINA reinstall, and plugin update;
- confirm no pairing key, playback URL, or authenticator enters unified logs,
  crash reports, recent items, or plugin preferences;
- add an in-app bridge status/reset surface and explicit revocation test.

If stock IINA cannot reliably read the provisioned item with an understandable
system prompt, this ADR must be revisited rather than falling back to a secret
in plugin files or unauthenticated cleartext pairing.
