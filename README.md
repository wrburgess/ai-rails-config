# ai-config

**In plain terms:** modern coding teams increasingly use AI assistants (Claude, Codex, Copilot,
Gemini) to help write software. Each of those tools normally needs its own separate instructions, so
they drift apart and give inconsistent advice. This repo fixes that: you write the house rules **once**,
and every AI assistant on the project reads the same copy and behaves the same way. Drop it into a
project, adjust one settings file for your team, and your AI helpers start following a consistent,
reviewable playbook — with built-in guardrails so they can't do risky things like committing to a
protected branch. You don't need to understand the vocabulary below to get that benefit; the
[usage guide](docs/guides/usage.md) walks you through it step by step.

---

A generic, model-agnostic **AI-agent configuration layer** for software projects. It ships as a
portable, business-neutral **Generic Baseline** — one **Canonical Source** of instructions that
drives four AI coding agents (Claude, Codex, Copilot, Gemini) in lockstep — which you **vendor into a
Host App** and then customize.

For the precise vocabulary used throughout (Config Bundle, Generic Baseline, Adapter, Skill, Rules
Layer, Project Config, Customization…), see [`CONTEXT.md`](CONTEXT.md). The full instruction set is
[`AGENTS.md`](AGENTS.md) — the one file every agent resolves to.

**New here?** [`docs/guides/usage.md`](docs/guides/usage.md) is the end-to-end walkthrough — vendor,
activate the guardrails, customize through `PROJECT.md`, and run each skill per tool. The sections
below are the quick reference.

## What you get

- **[`AGENTS.md`](AGENTS.md)** — the Canonical Source (model- and business-neutral instructions).
- **Adapters** — thin per-tool files that resolve to `AGENTS.md`: [`CLAUDE.md`](CLAUDE.md),
  [`GEMINI.md`](GEMINI.md), and `.github/copilot-instructions.md`. (Codex reads `AGENTS.md`
  natively, so it needs no Adapter.)
- **[`PROJECT.md`](PROJECT.md)** — the Project Config: the one file a Host App edits to declare its
  own quality-check commands, attribution, branch policy, review-severity framework, and lifecycle
  host.
- **[`CONTEXT.md`](CONTEXT.md)** and **[`docs/adr/`](docs/adr)** — the domain glossary and the
  Architecture Decision Records behind the design.
- **`scripts/parity_check.rb`** — a dependency-free structural check that keeps every Adapter
  resolving to the Canonical Source.
- **Branch-protection guardrails** — `.githooks/` + `bin/guard-protected-branch`,
  `bin/install-git-hooks`, and the Claude `.claude/hooks/enforce-branch-creation.sh` fast-fail, which
  stop any agent (or accidental human) from committing/pushing to a protected branch. See
  *Branch protection* below.
- **Rules Layer** — a two-tier progressive-context knowledge layer
  ([ADR 0004](docs/adr/0004-two-tier-rules-layer-progressive-context.md)): the always-resident
  **Tier-1 Lean Core** — seven `rules/*.md` files (`backend`, `frontend`, `testing`, `security`,
  `self-review`, `scripting`, `skills`), each with Patterns + Anti-Patterns — plus the deferred
  **Tier-2 Deep Docs** (`docs/rules/`, read on demand via the trigger table). Business-neutral and
  stack-neutral starters; extend per host — concrete stack-named examples live in a matching **Stack
  Overlay** (e.g. `ai-config-rails`), vendored alongside the baseline.
