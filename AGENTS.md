# AGENTS.md — Canonical Source

This is the **Canonical Source**: the one authored, model-neutral set of instructions every
configured AI coding agent (Claude, Codex, Copilot, Gemini) reads. Author instructions **here,
once**; each tool's own config file is a thin **Adapter** that resolves back to this file, so the
agents never receive drifted instructions. See [`CONTEXT.md`](CONTEXT.md) for the vocabulary used
throughout (Config Bundle, Adapter, Skill, Rules Layer, Project Config, …).

> This file is **business-neutral**. It carries no company, product, or domain content. A Host App
> adds that as **Customization** after vendoring — never here.

## How each tool consumes this file

Verified per-tool (2026-07-04, issue #3 → [`docs/research/tool-config-discovery.md`](docs/research/tool-config-discovery.md));
decision recorded in [ADR 0002](docs/adr/0002-agents-md-canonical-pointer-projection.md):

- **Claude Code** — reads `CLAUDE.md`, which imports this file via `@AGENTS.md` (expanded at launch).
- **Codex** — reads `AGENTS.md` **natively** by filename. No Adapter needed.
- **Copilot** — its PR-relevant surfaces (coding agent, code review, VS Code) read `AGENTS.md`
  **natively**. `.github/copilot-instructions.md` is only a discovery marker, not a copy.
- **Gemini** — reads `GEMINI.md`, which imports this file via `@AGENTS.md` (or names it via the
  `context.fileName` setting).

No tool follows a free-text "see AGENTS.md" pointer — resolution is either **import-expansion**
(`@AGENTS.md`) or **native discovery** (the tool reads `AGENTS.md` by filename). A parity check
(`scripts/parity_check.rb`, [ADR 0008](docs/adr/0008-structural-parity-check-not-model-in-the-loop.md))
keeps every Adapter resolving to this file.

## Project Config

Host-specific values live in **one** place — [`PROJECT.md`](PROJECT.md) — so these instructions stay
generic. Read it for: the quality-check commands, the attribution format and per-agent **model
declaration**, the branch/PR policy, the review-severity framework, and the lifecycle host. Never
hardcode any of those here; read them from `PROJECT.md`.

## Attribution

Every agent signs its work with **both its tool and its model version**, sourced from the single
declaration in [`PROJECT.md`](PROJECT.md) → *Attribution & Model Declaration*
([ADR 0007](docs/adr/0007-attribution-includes-model-version-for-audits.md)). Sign with your
**runtime-actual** model when you can determine it, reconciling against the declared default and
recording the actual if they differ. Use human-readable names (`Claude Opus 4.8`), never API ids
(`claude-opus-4-8`).

- **Commits** — a `Co-Authored-By: <Tool Model> <email>` trailer.
- **PRs, reviews, issue/PR comments** — a footer line, e.g. `— Claude Code (Opus 4.8)`.

## Branch & PR policy

Read the authoritative rules from [`PROJECT.md`](PROJECT.md) → *Branch & PR Policy*. In summary: work
on feature branches (never commit directly to a protected branch), open one PR per branch, and link
the issue with `Closes #N` for a leaf issue.

### Umbrella sub-PRs and closing keywords

When several PRs deliver one umbrella/epic issue, reference it as `Part of #N` and **never** place a
closing keyword (`close`/`closes`/`fix`/`fixes`/`resolve`/`resolves`) adjacent to `#N` — **even
negated** ("does not close #N" still registers; GitHub ignores the negation). A closing keyword on an
umbrella auto-closes it when the first sub-PR merges, orphaning the remaining phases. Close the
specific phase sub-issue instead.

## Development lifecycle

The lifecycle is issue/PR-shaped: **Assess → Plan → Implement → Verify → Deliver**, plus a
review-response step. `assess`/`cplan` post to an issue; `impl` opens a PR; `verify`/`rtr`/`final`
operate on that PR. Two human gates are mandatory — **plan approval** and **merge** — and are never
bypassed. GitHub is the default lifecycle host, set in `PROJECT.md` and remappable
([ADR 0006](docs/adr/0006-baseline-skill-set-and-github-default-lifecycle-host.md)). The full stage
spec — stages, roles, gates, and terminal artifacts — is
[`docs/standards/development-lifecycle.md`](docs/standards/development-lifecycle.md).

## Skills

The Generic Baseline ships nine Skills — `grill-with-docs`, `assess`, `cplan`, `impl`, `verify`,
`rtr`, `final`, `ship`, `scout` ([ADR 0006](docs/adr/0006-baseline-skill-set-and-github-default-lifecycle-host.md),
[ADR 0012](docs/adr/0012-intake-pipeline-placement.md)). Each is authored once as a canonical body
(`skills/<name>/SKILL.md`) and reached through a thin, tool-specific Invocation Shim; the procedure and
quality gates are identical on every tool, and only tool-specific execution enhancements degrade
gracefully.

### Invoking a Skill

A Skill's canonical body lives at `skills/<name>/SKILL.md` (Anthropic's portable Skill format: YAML
frontmatter + markdown body + optional bundled files). How each tool invokes it
([ADR 0003](docs/adr/0003-skills-canonical-body-thin-shims-graceful-degradation.md)):

- **Claude Code** — a slash command from the thin shim at `.claude/commands/<name>.md` (e.g.
  `/grill-with-docs`), which points at the canonical body.
