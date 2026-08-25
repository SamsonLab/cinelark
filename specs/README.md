# Contracts

Machine-readable contracts are the cross-runtime source of truth:

- `common/` — provider-neutral playback and control semantics.
- `bridge/` — CineLark for Mac ↔ IINA plugin protocol.
- `remote/` — Flutter Remote ↔ CineLark for Mac protocol.
- `uhdnow/` — sanitized observation of the external provider API.

A schema change lands before or with all affected Swift, Dart, and
TypeScript/JavaScript consumers. Generated models are outputs; compatibility is
proven with shared vectors in `fixtures/conformance/`.

Remote pairing QR payloads conform to `remote/pairing.schema.json`. They are
sensitive runtime values and therefore have no example fixture; only the
deterministic authentication primitive has a sanitized conformance vector.
Phone-to-Mac commands conform to `remote/client-message.schema.json` so every
stateful player action remains scoped to a playback ID and revision.
