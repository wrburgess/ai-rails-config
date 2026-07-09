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

Seven pillars — each a **benefit**, then the mechanism that proves it. The throughline is **author
once, resolve everywhere, and guard the resolution with a deterministic check**, so four different AI
tools stay in lockstep with no human hand-syncing. **Secure** leads the list; **Efficient** is on the
roadmap.

1. **Secure — stops any agent (or human) from committing to a protected branch, and keeps secrets out
   of the repo.** Defense-in-depth branch protection — portable git hooks (`.githooks/` +
   `bin/guard-protected-branch` + `bin/install-git-hooks`) *and* a per-tool fast-fail
   (`.claude/hooks/enforce-branch-creation.sh`) — blocks the write before it happens; the protected
   list is authored in [`PROJECT.md`](PROJECT.md), never hardcoded. Secret hygiene lives in
   [`rules/security.md`](rules/security.md)
   ([ADR 0009](docs/adr/0009-defense-in-depth-branch-protection-all-agents.md)).

2. **Portable — write the house rules once; Claude, Codex, Copilot & Gemini all read the same copy.**
   Every instruction is authored once in the Canonical Source [`AGENTS.md`](AGENTS.md); each tool reaches
   it through a thin **Adapter** that *resolves back* rather than copying (Claude and Gemini import it
   via `@AGENTS.md`; Codex and Copilot read `AGENTS.md` natively). No tool follows a free-text pointer,
   so none receives drifted instructions — and `scripts/parity_check.rb` enforces zero drift as a merge
   gate ([ADR 0002](docs/adr/0002-agents-md-canonical-pointer-projection.md),
   [ADR 0008](docs/adr/0008-structural-parity-check-not-model-in-the-loop.md)).

3. **Methodical — a repeatable, human-gated path from idea to merge.** Six lifecycle Skills —
   `/assess → /devise → /invoke → /verify → /listen → /final` — carry an issue to a merged PR, with
   `/distill` to sharpen the plan first and `/ship` to run the whole sequence hands-off. **Plan
   approval** and **merge** are mandatory human gates that are never bypassed
   ([ADR 0006](docs/adr/0006-baseline-skill-set-and-github-default-lifecycle-host.md)); `/ship` stays
   lean by offloading output-heavy work to discardable sub-agents while keeping the judgment calls in a
   clean orchestrator ([ADR 0005](docs/adr/0005-ship-hybrid-delegation-offload-retrieval-protect-judgment.md)).

4. **Customizable — tailor it to any project without forking the baseline.** One Customization surface,
   [`PROJECT.md`](PROJECT.md), is where a Host App declares its quality checks, attribution/model, branch
   policy, review severities, and lifecycle host; a two-tier **Rules Layer** (an always-resident Lean
   Core of `rules/*.md` plus Deferred Deep Docs pulled in on demand) carries the domain guidance. The
   baseline stays stack-neutral — extend it per host, or vendor a matching **Stack Overlay** (e.g.
   `ai-config-rails`) alongside ([ADR 0004](docs/adr/0004-two-tier-rules-layer-progressive-context.md)).

5. **Transparent — see *who/what* made each change and *why* each decision was made.** Two mechanisms,
   answering two questions:
   - **Attribution → *who/what*.** Every commit carries a `Co-Authored-By: <tool> <model>` trailer and
     every PR/review/comment a `— <tool> (<model>)` footer, all sourced from one declaration in
     [`PROJECT.md`](PROJECT.md) — so provenance is never ambiguous
     ([ADR 0007](docs/adr/0007-attribution-includes-model-version-for-audits.md)).
   - **ADRs → *why*.** Every non-trivial choice is a numbered, append-only Architecture Decision Record
     in [`docs/adr/`](docs/adr) — context, options weighed, decision + consequences — so the config
     never decays into unexplained conventions.

   *Methodical vs. Transparent:* Methodical means the process is disciplined **up front** (gates,
   stages); Transparent means you can **audit it after the fact** (who/what/why).

6. **Evolving — watches the field and proposes updates for you to approve.** An intake pipeline keeps the
   bundle's reference material current: `/scout` **pulls** — polling a **Watchlist**
   (`docs/reference/voices.yml`) and drafting dated **Learnings Log** entries
   (`docs/reference/learnings/`) — while `/clip` **pushes** a screenshot, link, or quote you hand it, and
   `/follow` curates the Watchlist roster. Every path opens a review PR; **a human always disposes**
   ([ADR 0012](docs/adr/0012-intake-pipeline-placement.md),
   [ADR 0015](docs/adr/0015-intake-front-door-drop-skill.md)).

7. **Efficient — the right model for each job: cheap work on cheap models, judgment on the frontier.**
   Cost-aware model routing. *Roadmap — [#77](https://github.com/wrburgess/ai-config/issues/77): today
   only the per-agent model **declaration** in [`PROJECT.md`](PROJECT.md) exists, not yet the routing
   that spends it wisely.*

Every pillar above traces to a numbered ADR in [`docs/adr/`](docs/adr); the domain vocabulary (Config
Bundle, Adapter, Skill, Rules Layer…) is defined in [`CONTEXT.md`](CONTEXT.md).

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
