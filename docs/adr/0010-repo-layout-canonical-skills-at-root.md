# Repo layout: Project Config at root, canonical skills in a tool-neutral `skills/`

**Status:** accepted

The Generic Baseline layout is a direct consequence of ADRs 0001–0009. Two placement choices are worth recording because a contributor would otherwise question them:

- **Project Config is root `PROJECT.md`** (not `.ai/project.md` or `config/ai.md`). Chosen for maximum discoverability — agents find it instantly and `AGENTS.md` links to it.
- **Canonical Skill bodies live in a tool-neutral `skills/<name>/SKILL.md` at root, NOT under `.claude/skills/`.** Claude's `.claude/commands/<name>.md` slash-command files are thin Invocation Shims pointing to those canonical bodies. This deliberately forgoes Claude-native auto-discovery of `.claude/skills/` so the Canonical Source stays tool-neutral (ADR 0003) — the skill body must not live inside one tool's directory convention.

## Reference layout

```
AGENTS.md  CLAUDE.md  GEMINI.md  PROJECT.md  CONTEXT.md  README.md
.github/copilot-instructions.md  .github/workflows/parity.yml
.claude/{settings.json, commands/*.md, hooks/enforce-branch-creation.sh}
.githooks/  bin/{guard-protected-branch, install-git-hooks, setup, ai-config-sync}
skills/<name>/SKILL.md        # 8 canonical bodies
rules/*.md                    # Tier-1 Lean Core (generic starters)
docs/{adr/, rules/, standards/development-lifecycle.md}
scripts/parity_check.rb
```

## Consequences

- Adding a new tool = add one Adapter + one shim dir; the canonical bodies don't move.
- The existing Rails-app `.gitignore` in the repo must be replaced with a config-repo `.gitignore` (ignore tool `*.local` settings, not Rails build artifacts).
