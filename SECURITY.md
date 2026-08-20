# Security Policy

CineLark handles provider credentials and capability-bearing playback URLs.
Treat both as secrets.

## Never commit

- HAR/network capture files or extracted captures
- usernames, passwords, TOTP values, cookies, or access tokens
- URLs containing `token`, `auth`, `key`, `signature`, or equivalent query data
- unredacted account, subscription, or viewing-history responses
- production Keychain exports or bridge pairing secrets

Only synthetic fixtures belong in `fixtures/`.

## Runtime requirements

- Store provider and bridge secrets in macOS/iOS Keychain.
- Redact authorization headers, cookies, and sensitive query parameters before
  logging or telemetry.
- Keep provider credentials in the core app; never send them to IINA or mpv.
- Treat playback URLs as short-lived bearer capabilities.
- Authenticate every local bridge connection and message.
- Do not ship the current IINA WebSocket transport until its network exposure
  and pairing design satisfy the constraints in
  [`docs/interfaces/playback-bridge.md`](docs/interfaces/playback-bridge.md).

## Reporting

Until a private reporting channel is published, contact the maintainers without
including secrets or exploit details in a public issue.
