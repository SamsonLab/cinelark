# Contracts

Machine-readable contracts are the cross-runtime source of truth:

- `common/` — provider-neutral playback and control semantics.
- `bridge/` — CineLark for Mac ↔ IINA plugin protocol.
- `remote/` — Flutter Remote ↔ CineLark for Mac protocol.
- `uhdnow/` — sanitized observation of the external provider API.

A schema change lands before or with all affected Swift, Dart, and
TypeScript/JavaScript consumers. Generated models are outputs; compatibility is
proven with shared vectors in `fixtures/conformance/`.
