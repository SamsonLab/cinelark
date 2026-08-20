# Protocol Conformance Fixtures

Sanitized positive and negative vectors shared by Swift, Dart, and the IINA
plugin belong here. Each vector identifies its schema version and expected
validation/decoding result.

Fixtures must never contain provider credentials, real account/media data,
playback URLs, pairing payloads, device credentials, or production bridge
secrets. Explicitly labeled deterministic byte sequences may be used only for
cross-runtime cryptographic test vectors.
