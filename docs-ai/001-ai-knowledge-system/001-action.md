# 001 — AI Knowledge System: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-21 | Audited Prowl's `write-ai-doc`, repository-local skills, and `docs-ai/` conventions. | [Prowl source](https://github.com/onevcat/Prowl) |
| 2026-08-21 | Established the CineLark `docs-ai/` taxonomy and index. | Working tree |
| 2026-08-21 | Added the canonical `write-ai-doc` skill under `.claude/skills/`. | Working tree |
| 2026-08-21 | Exposed the canonical skill tree to Codex through a relative symbolic link. | Working tree |
| 2026-08-21 | Validated skill discovery through both repository paths. | Working tree |

## Outcome & current state (as of 2026-08-21)

`.claude/skills/` is the single source of truth for repository-local skills.
`.codex/skills` is a relative symbolic link to `../.claude/skills`, so a clone
does not depend on an absolute machine path and the two agents cannot drift.

The first skill, `.claude/skills/write-ai-doc/SKILL.md`, defines selective entry
criteria, plan/action/amendment workflows, templates, security constraints, and
the boundary between `docs/`, `specs/`, and `docs-ai/`.

`docs-ai/README.md` is the durable index. This entry verifies the workflow, and
`docs-ai/002-keyboard-shortcut-system/` records the first product feature under
the new governance model.

## Validation

- `readlink .codex/skills` returned `../.claude/skills`.
- `.codex/skills/write-ai-doc/SKILL.md` resolved as a regular readable file.
- The Codex skill-creator `quick_validate.py` reported `Skill is valid!` for
  both `.claude/skills/write-ai-doc` and `.codex/skills/write-ai-doc`.
- Repository-relative links and referenced paths were checked against the
  working tree.

## Deviations from plan

None. Only `write-ai-doc` was introduced initially. Prowl's release, benchmark,
upstream-sync, and UI-verification skills were deliberately not copied because
CineLark does not yet provide their required repository-specific workflows.

## Open questions

- Additional project skills should be added only after a repeated CineLark
  workflow has stable commands, evidence, and failure boundaries.
