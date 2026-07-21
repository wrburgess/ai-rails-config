# PROJECT.md — Project Config

The **Project Config**: the one place a Host App declares its host-specific values so the Skills and
[Canonical Source](AGENTS.md) stay generic. A vendoring Host App edits the values in this file; it
does not edit `AGENTS.md` to change them. This file ships with **business-neutral placeholders** —
replace them during Customization.

> Section headings below are a contract: the parity check (`scripts/parity_check.rb`) asserts the
> **five required** `##` sections are present — *Quality Checks*, *Attribution & Model Declaration*,
> *Branch & PR Policy*, *Review Severity Framework*, *Lifecycle Host*. Rename one and the check fails.
> This file ships **more** sections than that floor (*Human Gates*, *Intake Pipeline*, *Tool Roster*);
> those are additive, so a Host App that predates one of them stays green.

## Quality Checks

The commands an agent must run and get green before declaring work done. The generalized Skills read
this table — they never hardcode a stack's commands. **Host Apps: replace these rows with your real
commands during Customization** (e.g. a Rails host: lint `bundle exec rubocop -a`, tests
`bundle exec rspec`, security `bin/brakeman --no-pager -q`, dependency audit `bin/bundler-audit check`;
a JS/TS host: lint `npm run lint`, tests `npm test`, dependency audit `npm audit`). A **Stack Overlay**
such as `ai-config-rails` can ship a ready-to-paste command set for its stack.

This config repo ships no application code, so its own gate is the structural parity check plus the
dependency-free stdlib self-tests:

| Purpose | Command |
|---------|---------|
| Structural parity | `ruby scripts/parity_check.rb` |
| Self-tests | `ruby test/parity_check_test.rb` |

A check whose command runs but has nothing applicable to inspect (e.g. no application code to lint) is
reported `pass`/`not_run` with a stated reason — checks are **not applicable, not skipped**, so rigor
is unchanged.

## Attribution & Model Declaration

Single source of truth for agent attribution ([ADR 0007](docs/adr/0007-attribution-includes-model-version-for-audits.md)).
Bump the model here — in one place — when the host switches models. Skills sign with the
**runtime-actual** model when determinable, reconciling against these declared defaults and recording
the actual if they differ. Use human-readable names, never API ids.

| Agent (harness) | Declared model | Identity email |
|-----------------|----------------|----------------|
| Claude Code | `Claude Opus 4.8` | `noreply@anthropic.com` |
| Codex | `GPT (host sets model)` | `<host sets>` |
| Copilot | `model varies (GPT / Claude / Gemini)` | `<host sets>` |
| Antigravity | `Gemini Flash (host sets model)` | `<host sets>` |
| Grok Build | `Grok (host sets model)` | `<host sets>` |

- **Commit trailer:** `Co-Authored-By: <Tool Model> <email>` — e.g.
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **PR / review / comment footer:** `— <Tool> (<Model>)` — e.g. `— Claude Code (Opus 4.8)`.
- Attribution shows **per-agent identity** so provenance reflects which agent did the work. The
  *Agent* column names the **harness** (Claude Code · Codex · Copilot · Antigravity · Grok Build); the *Declared
  model* column names the **model** it runs — never the harness — per the naming convention in
  [ADR 0024](docs/adr/0024-harness-model-naming-convention.md). Copilot's backing model is
  variable/unknown, so its declared model reads `model varies (GPT / Claude / Gemini)`.

## Branch & PR Policy

- **Protected branches:** `main`, `master`, `develop` — this backticked list (everything up to the
  em dash) is the **authored source** the guardrails derive from. Never commit or push directly to a
  protected branch; agents work on feature branches. A host may trim or extend the backticked list,
  then run `bin/install-git-hooks` to regenerate the derived sidecar `.githooks/protected-branches`.
  Enforcement (git hooks + per-tool fast-fail) is delivered by the guardrails baseline
  ([ADR 0009](docs/adr/0009-defense-in-depth-branch-protection-all-agents.md)) and sources this list.
- **Branch naming:** `feature/` · `fix/` · `chore/` · `docs/` prefixes (host may extend).
- **One PR per branch**, opened ready-for-review (not draft).
- **Issue linking:** `Closes #N` for a leaf issue; `Part of #N` (no closing keyword, even negated) for
  an umbrella/epic sub-PR — see `AGENTS.md` → *Umbrella sub-PRs and closing keywords*.
- **Feature-branch autonomy:** commit/edit/refactor without asking on a feature branch; ask before any
  change to a protected branch.

## Review Severity Framework

Generic starter severities for `verify`/`listen`/`final` and human review. A Host App tunes the
definitions.

| Severity | Meaning | Disposition |
|----------|---------|-------------|
| **Critical** | Data loss, security hole, breaks protected-branch or auth invariants, or ships broken. | Block merge; fix before proceeding. |
| **High** | Correctness bug, missing required test, or a violated project rule. | Fix in this PR before merge. |
| **Medium** | Maintainability, clarity, or a smaller coverage gap. | Fix now or file a tracked follow-up. |
| **Low** | Style, naming, or optional polish. | Author's discretion. |

