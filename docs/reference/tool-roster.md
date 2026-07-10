# Tool Roster

> **Generated file — do not edit by hand.** Rendered from [`tool-roster.yml`](tool-roster.yml)
> by `scripts/render_tool_roster.rb`, which the [`restock`](../../skills/restock/SKILL.md) skill
> runs on every refresh. Edit the YAML, not this. Illustrative reference, not the Generic Baseline
> ([ADR 0023](../adr/0023-tool-roster-facts-tracker-sibling-to-intake.md)).

## Harnesses

| Harness | Vendor | Version (date) | House model | Config surface | Status |
|---|---|---|---|---|---|
| Claude Code | Anthropic | 2.1.206 (2026-07-10) | Claude Opus | hooks · skill-shims · mcp · subagents | active |
| Codex CLI | OpenAI | 0.144.1 (2026-07-09) | GPT Sol | mcp · plugins · agents-md | active |
| Antigravity CLI | Google | 1.1.1 (2026-07-10) | Gemini Pro | mcp · agents-md | active |
| Cursor | Anysphere | 3.11 (2026-07-10) | *varies* (picker) | mcp | active |

## Models

| Model | Vendor | Version (date) | Effort tiers | $/Mtok (in·out) | SWE-bench Verified | Maturity | Status |
|---|---|---|---|---|---|---|---|
| Claude Fable | Anthropic | 5 (2026-06-09) | low · medium · high · xhigh · max | 10 · 50 | 95.0 (2026-07-08) | GA | active |
| Claude Opus | Anthropic | 4.8 | low · medium · high · xhigh · max | 5 · 25 | 88.6 (2026-07-08) | GA | active |
| Claude Sonnet | Anthropic | 5 | low · medium · high · xhigh · max | 2 · 10 | — | GA | active |
| Claude Haiku | Anthropic | 4.5 (2025-10-01) | — | 1 · 5 | — | GA | active |
| GPT Sol | OpenAI | 5.6 (2026-07-09) | low · medium · high | 5 · 30 | — | GA | active |
| GPT Terra | OpenAI | 5.6 (2026-07-09) | — | 2.5 · 15 | — | GA | active |
| GPT Luna | OpenAI | 5.6 (2026-07-09) | — | 1 · 6 | — | GA | active |
| Gemini Pro | Google | 3.1 | — | 2 · 12 | — | **Preview** | active |
| Gemini Flash | Google | 3.5 (2026-05-19) | — | 1.5 · 9 | — | GA | active |

<sub>— = not tracked / not yet sourced (ages honestly; `restock` fills). Prices are per-vendor list rates; see each entry's `sources:` in [`tool-roster.yml`](tool-roster.yml) for provenance and any tier / introductory-price notes.</sub>

