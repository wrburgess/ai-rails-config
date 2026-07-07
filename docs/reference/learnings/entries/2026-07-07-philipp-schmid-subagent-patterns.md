---
date: 2026-07-07
source:
  person: Philipp Schmid
  link: https://www.philschmid.de/subagent-patterns-2026
  medium: blog
claim: >
  Four orchestration patterns for managing subagents, from simple tool-call delegation up to
  autonomous agent teams.
stance: extends
touches: skills/ship
status: noted
---

## Compare / contrast

Published 2026-05-05 (backfill window). Schmid lays out four subagent-orchestration patterns, ranging
from simple tool-call delegation to autonomous agent teams.

This **extends** `ship`'s delegation model (`ADR-0005`): `ship` offloads output-heavy phases to
discardable sub-agents, and this taxonomy gives an external vocabulary to name **which** pattern
`ship` uses and where its boundaries are — useful when documenting or tuning the phase-delegation
enhancement (which degrades gracefully to inline execution).

## Disposition

`noted` — a vocabulary/reference for `ship`'s sub-agent execution enhancement; candidate to cite in
`ADR-0005` when the delegation policy is next described. No behavior change.