## Lifecycle Host

- **Host platform:** `GitHub` (default). The issue/PR verbs the Skills use are isolated so a Host App
  on another platform (e.g. GitLab) can remap the artifact targets without rewriting skill bodies
  ([ADR 0006](docs/adr/0006-baseline-skill-set-and-github-default-lifecycle-host.md)).
- **Artifact map:** assessments/plans → issue comments; implementation → a PR; SOW → a PR comment.
- **Copilot adapter mode:** `native` (Generic Baseline default) — Copilot reads `AGENTS.md` natively
  and `.github/copilot-instructions.md` is a discovery marker. Set to `render` (a byte-for-byte
  `parity:render` block in `.github/copilot-instructions.md`) only if the host drives work through a
  legacy in-editor Copilot IDE; the parity check enforces the render matches `AGENTS.md`.

## Reviewer

The **independent second-model Reviewer** the lifecycle summons at the plan and PR gates — declared
here so a generic Skill body names the *role* while the host names the *identity*
([ADR 0026](docs/adr/0026-reviewer-is-a-project-config-value-ac-summons-floor-preserved.md), the same
argument shape as the lifecycle host in [ADR 0006](docs/adr/0006-baseline-skill-set-and-github-default-lifecycle-host.md)
and the gate policy in [ADR 0025](docs/adr/0025-human-gate-policy-is-a-project-config-value.md)).
Ships **business-neutral placeholders**; a Host App names its real reviewer during Customization.

Like *Human Gates*, this heading is deliberately **absent from the parity check's required sections**,
so an already-vendored Host App whose `PROJECT.md` predates it keeps parsing to the shipped defaults
and stays green.

| Field | Setting | Allowed values |
|-------|---------|----------------|
| **Primary** — the reviewer summoned first | `Codex (GPT - host sets model)` | any harness in *Attribution & Model Declaration* |
| **Fallback order** — tried in turn when the primary is unreachable or silent | `Copilot` | comma-separated harnesses, or `none` |
| **Bounded window** — how long to wait for a response before falling back | `30m` | `<integer><unit>`, unit one of `s` · `m` · `h` |
| **Degradation floor** — what happens when the whole chain is exhausted | `stop-and-ask` | `stop-and-ask` (not configurable) |

- **The degradation floor is not configurable.** `stop-and-ask` is its only allowed value and the
  parity check hard-fails any other, on the same footing as merge: a run that cannot obtain an
  independent review must not be able to certify itself. The AC stops and asks the HC — it never
  delivers unreviewed with a footnote ([ADR 0026](docs/adr/0026-reviewer-is-a-project-config-value-ac-summons-floor-preserved.md)
  decision 3, affirming [ADR 0005](docs/adr/0005-ship-hybrid-delegation-offload-retrieval-protect-judgment.md)).
- **The AC summons the Reviewer, not the HC**, and [`verify`](skills/verify/SKILL.md) is the **sole
  owner** of the summons. No other Skill issues one — a duplicated summons produces two review
  requests and two windows, and makes "did the primary respond?" unanswerable.
- **A response** is a reply on **any** of the three surfaces — an issue-level PR comment, an **inline
  diff thread**, or a **review body**. Reading only the first makes an automated inline review
  invisible.
- **Timeout and unreachable are distinct outcomes**, carried forward separately: "no second model
  exists" and "the second model is slow" call for different HC responses, and collapsing them loses
  information the SOW cannot reconstruct.

### Invocation paths

The mechanism for summoning each harness, and the **precondition that must be verified first**. The
precondition is *checked*, not merely documented — an unmet one fails immediately into the fallback
rather than burning the window on a summons nobody receives
([ADR 0026](docs/adr/0026-reviewer-is-a-project-config-value-ac-summons-floor-preserved.md)
decision 4). A Host App replaces these rows with its real commands during Customization.

| Harness | Summons | Precondition | Check |
|---------|---------|--------------|-------|
| Codex | mention `@codex review` on the PR | its GitHub app is installed on the repository | list the repo's installed apps and confirm the slug is present |
| Copilot | request a PR review via the host platform's API | the account has Copilot code review enabled | request returns success rather than a not-enabled error |
| *(host adds its own)* | — | — | — |

## Human Gates

Which lifecycle pauses require a human, declared here so a generic Skill body names the *gate* instead
of hardcoding a policy a host would otherwise have to fork the file to change
([ADR 0025](docs/adr/0025-human-gate-policy-is-a-project-config-value.md), the same argument shape as
the host-platform value in [ADR 0006](docs/adr/0006-baseline-skill-set-and-github-default-lifecycle-host.md)).
The Generic Baseline ships the **strict** policy, and every Skill body states that default inline — so
a Host App that never touches this section behaves exactly as it did before the section existed.

| Gate | Setting | Allowed values |
|------|---------|----------------|
| **Plan approval** — covers both the Stage-1 option pick and the Stage-2 plan approval | `required` | `required` · `auto` |
| **Merge** — the HC merges the delivered PR | `required` | `required` (not configurable) |

