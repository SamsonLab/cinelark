# 001 — AI Knowledge System: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-21 |
| **Primary refs** | Implementation commit containing this record |
| **Related** | [`docs-ai/README.md`](../README.md), `docs/README.md` |

## Background

CineLark already has contributor documentation under `docs/`, but it does not
have a dedicated home for durable implementation rationale or repository-local
agent workflows. Claude and Codex also need to discover the same skills without
maintaining divergent copies.

Prowl demonstrates a useful arrangement: `.claude/skills/` is the single source
of truth, `.codex/skills` is a relative symbolic link to it, and `docs-ai/`
stores curated plans and outcomes rather than transient notes.

## Goals

- Establish one repository-local skill source shared by Claude and Codex.
- Add a selective workflow for recording substantial product and engineering
  decisions under `docs-ai/`.
- Define the boundary between current-state documentation, machine contracts,
  and historical engineering rationale.
- Keep the structure portable across clones by using a relative symbolic link.
- Validate the workflow by recording this change with a plan, action log, and
  indexed entry.

### Non-goals

- Migrating or rewriting the existing `docs/` and `specs/` trees.
- Copying Prowl skills whose commands or runtime assumptions do not exist in
  CineLark.
- Creating generic build, release, benchmark, or UI-verification skills before
  CineLark has stable workflows that justify them.
- Changing application runtime behavior.

## Design / Approach

Create `.claude/skills/write-ai-doc/SKILL.md` as the canonical workflow. Adapt
the selection criteria and templates to CineLark while preserving Prowl's key
invariants: plan before implementation, action log after implementation,
amendments for in-frame follow-ups, and new entries for redesigns.

Expose the same directory to Codex through the relative symbolic link
`.codex/skills -> ../.claude/skills`. Skills added later therefore become
available to both agents without synchronization work.

Create `docs-ai/README.md` as the durable index and taxonomy. Numbered entry
folders contain immutable plan/action history; non-numbered references inside
an entry remain living documents.

Validate the skill using the bundled Codex skill validator and verify the
symbolic link resolves from a fresh repository-relative path.

## Alternatives & decisions

| Alternative | Decision |
| --- | --- |
| Duplicate skills under `.claude/` and `.codex/` | Rejected because copies inevitably drift. |
| Make `.codex/skills/` canonical | Rejected to match the requested Prowl-compatible layout. |
| Put all engineering notes in `docs/` | Rejected because current-state contributor docs and historical rationale have different maintenance semantics. |
| Port every Prowl skill immediately | Rejected because repository-specific commands and dependencies would be inaccurate in CineLark. |
| Record every investigation in `docs-ai/` | Rejected because low-signal notes make durable decisions harder to discover. |

## Amendments

None.
