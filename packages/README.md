# Shared Packages

Planned package boundaries:

- `domain/` — provider-neutral models and protocols.
- `uhdnow/` — UHDNow API adapter and DTOs.
- `bridge/` — native side of the IINA bridge protocol.

Dependencies point inward: adapters depend on domain contracts; domain code does
not import provider, UI, or IINA types.
