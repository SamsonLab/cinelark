# 011.002 — Profile, Emby, and Catalog Completion

## Context

The first platform slice defined plugin contracts and a local Catalog but did
not persist source configuration, project user state locally, or expose a
complete Emby setup and content surface. UHDNow remains the UI-facing provider.

## Change

- Add a two-configuration Core Data repository: Cloud entities for profiles,
  favorites, playback state, media snapshots, and import markers; local
  entities for source configuration, profile-source binding, active selection,
  mirror ownership/queue, and Catalog.
- Resolve conflicts deterministically by `modifiedAt` and `deviceID`; enforce a
  single mirror owner for each `(sourceID, remoteUserID)` pair.
- Add Emby UDP 7359 discovery, URL validation, authentication setup, persisted
  runtime installation, and the remaining v1 browse/detail hierarchy mappings.
- Make local Profile state the sole UI truth. Remote state participates only in
  explicit idempotent import and optional outbound mirror processing.
- Replace `CachedMediaLibraryProvider` UI reads with Catalog-backed feature
  projections once behavior is covered.

## Validation

- Repository tests cover profile isolation, conflict ordering, offline writes,
  idempotent imports, source persistence, and unique mirror ownership.
- Emby fixtures cover discovery parsing, reverse-proxy setup, views, latest,
  resume, detail hierarchy, people, favorites import, direct playback, and
  check-in ordering.
- Integration tests cover persisted source bootstrap and cached-first Catalog
  refresh.

## Current state

Implemented and verified on 2026-08-26.

- The Profile repository loads two persistent stores and assigns cloud/local
  entities through Core Data configurations.
- Profile switching, source switching, local-first favorite/playback writes,
  explicit import, mirror enablement, queue processing, and retry are wired to
  `ProfileFeature`.
- Source setup supports manual URL and Emby LAN discovery. Persisted sources are
  installed before the saved context is projected into application features.
- Emby hierarchy, people, artwork metadata, remote state, direct
  play/direct-stream resolution, and playback check-ins have fixture coverage.
- Catalog-backed TCA views now own home, collections, favorites, search, media
  detail, and person detail. The previous UI/provider ownership was removed.

## Verification

- SwiftPM: 55 tests across 7 suites pass.
- macOS: 6 XCTest cases and 15 Swift Testing cases across 8 suites pass.
- Unsigned Debug application build passes after regenerating the Xcode project.
- CloudKit runtime verification is intentionally separate because the signed
  build needs an installed provisioning profile for `com.samsonlab.cinelark`.
