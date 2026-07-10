# ai-config

A generic, model-agnostic **AI-agent configuration layer** for software projects — vendor it into a
project, edit one file, and every AI coding assistant follows the same reviewable playbook.

## TL;DR

- **What it is** — one **Canonical Source** of instructions ([`AGENTS.md`](AGENTS.md)) that drives five
  AI coding agents (Claude, Codex, Copilot, Antigravity, Grok Build) in lockstep.
- **Why it exists** — each AI tool normally needs its own instructions, so they drift and give
  inconsistent advice. Here you write the house rules **once**; every agent reads the same copy and
  behaves the same way — with built-in guardrails that stop risky actions like committing to a
  protected branch.
- **How you use it** — vendor the bundle into your project (a **Host App**), edit **one** file
  (`PROJECT.md`) for your team, and go. See [Get started](#get-started).
- **New here?** The full walkthrough is [`docs/guides/usage.md`](docs/guides/usage.md); the vocabulary
  (Config Bundle, Adapter, Skill, Rules Layer…) is in [`CONTEXT.md`](CONTEXT.md).

## What it is & how it works

Seven pillars — each a **benefit**, then the mechanisms that prove it. The throughline is **author
once, resolve everywhere, and guard the resolution with a deterministic check**, so five different AI
tools stay in lockstep with no human hand-syncing. **Secure** leads the list, and **Efficient** is on
the roadmap.

1. **Secure — stops any agent (or human) from committing to a protected branch, and keeps secrets out
   of the repo.**
   - Defense-in-depth branch protection: portable git hooks (`.githooks/` +
     `bin/guard-protected-branch` + `bin/install-git-hooks`) *and* a per-tool fast-fail
     (`.claude/hooks/enforce-branch-creation.sh`) block the write before it happens.
   - The protected-branch list is authored in [`PROJECT.md`](PROJECT.md), never hardcoded.
   - Secret hygiene lives in [`rules/security.md`](rules/security.md)
     ([ADR 0009](docs/adr/0009-defense-in-depth-branch-protection-all-agents.md)).

2. **Portable — write the house rules once, and Claude, Codex, Copilot, Antigravity & Grok Build all read the same
   copy.**
   - Every instruction is authored once in the Canonical Source [`AGENTS.md`](AGENTS.md).
   - Each tool reaches it through a thin **Adapter** that *resolves back* rather than copying: Claude
     and Antigravity import it via `@AGENTS.md`, while Codex, Copilot, and Grok Build read `AGENTS.md` natively. No tool
     follows a free-text pointer, so none receives drifted instructions.
   - `scripts/parity_check.rb` enforces zero drift as a merge gate
     ([ADR 0002](docs/adr/0002-agents-md-canonical-pointer-projection.md),
     [ADR 0008](docs/adr/0008-structural-parity-check-not-model-in-the-loop.md)).

3. **Methodical — a repeatable, human-gated path from idea to merge.**
   - Six lifecycle Skills — `/assess → /devise → /invoke → /verify → /listen → /final` — carry an issue
     to a merged PR, with `/distill` to sharpen the plan first and `/ship` to run the whole sequence
     hands-off.
   - **Plan approval** and **merge** are mandatory human gates that are never bypassed
     ([ADR 0006](docs/adr/0006-baseline-skill-set-and-github-default-lifecycle-host.md)).
   - `/ship` stays lean by offloading output-heavy work to discardable sub-agents while keeping the
     judgment calls in a clean orchestrator
     ([ADR 0005](docs/adr/0005-ship-hybrid-delegation-offload-retrieval-protect-judgment.md)).

4. **Customizable — tailor it to any project without forking the baseline.**
   - One Customization surface — [`PROJECT.md`](PROJECT.md) — where a Host App declares its quality
     checks, attribution/model, branch policy, review severities, and lifecycle host.
   - A two-tier **Rules Layer** (an always-resident Lean Core of `rules/*.md` plus Deferred Deep Docs
     pulled in on demand) carries the domain guidance.
   - The baseline stays stack-neutral — extend it per host, or vendor a matching **Stack Overlay** (e.g.
     `ai-config-rails`) alongside
     ([ADR 0004](docs/adr/0004-two-tier-rules-layer-progressive-context.md)).

5. **Transparent — see *who/what* made each change and *why* each decision was made.** Two mechanisms,
   answering two questions:
   - **Attribution → *who/what*.** Every commit carries a `Co-Authored-By: <tool> <model>` trailer and
     every PR/review/comment a `— <tool> (<model>)` footer, all sourced from one declaration in
     [`PROJECT.md`](PROJECT.md) — so provenance is never ambiguous
     ([ADR 0007](docs/adr/0007-attribution-includes-model-version-for-audits.md)).
   - **ADRs → *why*.** Every non-trivial choice is a numbered, append-only Architecture Decision Record
     in [`docs/adr/`](docs/adr) — context, options weighed, decision + consequences — so the config
     never decays into unexplained conventions.
   - *Methodical vs. Transparent:* Methodical means the process is disciplined **up front** (gates,
     stages), while Transparent means you can **audit it after the fact** (who/what/why).

6. **Evolving — watches the field and proposes updates for you to approve.**
   - `/scout` **pulls** — polling a **Watchlist** (`docs/reference/voices.yml`) and drafting dated
     **Learnings Log** entries (`docs/reference/learnings/`).
   - `/clip` **pushes** a screenshot, link, or quote you hand it.
   - `/follow` curates the Watchlist roster.
   - Every path opens a review PR, and **a human always disposes**
     ([ADR 0012](docs/adr/0012-intake-pipeline-placement.md),
     [ADR 0015](docs/adr/0015-intake-front-door-drop-skill.md)).

7. **Efficient — the right model for each job: cheap work on cheap models, judgment on the frontier.**
   - Cost-aware model routing.
   - `/restock` maintains the **Tool Roster** (`docs/reference/tool-roster.yml`) — a current-state
     snapshot of coding harnesses & models (versions, cost, effort tiers) that informs those choices
     ([ADR 0023](docs/adr/0023-tool-roster-facts-tracker-sibling-to-intake.md)).
   - *Roadmap ([#77](https://github.com/wrburgess/ai-config/issues/77)):* today only the per-agent
     model **declaration** in [`PROJECT.md`](PROJECT.md) exists — not yet the routing that spends it
     wisely.

Every pillar above traces to a numbered ADR in [`docs/adr/`](docs/adr). The domain vocabulary (Config
Bundle, Adapter, Skill, Rules Layer…) is defined in [`CONTEXT.md`](CONTEXT.md).

## The Research Roster — how the config keeps up with the field

**Why.** The practice of AI-assisted engineering moves weekly; a config bundle frozen on the day it was
written would rot. The **Research Roster** is the intake pipeline that keeps this repo's own guidance
current — it watches a curated roster of field *voices* and proposes durable learnings back into the
Rules Layer, Skills, and ADRs. It **proposes; a human always disposes** on a review PR.

**How.** Three skills feed one append-only **Learnings Log**, reading their source list from a
version-controlled **Watchlist** ([ADR 0012](docs/adr/0012-intake-pipeline-placement.md)):

- **`/scout`** — the **pull** sweep: polls the Watchlist (and the manual-drop inbox), drafts dated
  Learnings-Log entries that each carry a `stance` (*confirms / challenges / extends / orthogonal*) and a
  `touches` target, and opens a review PR. A stance-less finding is dropped — that discipline is what
  keeps the log from decaying into a link dump.
- **`/clip`** — the **push** front door: hand it a screenshot, link, or quote in any session and it writes
  a well-formed, stance-less drop for the next sweep to turn into a learning
  ([ADR 0015](docs/adr/0015-intake-front-door-drop-skill.md)).
- **`/follow`** — the **roster** front door: turns a bare handle or link into the right add-or-update on
  the Watchlist, deduping so an already-tracked voice is refreshed, not duplicated
  ([ADR 0021](docs/adr/0021-voice-watchlist-front-door.md)).

The sweep runs by hand or on a schedule; only disposition differs (interactive one-at-a-time vs.
asynchronous-on-PR). Nothing merges without a human.

## The Tool Roster — knowing your options at a glance

**Why.** Choosing *which* agent and model to run for a task — the **Efficient** pillar's "right tool at
the right price" — needs a current, trustworthy map of the options. Harness versions move almost daily and
models every few weeks, and the changelog firehose is unreadable. The **Tool Roster** is the condensed
answer: a current-state snapshot of the harnesses and models worth weighing for software development, so
the choice reads off one board instead of a dozen vendor pages
([ADR 0023](docs/adr/0023-tool-roster-facts-tracker-sibling-to-intake.md)).

**How.** A version-controlled artifact ([`docs/reference/tool-roster.yml`](docs/reference/tool-roster.yml))
holds two normalized lists — **harnesses** (which carry config) and **models** (which are declared) — each
keyed by product *line* with the current version, cost, effort tiers, and a provenance-typed trust marker
on every value (vendor-fact / benchmark / flagged estimate). It is a **snapshot**, not a log: the git diff
is the history.

- **`/restock`** refreshes it: re-verifies each entry's facts against that entry's own `sources:`
  (reconfirm-or-age, **never fabricate**), writes only the real deltas, and opens a review PR — staying
  quiet when nothing changed.
- It runs on a **weekday-morning** cadence and pushes only *what changed* — host-configured and documented,
  not shipped ([scheduling guide](docs/guides/tool-roster-refresh-scheduling.md)).

The **Tool Roster** (tools to pick from) is the sibling of the **Research Roster** (voices to learn from) —
one tracks *facts*, the other *opinions*.

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
