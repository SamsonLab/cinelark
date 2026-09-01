# 017.002 — Remote Emby Server Setup

## Context

Manual setup accepted any explicit URL scheme and treated every scheme-less
address as HTTP. That is convenient for LAN discovery but wrong for a public
hostname, where HTTPS is the safe and common default. User information, query
items, and fragments could also enter the persisted base URL even though they
are not part of a stable Emby API root.

The Emby descriptor advertised token authentication while the runtime and
macOS setup UI implemented only `Users/AuthenticateByName`. This exposed a
capability that callers could not complete.

## Planned change

- Normalize a manual server address before validation and persistence.
- Accept only HTTP(S) URLs with a host; reject embedded credentials, queries,
  and fragments while preserving ports and reverse-proxy paths.
- Default scheme-less localhost and private/link-local IP literals to HTTP.
  Default other hostnames and addresses to HTTPS.
- Remove redundant trailing slashes from the persisted base URL.
- Advertise username/password authentication only until token setup has a
  complete user-selection and verification contract.
- Keep UDP-discovered URLs unchanged because the server supplies their scheme.

## Validation plan

- Reducer tests cover public-host HTTPS defaulting, local HTTP defaulting,
  reverse-proxy path preservation, and invalid URL rejection.
- Emby contract tests retain reverse-proxy request-path coverage.
- A read-only public-system check may be run against a user-provided real URL;
  no credential or private response data belongs in this record.

## Current state

Implemented and verified locally. Reducer tests cover public HTTPS defaulting,
local HTTP defaulting, reverse-proxy paths, normalized persistence, and rejection
of credential/query-bearing input. A full public-host setup test carries the
normalized URL through username/password authentication and Profile-backed
Source persistence. The descriptor now exposes only the implemented flow. No
live credentials or private response data were used.
