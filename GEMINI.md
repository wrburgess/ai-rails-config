@AGENTS.md

# Gemini-only notes

The line above imports the [Canonical Source](AGENTS.md) via Gemini's `@file` memory import — every
instruction Gemini follows lives in `AGENTS.md`. **Do not duplicate `AGENTS.md` content here.**

- A Host App may instead point Gemini directly at the canonical file by setting `context.fileName` to
  `AGENTS.md`, rather than importing through this file
  ([ADR 0002](docs/adr/0002-agents-md-canonical-pointer-projection.md)). Either path resolves to the
  same Canonical Source.
- Gemini is present but minimal in the baseline (not yet a daily driver); keep this Adapter thin.
- Google's terminal surface is now **Antigravity CLI** (consumer Gemini CLI retired 2026-06-18); it
  continues to read `GEMINI.md`/`AGENTS.md` and honor `@`-imports, so the `@AGENTS.md` line above is
  unchanged — see [`docs/research/tool-config-discovery.md`](docs/research/tool-config-discovery.md).
