# Rust Packages

Planned package:

- `cinelark-bridge/` — self-contained local broker bundled and signed inside
  CineLark.app.

It will communicate with the parent Mac app through framed stdin/stdout and
with the thin IINA plugin through authenticated loopback-only HTTP. It is not a
persistent daemon and must require no user-installed Rust runtime or toolchain.
