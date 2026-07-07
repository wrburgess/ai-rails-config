# Learnings Log — index

Chronological (most recent first) index of intake findings. Each row links an entry under
[`entries/`](entries/); the schema and the one hard rule (a `stance`-less entry is invalid) live in
[`README.md`](README.md).

> **ILLUSTRATIVE REFERENCE — not part of the [Generic Baseline](../../../CONTEXT.md) guarantee.** The
> entries below are worked examples seeding the shape (issue #30); a Host App replaces or extends
> them. Placement: [ADR 0012](../../adr/0012-intake-pipeline-placement.md).

**Last swept:** 2026-07-07 _(first `scout` sweep — window 2026-06-23 → 2026-07-07; 13 entries
proposed across 8 sources. The marker advances only inside a merged `scout` sweep PR; an empty sweep
leaves it untouched. Scheduling the sweep is covered in the
[intake-sweep scheduling guide](../../guides/intake-sweep-scheduling.md).)_

| Date | Source | Claim | Stance | Touches | Status |
|------|--------|-------|--------|---------|--------|
| [2026-07-07](entries/2026-07-07-pocock-kill-context-bloat.md) | Matt Pocock | Measure unused tools via a logging proxy, then disable them to cut context bloat | extends | `ADR-0004` | noted |
| [2026-07-07](entries/2026-07-07-pocock-grill-with-docs.md) | Matt Pocock | An AI interview capturing vocabulary as a glossary and hard-to-reverse choices as ADRs before code | confirms | `skills/grill-with-docs` | noted |
| [2026-07-07](entries/2026-07-07-pocock-skills-as-markdown-catalog.md) | Matt Pocock | Skills as focused markdown files (instructions + inputs + outputs) mapped to engineering moments | confirms | `rules/skills.md` | noted |
| [2026-07-07](entries/2026-07-07-willison-ai-review-caught-bugs.md) | Simon Willison | An AI-run code review caught critical bugs before a release shipped | confirms | `skills/verify` | noted |
| [2026-07-07](entries/2026-07-07-willison-better-models-worse-tools.md) | Simon Willison | Newer models are worse at custom third-party tools — tool-specific mechanisms are fragile across versions | confirms | `ADR-0003` | noted |
| [2026-07-07](entries/2026-07-07-thorsten-ball-agents-in-orbs.md) | Thorsten Ball | Ephemeral sandboxed agents reframed as async functions you queue and run in parallel | extends | `skills/ship` | noted |
| [2026-07-07](entries/2026-07-07-lilian-weng-harness-engineering.md) | Lilian Weng | The harness (orchestration layer around a model) is as important as raw model intelligence | confirms | `skills/ship` | noted |
| [2026-07-07](entries/2026-07-07-willison-fable-judgement-delegation.md) | Simon Willison | Delegate routine implementation to cheaper subagents; keep judgment in the premium main loop | confirms | `skills/ship` | noted |
| [2026-07-07](entries/2026-07-07-willison-dspy-agent-prompt-evals.md) | Simon Willison | Use DSPy with auto-generated gold datasets to evaluate and optimize agent system prompts | extends | `rules/testing.md` | noted |
| [2026-07-07](entries/2026-07-07-latent-space-against-one-shot-design.md) | Paul Bakaus (Latent Space) | Reject one-shot design; the agent does ~80%, the human applies taste for the final 20% | confirms | `rules/self-review.md` | noted |
| [2026-07-07](entries/2026-07-07-hamel-hard-to-eval-product-smell.md) | Hamel Husain | Hard-to-eval output is a product-design smell — redesign for verifiability | extends | `rules/testing.md` | noted |
| [2026-07-07](entries/2026-07-07-jason-liu-scheduled-work-kinds.md) | Jason Liu | Scheduled Tasks (fresh context each run) vs Scheduled Messages (persistent thread) | extends | `skills/scout` | noted |
| [2026-07-07](entries/2026-07-07-andrew-ng-loop-engineering.md) | Andrew Ng | "Loop engineering": three nested feedback loops with humans owning the higher-level ones | confirms | `docs/standards/development-lifecycle.md` | noted |
| [2026-07-06](entries/2026-07-06-building-effective-agents-simplicity.md) | Erik Schluntz & Barry Zhang (Anthropic) | Prefer simple, composable patterns; add agentic complexity only when it measurably helps | confirms | `ADR-0003` | noted |
| [2026-07-06](entries/2026-07-06-hamel-evals-first-class-tests.md) | Hamel Husain | An AI product needs task-specific evals as first-class tests | extends | `rules/testing.md` | actioned |
