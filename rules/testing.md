# Testing Rules

**Applies to:** `spec/` (test suite)
**Deep doc:** `docs/rules/testing-postmortems.md` (Tier 2 — deferred; read on demand when a trigger fires)

> Tier-1 Lean Core ([ADR 0004](../docs/adr/0004-two-tier-rules-layer-progressive-context.md)): always-resident invariants. Keep this file lean — push heavy, subsystem-specific case studies down to the deep doc. These are business-neutral starters; **extend per host**.

## Patterns

- **Test behavior and side effects**, not that the code merely runs: assert content, database state, redirects, and enqueued work.
- **Cover the sad paths**: invalid input, `nil`, duplicates, and boundary values — that is where regressions hide.
- **Build the test infrastructure the scenario needs** (helpers, shared contexts, factories, HTTP record/replay) rather than declaring a thing untestable. That is part of the work, not a reason to skip it.
- **Self-review before "done":** for each test ask, "if this passed but the feature were broken, would I know?"

## Anti-Patterns

- **Never use fixtures** — because they drift from the schema and obscure intent; use factories. *(Extend per host.)*
- **Never assert only a status code / `success`** — because a broken feature can still return 200; assert the content, side effects, and redirect. *(Extend per host.)*
- **Never use `sleep` in a test** — because it is flaky and slow; freeze or travel time instead. *(Extend per host.)*
- **Never claim something "can't be tested" without first attempting it** with the host's stack — because most "untestable" cases have a documented tool (headless browser, HTTP record/replay). *(Extend per host.)*
