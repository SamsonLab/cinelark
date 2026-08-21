---
name: write-ai-doc
description: Create and maintain curated CineLark docs-ai records for substantial features and non-trivial, decision-shaping fixes. Use numbered entries with 000-plan.md before implementation and 001-action.md after. Do not use for routine investigations, reviews, status reports, test runs, or working notes unless the user explicitly requests a docs-ai record.
---

# Write AI Doc

`docs-ai/` is CineLark's curated engineering memory, not a work log. Future
humans and agents use it to understand why a consequential design exists, what
was implemented, and how later changes amended it. Read `docs-ai/README.md`
before creating or changing an entry.

## When to write one

Create a new numbered entry when the work is either:

- a substantial feature with an enduring product, UX, architecture, protocol,
  security, performance, or operational decision;
- a non-trivial fix whose root cause or resulting invariant must guide future
  implementation;
- explicitly requested by the user as a `docs-ai/` record.

Do not create an entry merely because a task is detailed or took significant
time. Skip routine reviews and audits, exploratory research, ordinary debugging,
status reports, test runs, formatting, dependency bumps, and docs-only cleanup
unless the user explicitly requests a record. When uncertain, do not create one.

## Choose the right documentation home

- Use `docs/` for the contributor-facing current state: product behavior,
  architecture, integrations, interfaces, and accepted ADRs.
- Use `specs/` for machine-readable cross-runtime contracts.
- Use `docs-ai/` for plans, decision history, implementation outcomes,
  amendments, and living engineering runbooks.

If a change alters a current public or contributor-facing contract, update the
relevant `docs/` or `specs/` source of truth as well. Link it from `docs-ai/`
instead of duplicating its full contents. Foundational decisions may require an
ADR under `docs/decisions/`; the `docs-ai/` entry records the implementation arc
and links to that normative decision.

## Workflow

### New entry: plan before implementation

1. Inspect `docs-ai/README.md` and list existing numbered directories. Choose
   the highest three-digit ID plus one.
2. Create `docs-ai/NNN-<kebab-slug>/000-plan.md` with `Status: Planned`.
   Capture background, goals, non-goals when meaningful, approach, and rejected
   alternatives before editing product code.
3. Implement and verify the work through the repository's normal workflow.
4. Create `001-action.md` with the verified outcome, key files, validation,
   deviations, and unresolved questions. Change the plan status to
   `Implemented`.
5. Add or refresh the entry in `docs-ai/README.md` and ship the record with the
   implementation when practical.

If the documentation system is introduced after qualifying implementation is
already in progress, say so explicitly under **Deviations from plan**. Do not
rewrite chronology to pretend the plan existed earlier.

### Follow-up within an existing design

1. Add the next numbered file, such as `002-<topic>.md`.
2. Append an amendment to `000-plan.md`:
   `- Updated YYYY-MM-DD: <summary> — see [002-topic.md](002-topic.md).`
3. Correct stale plan or action text when the current state changed, and name
   the correction in the amendment.
4. Update a non-numbered living reference in place when the change affects a
   maintained contract or runbook rather than historical chronology.

### Redesign or replacement

Open a new numbered entry when the approach replaces the original design rather
than extending it. Cross-link both entries and mark the old plan
`Superseded by [NNN-new-topic](../NNN-new-topic/000-plan.md)`.

## Templates

### `000-plan.md`

```markdown
# NNN — <Title>: Plan

| | |
| --- | --- |
| **Status** | Planned | Implemented | Superseded by <link> |
| **Anchor date** | YYYY-MM-DD |
| **Primary refs** | PRs and commits, or Pending |
| **Related** | Relative links and repo paths |

## Background

## Goals

### Non-goals

## Design / Approach

## Alternatives & decisions

## Amendments
```

### `001-action.md`

```markdown
# NNN — <Title>: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |

## Outcome & current state (as of YYYY-MM-DD)

## Validation

## Deviations from plan

## Open questions
```

### Amendment (`002+`)

```markdown
# NNN.00M — <Topic>

## Context

## Change

## Validation

## Current state
```

## Writing rules

- Write in concise, factual English with RFC-like precision. Prefer a table for
  timelines and exact mappings.
- Keep plans and action logs readable rather than exhaustive. Typical plans are
  40–120 lines and action logs 30–100 lines.
- Verify every repo-relative path with `rg --files` or an equivalent read-only
  check before writing it. Put unverifiable claims under **Open questions**.
- Record only tests and runtime checks that were actually executed, including
  relevant limitations.
- Reference PRs as `#123`, commits as short hashes in backticks, and sibling
  documents with relative Markdown links.
- Treat numbered files as durable history. Treat non-numbered contracts and
  runbooks inside an entry as living documents and update them in place.
- Never include credentials, cookies, provider tokens, signed playback URLs,
  private captures, or real account data. Follow `SECURITY.md`.
- Keep `docs-ai/README.md` accurate whenever an entry is added, renamed,
  superseded, or materially re-scoped.
