@AGENTS.md

# Claude-only notes

The line above imports the [Canonical Source](AGENTS.md) — every instruction Claude follows lives in
`AGENTS.md`, expanded into this file at launch. **Do not duplicate `AGENTS.md` content here.** This
file holds only Claude-specific configuration notes that have no place in the tool-neutral canonical.

- **Invocation Shims** — Claude reaches each Skill through a thin `.claude/commands/<name>.md`
  slash-command file that points at the canonical body in `skills/<name>/SKILL.md`
  ([ADR 0010](docs/adr/0010-repo-layout-canonical-skills-at-root.md)). The first is
  [`.claude/commands/distill.md`](.claude/commands/distill.md) → `/distill`
  (canonical body: `skills/distill/SKILL.md`). The six lifecycle shims — `/assess`, `/devise`,
  `/invoke`, `/verify`, `/listen`, `/final` — ship alongside it, the orchestrator shim
  [`.claude/commands/ship.md`](.claude/commands/ship.md) → `/ship` (canonical body:
  `skills/ship/SKILL.md`), the intake-pipeline sweep shim
  [`.claude/commands/scout.md`](.claude/commands/scout.md) → `/scout` (canonical body:
  `skills/scout/SKILL.md`), the intake front-door shim
  [`.claude/commands/clip.md`](.claude/commands/clip.md) → `/clip` (canonical body:
  `skills/clip/SKILL.md`), the authoring front-door shim
  [`.claude/commands/create-skill.md`](.claude/commands/create-skill.md) → `/create-skill` (canonical
  body: `skills/create-skill/SKILL.md`), and the roster front-door shim
  [`.claude/commands/follow.md`](.claude/commands/follow.md) → `/follow` (canonical body:
  `skills/follow/SKILL.md`), and the Pegboard refresh shim
  [`.claude/commands/restock.md`](.claude/commands/restock.md) → `/restock` (canonical body:
  `skills/restock/SKILL.md`) complete the set of thirteen.
- **Settings & hooks** — `.claude/settings.json` wires the branch-protection fast-fail
  ([`.claude/hooks/enforce-branch-creation.sh`](.claude/hooks/enforce-branch-creation.sh)) as a
  PreToolUse hook — Layer 3 over the portable git hooks in `.githooks/`
  ([ADR 0009](docs/adr/0009-defense-in-depth-branch-protection-all-agents.md); see
  [`docs/guides/branch-protection.md`](docs/guides/branch-protection.md)). Activate the git hooks on a
  fresh clone with `bin/setup`.
- **Sub-agent offload** — where a Skill defines an optional sub-agent execution enhancement (e.g.
  `ship`'s phase delegation), Claude uses its native `Task` tool; tools without that mechanism run
  the same procedure inline. The quality bar never changes; only the mechanism degrades
  ([ADR 0003](docs/adr/0003-skills-canonical-body-thin-shims-graceful-degradation.md)).