- **Skills** — model-agnostic capabilities authored once as a canonical body (`skills/<name>/SKILL.md`)
  and reached through a thin per-tool Invocation Shim (Claude `.claude/commands/<name>.md`; other tools
  via native `AGENTS.md` discovery), so any configured agent runs the same procedure
  ([ADR 0003](docs/adr/0003-skills-canonical-body-thin-shims-graceful-degradation.md)). Shipped (11):
  `grill-with-docs`, the six lifecycle skills `assess`, `cplan`, `impl`, `verify`, `rtr`, `final`
  (their five-stage spec is `docs/standards/development-lifecycle.md`), the `ship` orchestrator that
  sequences those six end to end (Epic #1), the `scout` intake sweep (Epic #28), the `drop` intake
  front door that pushes a human-handed item into that sweep (Issue #46), and the `create-skill`
  authoring front door that scaffolds a new, conforming skill from full repo context (Issue #67).
- **Intake pipeline** — a living-knowledge sweep that keeps the bundle's reference material current
  ([ADR 0012](docs/adr/0012-intake-pipeline-placement.md),
  [ADR 0013](docs/adr/0013-scheduled-intake-sweep-and-empty-sweep-policy.md)): the
  [`scout`](skills/scout/SKILL.md) skill polls a **Watchlist** (`docs/reference/voices.yml`), drafts
  dated entries into an append-only **Learnings Log** (`docs/reference/learnings/`), and opens a PR of
  them for a human to accept, edit, or reject — the sweep proposes, a human disposes. The
  [`drop`](skills/drop/SKILL.md) skill is the pipeline's **push front door** complementing `scout`'s
  **pull** sweep: hand it a screenshot, a link, or a quote and it enforces a real-URL gate, writes a
  stance-less drop into the manual-drop inbox, and delegates to `scout` to draft the entry and open
  that same review PR ([ADR 0015](docs/adr/0015-intake-front-door-drop-skill.md)). Ships as an
  **illustrative reference seed**; repoint or extend it per host via `PROJECT.md` → *Intake Pipeline*.

## Technical overview

For a reader who *is* AI/software-savvy, here is how the pieces fit — the architecture and the design
intent, without reading every ADR:

- **One source of truth → adapters (projection, not duplication).** All instructions are authored once
  in [`AGENTS.md`](AGENTS.md), the **Canonical Source**. Each tool reaches it through a thin **Adapter**
  that *resolves back* to that file rather than copying it: Claude and Gemini import it
  (`@AGENTS.md` in [`CLAUDE.md`](CLAUDE.md) / [`GEMINI.md`](GEMINI.md)), while Codex and Copilot read
  `AGENTS.md` natively by filename ([ADR 0002](docs/adr/0002-agents-md-canonical-pointer-projection.md)).
  No tool follows a free-text "see AGENTS.md" pointer, so the agents never receive drifted instructions.
- **A structural parity gate, not a model in the loop.** `scripts/parity_check.rb` is a dependency-free
  structural check that asserts every Adapter still resolves to the Canonical Source, the `PROJECT.md`
  contract sections are intact, and every documented link resolves — a fast, deterministic guard that
  drift is mechanically impossible to merge ([ADR 0008](docs/adr/0008-structural-parity-check-not-model-in-the-loop.md)).
- **A two-tier Rules Layer for progressive context.** Tier 1 is the always-resident **Lean Core**
  (`rules/*.md`, small and invariant); Tier 2 is heavy, subsystem-specific **Deep Docs**
  (`docs/rules/`) that are *not* auto-loaded but pulled in on demand via a trigger table — keeping the
  session context lean while deep knowledge stays one hop away
  ([ADR 0004](docs/adr/0004-two-tier-rules-layer-progressive-context.md)).
- **A single-sourced Skill model.** Each Skill is authored once as a canonical body
  (`skills/<name>/SKILL.md`) and invoked through a per-tool shim; only tool-specific execution
  enhancements degrade gracefully, never the procedure or the quality gates
  ([ADR 0003](docs/adr/0003-skills-canonical-body-thin-shims-graceful-degradation.md)). The lifecycle
  Skills (`assess` → `cplan` → `impl` → `verify` → `rtr` → `final`) implement an issue/PR-shaped
  workflow with two mandatory human gates (plan approval, merge).
- **`ship` — delegation by output-weight.** The orchestrator sequences the six lifecycle Skills end to
  end while keeping a lean main context: it **offloads output-heavy, signal-light** work (codebase
  exploration, the code+check+fix loop, full-diff review) to discardable sub-agents that return a
  compact handoff contract, and **keeps judgment-heavy** work (plan authoring, review-severity calls,
  merge-readiness) in the clean orchestrator — so a lossy summary can't silently steer the outcome
  ([ADR 0005](docs/adr/0005-ship-hybrid-delegation-offload-retrieval-protect-judgment.md)).
- **`scout` — a propose-then-dispose intake pipeline.** A scheduled or hand-run sweep polls the
  Watchlist, drafts dated Learnings-Log entries (each carrying a `stance` and a `touches` target), and
  opens a PR for a human to accept, edit, or reject — automation gathers, a human decides
  ([ADR 0012](docs/adr/0012-intake-pipeline-placement.md),
  [ADR 0013](docs/adr/0013-scheduled-intake-sweep-and-empty-sweep-policy.md)).

The design intent throughout: **author once, resolve everywhere, and guard the resolution with a
deterministic check** — so four different AI tools stay in lockstep without a human hand-syncing four
copies of the rules.

## Vendor it into a Host App

The bundle is distributed by **copying files in** — no submodule, no package, no upstream tracking
([ADR 0001](docs/adr/0001-distribute-as-copy-in-sync-script.md)). From a clone of this repo:

```bash
# Preview what would be copied (writes nothing):
ruby bin/ai-config-sync --dry-run /path/to/host-app

# Vendor the bundle in:
ruby bin/ai-config-sync /path/to/host-app
```

The Host App ends up **owning plain files** at their expected paths (real files, never symlinks).
`ai-config-sync` copies each top-level bundle surface **only if it exists**, so it behaves the same
as the baseline grows. It does **not** copy this repo's own meta files (`README.md`, `LICENSE`,
`.gitignore`, `test/`, or the `ai-config-sync` script itself), and it never touches your Host App's
own `.gitignore`.

## Customize after vendoring

The split between **Generic Baseline** and **Customization** is what keeps future updates
mergeable — author host-specific content as Customization, never by editing the baseline files in
place.

1. **Edit [`PROJECT.md`](PROJECT.md)** — the single Customization surface the agents read for
   host-specific values (real check commands, attribution model, protected branches, severities,
   lifecycle host). This is the one file `ai-config-sync` **preserves** on a re-sync.
2. **Add your domain rules** to the Rules Layer (host-specific patterns and anti-patterns) as
   Customization — keep them separate from the baseline starters.
3. **Leave `AGENTS.md` and the Adapters as the baseline** so every tool stays in lockstep; host
   values flow in through `PROJECT.md`, not by forking the Canonical Source.

## Update / re-sync

Updating is a **re-run of the sync followed by a manual merge**
([ADR 0001](docs/adr/0001-distribute-as-copy-in-sync-script.md)):

```bash
ruby bin/ai-config-sync /path/to/host-app
```

Baseline files are overwritten; **`PROJECT.md` is preserved** (pass `--force` to overwrite it too
for a deliberate reset). Review the changes with `git diff` in the Host App and reconcile any
Customization.

## Branch protection

The bundle ships defense-in-depth branch protection so no agent — or accidental human — commits or
pushes to a protected branch ([ADR 0009](docs/adr/0009-defense-in-depth-branch-protection-all-agents.md)).
The protected-branch list is **not hardcoded**: it is authored in [`PROJECT.md`](PROJECT.md) →
*Branch & PR Policy* and derived into the sidecar `.githooks/protected-branches` that the guards read.

Git hooks are inactive on a fresh clone until `core.hooksPath` is set, so run once after cloning (or
after vendoring into a Host App):

```bash
bin/setup            # runs bin/install-git-hooks (sets core.hooksPath, regenerates the sidecar)
```

A Host App with its own richer `bin/setup` keeps it — `ai-config-sync` **preserves** an existing
`bin/setup` (like `PROJECT.md`) on re-sync — and adds `bin/install-git-hooks` to that script. Full
setup, the AI-vs-human exemption, and the server-side (GitHub) step are documented in
[`docs/guides/branch-protection.md`](docs/guides/branch-protection.md).

## Quality gate

This repo's own check is dependency-free (standard library only, no package manager):

```bash
ruby scripts/parity_check.rb
```

It verifies every Adapter still resolves to [`AGENTS.md`](AGENTS.md), that the `PROJECT.md` contract
sections are intact, and that all documented links resolve.
