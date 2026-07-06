# ai-rails-config

A generic, model-agnostic **AI-agent configuration layer** for Rails projects. It ships as a
portable, business-neutral **Generic Baseline** — one **Canonical Source** of instructions that
drives four AI coding agents (Claude, Codex, Copilot, Gemini) in lockstep — which you **vendor into a
Host App** and then customize.

For the precise vocabulary used throughout (Config Bundle, Generic Baseline, Adapter, Skill, Rules
Layer, Project Config, Customization…), see [`CONTEXT.md`](CONTEXT.md). The full instruction set is
[`AGENTS.md`](AGENTS.md) — the one file every agent resolves to.

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
  **Tier-1 Lean Core** (`rules/*.md` — `backend`, `frontend`, `testing`, `security`, `self-review`,
  `scripting`, each with Patterns + Anti-Patterns) plus the deferred **Tier-2 Deep Docs**
  (`docs/rules/`, read on demand via the trigger table). Business-neutral starters; extend per host.
- **Skills** — model-agnostic capabilities authored once as a canonical body (`skills/<name>/SKILL.md`)
  and reached through a thin per-tool Invocation Shim (Claude `.claude/commands/<name>.md`; other tools
  via native `AGENTS.md` discovery), so any configured agent runs the same procedure
  ([ADR 0003](docs/adr/0003-skills-canonical-body-thin-shims-graceful-degradation.md)). Shipped (7 of
  8): `grill-with-docs` and the six lifecycle skills `assess`, `cplan`, `impl`, `verify`, `rtr`,
  `final` (their five-stage spec is `docs/standards/development-lifecycle.md`); the `ship` orchestrator
  lands in a later issue.

## Vendor it into a Host App

The bundle is distributed by **copying files in** — no submodule, no gem, no upstream tracking
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
Rails `.gitignore`.

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

This repo's own check is dependency-free (standard-library Ruby, no bundler):

```bash
ruby scripts/parity_check.rb
```

It verifies every Adapter still resolves to [`AGENTS.md`](AGENTS.md), that the `PROJECT.md` contract
sections are intact, and that all documented links resolve.
