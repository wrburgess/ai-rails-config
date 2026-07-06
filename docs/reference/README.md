# docs/reference/ — illustrative reference

Material in this directory is **illustrative reference, not part of the
[Generic Baseline](../../CONTEXT.md) guarantee.** Files here are examples a Host App is expected to
replace or extend during Customization.

Unlike the Config Bundle's business-neutral baseline (Skills, Rules Layer, Adapters), reference
content **may name specific external field sources** — it is *reference about the practice of
AI-assisted engineering*, not host-business-domain content, and not authored instructions any agent
must follow. The distinction, and why the intake pipeline's mechanism is baseline while its curated
content lives here, is recorded in [ADR 0012](../adr/0012-intake-pipeline-placement.md).

## Contents

- [`voices.yml`](voices.yml) — the machine-readable **Watchlist** the `scout` sweep polls (issue #30).
  Seeded from the #28 roster sketch; its schema is business-neutral, its entries are illustrative.
- [`learnings/`](learnings/) — the dated, append-only **Learnings Log** (issue #30): the entry
  [schema](learnings/README.md), the [index](learnings/index.md), and worked example entries.
- [`ai-engineering-voices.md`](ai-engineering-voices.md) — the curated roster prose doc of
  AI-engineering voices (issue #27): the human-readable sibling of `voices.yml`. It owns the narrative
  (per-person **Focus**, tier rationale, and the non-person *balance* documents + *master resource*);
  `voices.yml` owns the machine fields (`feeds`, `cadence`, `verified`, `status`) the sweep polls.
