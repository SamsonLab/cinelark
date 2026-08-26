# 007.003 — Host Identity Presentation

## Context

The first multi-device list reused the Bonjour service label
`CineLark — <host>`, and every row displayed the CineLark character. Product
branding is not device identity and does not distinguish host operating systems.

## Change

- The Mac QR payload now publishes `Host.current().localizedName` as `name`
  without a CineLark prefix.
- Pairing payloads may include additive `platform` metadata with `macos`,
  `windows`, `linux`, or `unknown`. The field is presentation-only and is not
  part of certificate pinning, device proof, or authorization.
- Flutter persists the platform with each paired host. Version-1 records and QR
  payloads without the field default to `macos`, matching every host released
  before this addition.
- The device list and active Remote header strip historical `CineLark` or
  `Cine-Lark` prefixes at presentation time without mutating credential scope.
- Device rows use Material Apple, window, terminal, or generic-computer icons
  for macOS, Windows, Linux, or unknown hosts. The CineLark character remains
  product branding at the screen level, not a repeated device icon.

The Bonjour service type `_cinelark._tcp` retains product discovery context;
its instance name is the unprefixed host name. Stable `serviceID`, not either
display string, remains device identity.

## Validation

- `fvm flutter analyze` passed.
- `fvm flutter test` passed all 17 tests, including legacy-name normalization,
  platform decoding, and Apple/Windows/Linux icon selection.
- `uv run --with-requirements requirements-specs.txt python scripts/check_contracts.py`
  validated all 6 conformance fixtures.
- The macOS Xcode suite passed with code signing disabled.
- iOS Simulator and Android debug builds succeeded. Android retained the
  existing future Built-in Kotlin warning from `mobile_scanner`.

## Current state

macOS is the only shipping host gateway. Windows and Linux values are defined
now so future host implementations do not need to infer operating systems from
mutable device names.
