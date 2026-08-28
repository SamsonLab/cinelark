# Retired media library provider interface

Status: **Retired**

The original `MediaLibraryProvider` contract, provider session model, cache
decorator, and generic metadata cache were removed after the macOS application
completed its migration to TCA Features, capability-based Sources, and the local
Catalog.

Current integrations must use:

- [`media-source-platform.md`](media-source-platform.md) for Source plugin,
  capability, identity, query, and runtime contracts;
- [`metadata-cache.md`](metadata-cache.md) for Catalog and artwork caching;
- [`../integrations/emby.md`](../integrations/emby.md) for the Emby adapter.

This tombstone is retained only to keep historical documentation links valid.
No production or test target contains the retired Swift protocols.