- **`required`** (shipped default) — the AC stops and waits for the HC: it does not proceed past the
  assessment without a chosen option, and it does not write code without an approved plan.
- **`auto`** — a host may set the **plan-approval** row (and only that row) to `auto`. The AC then
  proceeds on **its own stated recommendation** rather than waiting. It still **posts** the assessment
  and the plan to the lifecycle host — under `auto` those comments are the *only* durable audit trail
  of what was decided, so posting them becomes more load-bearing, not less — and it **names in the
  posted comment** that it self-selected under `auto`. Under `auto` the AC may likewise elect the
  exploratory (spike-then-plan) path itself, stating its rationale in the plan.
- **Merge is not configurable.** `required` is the only allowed value: **no Host App may express
  self-merge.** The parity check hard-fails any other value. `final` posts the SOW; a human merges.

**Unconditional, whatever this section says:**

- **Merge is always human** (above).
- **The plan gate is also a session boundary, and the boundary survives the pause being waived.**
  "Plan posted" ends a session under either setting: [`invoke`](skills/invoke/SKILL.md) **begins by
  re-reading the posted plan from the issue** and never continues on conversational memory, and the
  pre-[`final`](skills/final/SKILL.md) context check still applies. `auto` removes the *wait*; it never
  removes the context firebreak.
- **[`ship`](skills/ship/SKILL.md)'s four emergency stops** — an unresolvable check failure; a discovery
  that the change touches core logic the plan did not anticipate; an architectural or ambiguous review
  comment; a handoff verdict the orchestrator cannot resolve — always stop and ask the HC.
- **[`listen`](skills/listen/SKILL.md)'s "wait for the HC to choose"** is out of scope for this setting
  and remains mandatory.
- **The lifecycle's "the HC decides when to compress"** remains mandatory for every row of its
  *When to skip or compress stages* table **but one**: `auto` waives exactly three pauses — the Stage-1
  option pick, the Stage-2 plan approval, and the **exploratory (spike-then-plan) election** named
  above, which chooses *how to plan* rather than skipping a stage. The trivial-fix, bug-fix,
  documentation-only and large-change rows each compress away a *stage* and stay the HC's call.
- **The intake and authoring "a human disposes" gates** — [`scout`](skills/scout/SKILL.md),
  [`clip`](skills/clip/SKILL.md), [`follow`](skills/follow/SKILL.md),
  [`restock`](skills/restock/SKILL.md), [`create-skill`](skills/create-skill/SKILL.md)
  ([ADR 0014](docs/adr/0014-manual-drop-inbox-for-unfetchable-sources.md),
  [ADR 0016](docs/adr/0016-interactive-sequential-disposition-scout.md)) — are out of scope too.
  `auto` is **not** licence to auto-merge any of their review PRs.

## Intake Pipeline

The artifact locations the [`scout`](skills/scout/SKILL.md) sweep reads and writes, declared here so
the generic Skill body names no path ([ADR 0012](docs/adr/0012-intake-pipeline-placement.md)). These
ship as **business-neutral placeholders** pointing at the illustrative reference seed; a Host App
repoints them during Customization if it relocates its intake artifacts.

| Artifact | Location |
|----------|----------|
| **Watchlist** — the machine-readable source list the sweep polls | [`docs/reference/voices.yml`](docs/reference/voices.yml) |
| **Learnings Log** — the dated, append-only entries + their index | [`docs/reference/learnings/`](docs/reference/learnings/) |
| **Last-swept marker** — the recency stamp the next sweep reads for its incremental window | the `**Last swept:**` line in the Learnings-Log [`index.md`](docs/reference/learnings/index.md) |
| **Manual-drop inbox** — human-curated pointers to output the sweep can't fetch (X, paywalled, feed-less) | [`docs/reference/intake-inbox/`](docs/reference/intake-inbox/) |

The *schemas* for these artifacts (the Watchlist fields, the Learnings-Log entry front-matter with its
required `stance` and `touches`, the drop shape in the manual-drop inbox) are business-neutral mechanism
and live with the artifacts; only the locations are host-configurable and belong here.

## Tool Roster

The location of the [Tool Roster](docs/reference/tool-roster.yml) artifact the `restock` refresh skill
reads and writes, declared here so the generic Skill body names no path
([ADR 0023](docs/adr/0023-tool-roster-facts-tracker-sibling-to-intake.md), mirroring
[ADR 0012](docs/adr/0012-intake-pipeline-placement.md)). Ships as a **business-neutral placeholder**
pointing at the illustrative seed; a Host App repoints it during Customization.

| Artifact | Location |
|----------|----------|
| **Tool Roster** — the current-state harness/model snapshot | [`docs/reference/tool-roster.yml`](docs/reference/tool-roster.yml) |

The Tool Roster *schema* (the fields, the provenance typing, the inclusion test) is business-neutral
mechanism and lives with the artifact; only the location is host-configurable and belongs here.
