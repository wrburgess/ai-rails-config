---
date: 2026-07-07
source:
  person: Matt Pocock
  link: https://www.aihero.dev/grill-with-docs
  medium: docs
claim: >
  An AI interview that stress-tests design decisions one question at a time, capturing settled
  vocabulary as a glossary and hard-to-reverse choices as ADRs before any code is written.
stance: confirms
touches: skills/grill-with-docs
status: noted
---

## Compare / contrast

Published 2026-07-06. Pocock documents a "grill-with-docs" move: an AI interview that stress-tests
design one question at a time, capturing settled vocabulary as a glossary and hard-to-reverse choices
as ADRs, all *before* code.

This is the **same-named, same-shaped** Skill the repo already ships (`skills/grill-with-docs`:
one-question-at-a-time grilling → `CONTEXT.md` glossary + `docs/adr/` ADRs). The near-certain shared
lineage makes it strong external validation of the existing Skill's design rather than a new idea to
import.

## Disposition

`noted` — confirms `skills/grill-with-docs`. Worth watching Pocock's version for divergences (prompt
shape, capture format) that might be worth adopting; nothing to change today.
