# PROJECT.md — Project Config

The **Project Config**: the one place a Host App declares its host-specific values so the Skills and
[Canonical Source](AGENTS.md) stay generic. A vendoring Host App edits the values in this file; it
does not edit `AGENTS.md` to change them. This file ships with **business-neutral placeholders** —
replace them during Customization.

> Section headings below are a contract: the parity check (`scripts/parity_check.rb`) asserts each of
> the five `##` sections is present. Rename them and the check fails.

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

| Agent | Declared model | Identity email |
|-------|----------------|----------------|
| Claude Code | `Claude Opus 4.8` | `noreply@anthropic.com` |
| Codex | `Codex (host sets model)` | `<host sets>` |
| Copilot | `Copilot (model varies)` | `<host sets>` |
| Gemini | `Gemini (host sets model)` | `<host sets>` |

- **Commit trailer:** `Co-Authored-By: <Tool Model> <email>` — e.g.
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **PR / review / comment footer:** `— <Tool> (<Model>)` — e.g. `— Claude Code (Opus 4.8)`.
- Attribution shows **per-agent identity** so provenance reflects which agent did the work. Copilot's
  backing model is variable/unknown, so its declaration reads `Copilot (model varies)`.

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

## Tooling Pegboard

The location of the [Tooling Pegboard](docs/reference/pegboard.yml) artifact the `restock` refresh skill
reads and writes, declared here so the generic Skill body names no path
([ADR 0022](docs/adr/0022-pegboard-facts-tracker-sibling-to-intake.md), mirroring
[ADR 0012](docs/adr/0012-intake-pipeline-placement.md)). Ships as a **business-neutral placeholder**
pointing at the illustrative seed; a Host App repoints it during Customization.

| Artifact | Location |
|----------|----------|
| **Pegboard** — the current-state harness/model snapshot | [`docs/reference/pegboard.yml`](docs/reference/pegboard.yml) |

The Pegboard *schema* (the fields, the provenance typing, the inclusion test) is business-neutral
mechanism and lives with the artifact; only the location is host-configurable and belongs here.
