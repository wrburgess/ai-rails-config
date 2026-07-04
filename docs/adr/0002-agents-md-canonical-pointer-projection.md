# `AGENTS.md` is the Canonical Source; per-tool files are thin pointers

**Status:** accepted

The full, model-neutral instruction content lives in **one** file — `AGENTS.md` (the emerging cross-tool standard). Each other tool's native config surface is a **thin Adapter** that includes or points to it, rather than a full copy:

- `CLAUDE.md` — imports `AGENTS.md` (`@AGENTS.md`) plus Claude-only `.claude/` notes
- `.github/copilot-instructions.md` — short pointer + any Copilot-specific review notes
- `GEMINI.md` — short pointer

We reject the generator/render model (inline the full content into all four files via a build step) as the *default* because it multiplies the number of places content lives and pays generator complexity for all four tools up front. The pointer model keeps content in one place, so a Host App customizes `AGENTS.md` once and every tool inherits.

## Motivating context — tool role tiers

The tools are not co-equal daily drivers, which makes the pointer model low-risk:

- **Claude** — primary developer (full `.claude/` config; unquestionably follows its own config)
- **Codex** — primary reviewer (reads `AGENTS.md` natively)
- **Copilot** — chimes in with PR comments (reads `.github/copilot-instructions.md`; its backing model is not something we control or assume)
- **Gemini** — not yet in use, under consideration (keep its Adapter present but minimal)

The two heaviest users already look exactly where the Canonical Source lives.

## Consequences

- **Hybrid fallback:** if per-tool verification (see the parity phase) shows a tool won't reliably *follow* a pointer, we render *that one tool's* file with inlined content — pointer where it works, render where it doesn't. Generator complexity stays proportional to the actual problem.
- A CI parity check must confirm each Adapter still resolves to the Canonical Source (guards against a pointer going stale).
- Attribution and instructions must not assume any tool's backing model (Copilot's especially is unknown/variable).
