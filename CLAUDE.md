@AGENTS.md

# Claude-only notes

The line above imports the [Canonical Source](AGENTS.md) — every instruction Claude follows lives in
`AGENTS.md`, expanded into this file at launch. **Do not duplicate `AGENTS.md` content here.** This
file holds only Claude-specific configuration notes that have no place in the tool-neutral canonical.

- **Invocation Shims** — Claude reaches each Skill through a thin `.claude/commands/<name>.md`
  slash-command file that points at the canonical body in `skills/<name>/SKILL.md`
  ([ADR 0010](docs/adr/0010-repo-layout-canonical-skills-at-root.md)). These shim files are added in
  later baseline issues.
- **Settings & hooks** — `.claude/settings.json` and `.claude/hooks/` (branch-protection fast-fail,
  etc.) are added in later baseline issues.
- **Sub-agent offload** — where a Skill defines an optional sub-agent execution enhancement (e.g.
  `ship`'s phase delegation), Claude uses its native `Task` tool; tools without that mechanism run
  the same procedure inline. The quality bar never changes; only the mechanism degrades
  ([ADR 0003](docs/adr/0003-skills-canonical-body-thin-shims-graceful-degradation.md)).
