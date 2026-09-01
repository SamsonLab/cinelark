# 024.002 — Balanced Recommendation Weighting

## Context

The initial genre baseline added session hours, a completion bonus, and a
favorite bonus directly. It also imposed a minimum quarter-point contribution
on every session and summed every matching candidate genre at full strength.
This made very short sessions too influential, left long or old sessions
unbounded, and favored candidates merely because they carried more genre tags.

## Planned change

- Centralize the ranking constants in one value-typed policy so tests and future
  tuning use explicit, reviewable inputs.
- Cap watch-duration evidence per session, keep completion and favorite intent
  independent, and decay session evidence with a fixed half-life.
- Preserve active favorites as durable intent rather than aging them out.
- Score the strongest matching genre fully and discount a bounded number of
  secondary matches, preventing tag count from dominating affinity strength.
- Keep provider rating as a deterministic tie-break only. Candidates still
  require personal genre evidence and recommendation reasons remain truthful.

## Validation plan

- Prove short sessions are no longer promoted to a minimum synthetic weight.
- Prove old evidence decays and long sessions are capped.
- Prove one strong genre outranks several weak matches and secondary matches
  retain a bounded benefit.
- Retain existing privacy, exclusion, determinism, and provider-state tests.

## Current state

Implemented and verified locally. The policy defaults are two watched hours per
session, a `1.5` completion bonus, a `2.5` durable favorite bonus, a 180-day
session half-life, `0.35` secondary-genre weight, and three matched genres
maximum. Focused package tests prove caps, decay, absence of a synthetic minimum,
and bounded secondary matches.
