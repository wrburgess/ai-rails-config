---
date: 2026-07-07
source:
  person: Thorsten Ball
  link: https://registerspill.thorstenball.com/p/building-software-is-learning
  medium: blog
claim: >
  Building new software is inherently a learning process, so optimize for fast feedback loops
  (prototypes, thin specs, incremental shipping) rather than a heavy up-front plan that won't survive
  contact with reality.
stance: challenges
touches: docs/standards/development-lifecycle.md
status: noted
---

## Compare / contrast

Published 2026-06-02 (backfill window). Ball argues that because building software is a discovery
process, teams should ship-to-learn — thin specs, prototypes, incremental delivery — instead of
investing weeks in a plan that breaks on contact with reality.

This **challenges** the repo's lifecycle design, which front-loads a formal `cplan` stage behind a
**mandatory plan-approval human gate**. Ball's "you can't know the target until you build toward it"
presses on how heavy that gate should be: a rigid up-front plan risks the very waste he describes.

## Disposition

`noted` — a useful counterweight for `cplan` / `docs/standards/development-lifecycle.md` authoring.
The tension is real but not necessarily a defect: the repo's plan gate targets *hard-to-reverse*
decisions, and `cplan` could state explicitly that its plan is a thin, revisable spec (ship-to-learn
within a stage), not a waterfall contract. Worth weighing when the lifecycle spec is next revised.