- **Codex / Copilot / Gemini** — no slash command; these tools read `AGENTS.md` natively, so **the
  documented procedure is the shim**: to run a Skill, read and follow its canonical body at
  `skills/<name>/SKILL.md`. (A tool may additionally define a native prompt/command file where it
  supports one; the Generic Baseline ships none yet.)

**Shipped (9 of 9):**

- [`grill-with-docs`](skills/grill-with-docs/SKILL.md) — a plan-grilling / brainstorming session that
  stress-tests a plan against the project's domain language and captures decisions inline as a
  `CONTEXT.md` glossary and `docs/adr/` ADRs (with sibling format specs `CONTEXT-FORMAT.md` and
  `ADR-FORMAT.md`).
- The six lifecycle Skills, each reading its host values from [`PROJECT.md`](PROJECT.md) and posting
  to the host named in [`PROJECT.md`](PROJECT.md) → *Lifecycle Host*, never hardcoding a stack or
  platform: [`assess`](skills/assess/SKILL.md) → [`cplan`](skills/cplan/SKILL.md) →
  [`impl`](skills/impl/SKILL.md) → [`verify`](skills/verify/SKILL.md) →
  [`rtr`](skills/rtr/SKILL.md) → [`final`](skills/final/SKILL.md). Their five-stage spec is
  [`docs/standards/development-lifecycle.md`](docs/standards/development-lifecycle.md).
- [`ship`](skills/ship/SKILL.md) — the hands-off orchestrator that sequences the six lifecycle Skills
  end to end, delegating output-heavy work to discardable sub-agents while protecting the two human
  gates ([ADR 0005](docs/adr/0005-ship-hybrid-delegation-offload-retrieval-protect-judgment.md)). It
  adds no phase procedure of its own — the sequencing, delegation policy, and gates are its contract.
- [`scout`](skills/scout/SKILL.md) — the intake-pipeline sweep: reads the Watchlist declared in
  [`PROJECT.md`](PROJECT.md) → *Intake Pipeline*, drafts dated Learnings-Log entries that each carry a
  `stance` and a `touches` target, and opens a PR of them for a human to accept, edit, or reject —
  the sweep proposes, a human disposes ([ADR 0012](docs/adr/0012-intake-pipeline-placement.md)). Runs
  identically invoked by hand or on a schedule; wiring the schedule — cadence, enable/disable, and the
  empty-sweep (no-PR, log-only) behavior — is covered in the
  [intake-sweep scheduling guide](docs/guides/intake-sweep-scheduling.md)
  ([ADR 0013](docs/adr/0013-scheduled-intake-sweep-and-empty-sweep-policy.md)).

## Rules Layer

Host guidance is loaded in two tiers so session context stays lean
([ADR 0004](docs/adr/0004-two-tier-rules-layer-progressive-context.md)):

- **Tier 1 — Lean Core** (`rules/*.md`): small, always-resident, invariant per-domain rule files,
  each with a **Patterns** and a required **Anti-Patterns** section. The Generic Baseline ships
  business-neutral starters, marked *extend per host*:
  - [`rules/backend.md`](rules/backend.md) — models, controllers, jobs, services; Rails-ecosystem-first.
  - [`rules/frontend.md`](rules/frontend.md) — Hotwire (Turbo + Stimulus), ViewComponent, assets.
  - [`rules/testing.md`](rules/testing.md) — factories over fixtures, behavior-level assertions.
  - [`rules/security.md`](rules/security.md) — credentials, secret hygiene, scanners.
  - [`rules/self-review.md`](rules/self-review.md) — the before-done quality checklist.
  - [`rules/scripting.md`](rules/scripting.md) — bundled `bin/`/`scripts/` authoring (ASCII-safe output, stdlib-only).
  - [`rules/skills.md`](rules/skills.md) — authoring generic, single-sourced Skill bodies + thin shims.
- **Tier 2 — Deferred Deep Docs** (`docs/rules/<domain>-postmortems.md`): heavy, subsystem-specific
  case studies, **not** auto-loaded — read on demand when a trigger fires. See
  [`docs/rules/README.md`](docs/rules/README.md) for the structure and the full trigger table.

The **trigger table** links each Tier-1 file to the deferred deep doc it points to:

| Working in… | Tier-1 rule | Deferred deep doc |
|---|---|---|
| `app/models/`, `app/controllers/`, `app/jobs/`, `app/services/` | `rules/backend.md` | `docs/rules/backend-postmortems.md` |
| `app/javascript/`, `app/views/`, `app/components/`, `app/assets/` | `rules/frontend.md` | `docs/rules/frontend-postmortems.md` |
| `spec/` | `rules/testing.md` | `docs/rules/testing-postmortems.md` |
| `app/`, `config/`, `lib/` | `rules/security.md` | `docs/rules/security-postmortems.md` |
| `bin/`, `scripts/` | `rules/scripting.md` | `docs/rules/scripting-postmortems.md` |
| `skills/`, `.claude/commands/` | `rules/skills.md` | `docs/rules/skills-postmortems.md` |

Claude's `.claude/rules/` auto-load can mirror the Lean Core as a tool-specific accelerator; the
Generic Baseline keeps a single canonical home under `rules/` (no duplicated tree) and leaves that
projection to a host.

## Quality gate

Before declaring any work in this repository done, run its quality check and get it green:

```
ruby scripts/parity_check.rb
```

A Host App's own checks (tests, linters, security scanners) are declared in
[`PROJECT.md`](PROJECT.md) → *Quality Checks*; run those too when working in a Host App.
