# CineLark AI Documentation

`docs-ai/` is CineLark's curated engineering memory. It records why substantial
features, architecture choices, and decision-shaping fixes exist, together with
what was ultimately implemented.

This directory is not a task journal or a replacement for the rest of the
documentation set:

- `docs/` describes current product behavior, architecture, integrations, and
  accepted decisions intended for contributors.
- `specs/` contains machine-readable cross-runtime contracts.
- `docs-ai/` preserves plans, implementation outcomes, amendments, and living
  engineering runbooks that future humans and agents need to make sound changes.

## Entry model

Each substantial topic uses a three-digit numbered directory:

```text
docs-ai/NNN-kebab-case-topic/
├── 000-plan.md
├── 001-action.md
└── 002-follow-up.md
```

- `000-plan.md` is written before implementation and captures goals, non-goals,
  design, and rejected alternatives.
- `001-action.md` records the verified outcome and deviations from the plan.
- `002-*.md` and later numbered files record meaningful follow-ups.
- Non-numbered files inside an entry are living references or runbooks and are
  updated in place.

Use the project skill at `.claude/skills/write-ai-doc/SKILL.md` for selection,
writing, amendment, and verification rules.

## Index

| ID | Topic | Anchor date | Summary |
| --- | --- | --- | --- |
| 001 | [AI knowledge system](001-ai-knowledge-system/000-plan.md) | 2026-08-21 | Shared Claude/Codex skills and curated engineering-memory governance |
| 002 | [Keyboard shortcut system](002-keyboard-shortcut-system/000-plan.md) | 2026-08-21 | Fixed navigation keys, directional content focus, overlay help, and back semantics |
| 003 | [Keyboard-first application navigation](003-keyboard-first-navigation/000-plan.md) | 2026-08-24 | Application-wide focus graphs, resilient input lifecycle, and last-input selection handoff |
| 004 | [Sparkle updates](004-sparkle-updates/000-plan.md) | 2026-08-24 | Signed native updates with a conditional sidebar availability prompt |
| 005 | [Native episode playlist](005-native-episode-playlist/000-plan.md) | 2026-08-24 | Superseded rolling IINA/mpv playlist design and implementation lessons |
| 006 | [Sequential episode replacement](006-sequential-episode-replacement/000-plan.md) | 2026-08-25 | Single-content player that replaces the current episode at natural EOF |
| 007 | [Couch Remote](007-couch-remote/000-plan.md) | 2026-08-25 | Secure Flutter Remote, Mac semantic control surfaces, and Rust transport integration |
| 008 | [Safe IINA plugin lifecycle](008-safe-iina-plugin-lifecycle/000-plan.md) | 2026-08-25 | Restart-safe first installation, update, and repair of the managed IINA plugin |
| 009 | [Unified native gateway](009-unified-native-gateway/000-plan.md) | 2026-08-26 | One native process with independent IINA and Remote centers |
| 010 | [TCA application architecture](010-tca-application-architecture/000-plan.md) | 2026-08-26 | Incremental TCA feature architecture, deterministic effects, and curated learning records |
| 011 | [Media source platform](011-media-source-platform/000-plan.md) | 2026-08-26 | Capability-based plugins, local catalog, profiles, and standard Emby support |
| 012 | [Cache management](012-cache-management/000-plan.md) | 2026-08-26 | Catalog/artwork usage visibility and safe recreatable-data purge |
| 013 | [Settings information architecture](013-settings-information-architecture/000-plan.md) | 2026-08-26 | Content-only sidebar and consolidated native macOS configuration categories |
| 014 | [Viewing identity and sync](014-viewing-identity-and-sync/000-plan.md) | 2026-08-27 | Client/Profile identity separation, CloudKit bootstrap resolution, monotonic conflicts, and independent provider state |
| 015 | [Viewing insights](015-viewing-insights/000-plan.md) | 2026-08-27 | Local-first monthly, quarterly, annual, and affinity projections from durable viewing facts |
| 016 | [Emby source unification](016-emby-source-unification/000-plan.md) | 2026-08-27 | One user-visible Emby plugin with explicit reconnect migration from the retired UHDNow private runtime |
| 017 | [Emby real-contract hardening](017-emby-real-contract-hardening/000-plan.md) | 2026-08-27 | Episode identity, provider-correct pagination, and secret-free direct-stream URL resolution |
| 018 | [Emby metadata fidelity](018-emby-metadata-fidelity/000-plan.md) | 2026-08-27 | Original titles, genres, series counts, and explicit-import playback timestamps across Catalog and Profile |
| 019 | [Authenticated artwork delivery](019-authenticated-artwork-delivery/000-plan.md) | 2026-08-27 | Header-authenticated plugin artwork through a credential-free Kingfisher cache boundary |
| 020 | [Legacy provider retirement](020-legacy-provider-retirement/000-plan.md) | 2026-08-28 | Removal of duplicate provider/session/cache ownership with narrow legacy artifact cleanup |
| 021 | [Profile onboarding and sync health](021-profile-onboarding-and-sync-health/000-plan.md) | 2026-08-28 | Pending-import recovery, local-first continuation, and truthful CloudKit transport health |
| 022 | [Emby mutation delivery](022-emby-mutation-delivery/000-plan.md) | 2026-08-28 | Domain failure classification, safe mirror retry, and ordered playback check-ins |
