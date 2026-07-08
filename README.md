# ai-config

A generic, model-agnostic **AI-agent configuration layer** for software projects — vendor it into a
project, edit one file, and every AI coding assistant follows the same reviewable playbook.

## TL;DR

- **What it is** — one **Canonical Source** of instructions ([`AGENTS.md`](AGENTS.md)) that drives four
  AI coding agents (Claude, Codex, Copilot, Gemini) in lockstep.
- **Why it exists** — each AI tool normally needs its own instructions, so they drift and give
  inconsistent advice. Here you write the house rules **once**; every agent reads the same copy and
  behaves the same way — with built-in guardrails that stop risky actions like committing to a
  protected branch.
- **How you use it** — vendor the bundle into your project (a **Host App**), edit **one** file
  (`PROJECT.md`) for your team, and go. See [Get started](#get-started).
- **New here?** The full walkthrough is [`docs/guides/usage.md`](docs/guides/usage.md); the vocabulary
  (Config Bundle, Adapter, Skill, Rules Layer…) is in [`CONTEXT.md`](CONTEXT.md).

## What it is & how it works

The design intent throughout: **author once, resolve everywhere, and guard the resolution with a
deterministic check** — so four different AI tools stay in lockstep with no human hand-syncing.

- **One Canonical Source → thin Adapters (projection, not duplication).** All instructions are authored
  once in [`AGENTS.md`](AGENTS.md). Each tool reaches it through an **Adapter** that *resolves back*
  rather than copying: Claude and Gemini import it (`@AGENTS.md` in [`CLAUDE.md`](CLAUDE.md) /
  [`GEMINI.md`](GEMINI.md)); Codex and Copilot read `AGENTS.md` natively (`.github/copilot-instructions.md`
  is just a discovery marker). No tool follows a free-text pointer, so none receives drifted
  instructions ([ADR 0002](docs/adr/0002-agents-md-canonical-pointer-projection.md)).
- **[`PROJECT.md`](PROJECT.md) — the one Customization surface.** A Host App declares its quality-check
  commands, attribution/model, branch policy, review-severity framework, and lifecycle host here; the
  baseline files stay generic. A re-sync preserves it (and an existing `bin/setup`).
- **A structural parity gate, not a model in the loop.** `scripts/parity_check.rb` is a dependency-free
  check that asserts every Adapter still resolves, the `PROJECT.md` contract sections are intact, and
  every documented link resolves — making drift mechanically impossible to merge
  ([ADR 0008](docs/adr/0008-structural-parity-check-not-model-in-the-loop.md)).
- **A two-tier Rules Layer for progressive context** ([ADR 0004](docs/adr/0004-two-tier-rules-layer-progressive-context.md)).
  Tier-1 **Lean Core** = seven always-resident `rules/*.md` files (`backend`, `frontend`, `testing`,
  `security`, `self-review`, `scripting`, `skills`), each with Patterns + Anti-Patterns; Tier-2 **Deep
  Docs** (`docs/rules/`) are pulled in on demand via a trigger table. Stack-neutral starters — extend
  per host, or vendor a matching **Stack Overlay** (e.g. `ai-config-rails`) alongside.
- **Single-sourced Skills (12).** Each is authored once as `skills/<name>/SKILL.md` and invoked through
  a thin per-tool shim (Claude `.claude/commands/<name>.md`; other tools via native `AGENTS.md`
  discovery); only tool-specific execution enhancements degrade gracefully, never the procedure or the
  gates ([ADR 0003](docs/adr/0003-skills-canonical-body-thin-shims-graceful-degradation.md)). The set:
  `grill-with-docs`; the six **lifecycle** skills `assess` → `cplan` → `impl` → `verify` → `rtr` →
  `final` (an issue/PR workflow with two mandatory human gates — plan approval, merge; spec in
  `docs/standards/development-lifecycle.md`); the `ship` orchestrator (Epic #1); the `scout` intake
  sweep (Epic #28); the `drop` intake front door (Issue #46); the `create-skill` authoring front door
  (Issue #67); and the `voice` roster front door that adds/updates a Watchlist voice from a handle or
  link (Issue #66).
- **`ship` — delegation by output-weight.** The orchestrator runs the six lifecycle skills end to end
  while keeping a lean main context: it **offloads output-heavy** work (exploration, the code+check+fix
  loop, full-diff review) to discardable sub-agents, and **keeps judgment-heavy** work (plan authoring,
  severity calls, merge-readiness) in the clean orchestrator — so a lossy summary can't silently steer
  the outcome ([ADR 0005](docs/adr/0005-ship-hybrid-delegation-offload-retrieval-protect-judgment.md)).
- **An intake pipeline — propose, then a human disposes.** [`scout`](skills/scout/SKILL.md) polls a
  **Watchlist** (`docs/reference/voices.yml`), drafts dated **Learnings Log** entries
  (`docs/reference/learnings/`), and opens a review PR ([ADR 0012](docs/adr/0012-intake-pipeline-placement.md),
  [ADR 0013](docs/adr/0013-scheduled-intake-sweep-and-empty-sweep-policy.md)).
  [`drop`](skills/drop/SKILL.md) is its **push front door**: hand it a screenshot, link, or quote and it
  enforces a real-URL gate, writes a stance-less drop, and delegates to `scout`
  ([ADR 0015](docs/adr/0015-intake-front-door-drop-skill.md)). Ships as an illustrative reference seed;
  repoint per host via `PROJECT.md` → *Intake Pipeline*.
- **Defense-in-depth branch protection.** `.githooks/` + `bin/guard-protected-branch` +
  `bin/install-git-hooks` + the Claude `.claude/hooks/enforce-branch-creation.sh` fast-fail stop any
  agent — or accidental human — from committing/pushing to a protected branch. The list is authored in
  `PROJECT.md`, not hardcoded ([ADR 0009](docs/adr/0009-defense-in-depth-branch-protection-all-agents.md)).
- **[`CONTEXT.md`](CONTEXT.md) + [`docs/adr/`](docs/adr)** — the domain glossary and the Architecture
  Decision Records behind every choice above.

## Get started

Vendor the bundle into your project (a **Host App**), then activate the guardrails:

```bash
# Preview what would be copied (writes nothing):
ruby bin/ai-config-sync --dry-run /path/to/host-app

# Vendor it in, then activate the git hooks:
ruby bin/ai-config-sync /path/to/host-app
cd /path/to/host-app && bin/setup
```

- Distributed by **copying files in** — no submodule, no package, no upstream tracking
  ([ADR 0001](docs/adr/0001-distribute-as-copy-in-sync-script.md)). The Host App owns plain files (never
  symlinks); this repo's own meta files (`README.md`, `LICENSE`, `.gitignore`, `test/`, the sync script)
  are **not** copied.
- `bin/setup` sets `core.hooksPath` and regenerates the protected-branch sidecar — run it once before
  your first commit.
- **Full point-by-point walkthrough → [`docs/guides/usage.md`](docs/guides/usage.md).**

## Next steps

- **Customize** — edit [`PROJECT.md`](PROJECT.md) (preserved on re-sync, with an existing `bin/setup`) and add your
  domain Patterns / Anti-Patterns to the Rules Layer as Customization; leave `AGENTS.md` and the
  Adapters as the baseline so every tool stays in lockstep. Steps → [`usage.md`](docs/guides/usage.md).
- **Update / re-sync** — re-run `ruby bin/ai-config-sync /path/to/host-app`, then reconcile with
  `git diff`. Baseline files are overwritten; `PROJECT.md` and an existing `bin/setup` are preserved (`--force` overwrites `PROJECT.md` for a
  deliberate reset) ([ADR 0001](docs/adr/0001-distribute-as-copy-in-sync-script.md)).
- **Branch protection** — full setup, the AI-vs-human exemption, and the server-side (GitHub) step are
  in [`docs/guides/branch-protection.md`](docs/guides/branch-protection.md).

## Quality gate

This repo's own check is dependency-free (standard library only, no package manager):

```bash
ruby scripts/parity_check.rb
```

It verifies every Adapter still resolves to [`AGENTS.md`](AGENTS.md), that the `PROJECT.md` contract
sections are intact, and that all documented links resolve.
