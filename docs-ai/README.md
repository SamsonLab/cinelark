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
