---
date: 2026-07-07
source:
  person: Matt Pocock
  link: https://x.com/mattpocockuk
  medium: post
claim: >
  The discipline behind writing a good Skill — structure, leading words, and pruning — is useful for
  any text an agent reads: AGENTS.md, docs for agents, specs and tickets, and AFK workflow prompts.
stance: extends
touches: rules/skills.md
status: noted
---

## Compare / contrast

In a 2026-07-07 X post, Matt Pocock (author of the `mattpocock/skills` collection, tracked on the
[Watchlist](../../voices.yml)) reports using his `/writing-great-skills` skill "for a lot more than
writing skills" — naming **AGENTS.md**, **docs for agents**, **specs and tickets**, and **AFK
workflow prompts**. His conclusion: *"structure + leading words + pruning is useful for any text
agents read."*

This **extends** [`rules/skills.md`](../../../../rules/skills.md). That rule today governs how a Skill
body is *sourced and wired* — single canonical body, thin shims, host values read from `PROJECT.md`,
no restated procedure. Those are DRY/portability invariants. What it does **not** cover is the
*prose craft* of an agent-read artifact: how to **structure** it, how to **lead each instruction with
an imperative word**, and how to **prune** it so an agent isn't reading noise. This repo already
practices that craft implicitly — the `scout` and lifecycle SKILL bodies open with `<what-to-do>`,
run numbered steps whose every item leads with a bold verb (*Resolve, Read, Load, Find, Draft,
Apply, Append, Surface, Open*), and stay lean — but it is never named as a rule.

The sharper half of the learning is Pocock's **generalization**: the same discipline pays off across
*every* agent-read artifact this Config Bundle ships, not just `skills/`. `AGENTS.md`, `PROJECT.md`,
the `rules/*.md` files, the ADRs, and the Learnings Log itself are all "text agents read," and all
would benefit from the same structure/leading-words/pruning pass. That reframes the authoring
discipline from a skills-only concern into a cross-cutting one.

## Proposed delta (for the human to dispose)

Add to [`rules/skills.md`](../../../../rules/skills.md) — or a sibling authoring rule if a host
prefers to scope it wider — a **Pattern** capturing the prose-craft discipline:

> **Write for an agent reader: structure, leading words, prune.** Give an agent-read artifact a clear
> skeleton, open each instruction with the imperative that names the action, and cut anything that
> doesn't change what the agent does. This applies to *any* text an agent reads — skill bodies,
> `AGENTS.md`, docs, specs, tickets, and workflow prompts — not just `skills/`.

…and a matching **Anti-Pattern** (e.g. *never pad an agent-read artifact with restated context,
hedging, or narration that doesn't alter the agent's next action — pruning is a feature, not a
loss*). Both would ship as business-neutral `extend-per-host` starters, consistent with the rest of
the Lean Core. Left as `noted` for a human to accept, reframe, or reject.

## Staleness note

The exact tweet permalink was not resolvable at sweep time (web search surfaced a different, later
Pocock post rather than this one), so `source.link` points at the author's verified X handle rather
than a fabricated status URL — per the log's "never invent a URL" rule. The claim itself is
corroborated by the public `/writing-great-skills` skill in
[`github.com/mattpocock/skills`](https://github.com/mattpocock/skills).
