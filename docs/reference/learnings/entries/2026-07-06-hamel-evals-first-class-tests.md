---
date: 2026-07-06
source:
  person: Hamel Husain
  link: https://hamel.dev/blog/posts/evals/
  medium: blog
claim: >
  An AI product's most common failure mode is the absence of task-specific evals; evals belong
  alongside the code as first-class, continuously-run tests.
stance: extends
touches: rules/testing.md
status: noted
---

## Compare / contrast

"Your AI Product Needs Evals" argues that the root cause of most failing LLM products is not the model
but the **lack of a robust evaluation system** — and that evals should be built and run as a
first-class part of the development loop, not bolted on later.

This **extends** [`rules/testing.md`](../../../../rules/testing.md). That rule today covers
conventional testing (factories over fixtures, behavior-level assertions) but says nothing about
**evaluating LLM-driven behavior**, where the "assertion" is a graded rubric or an LLM-as-judge check
rather than a deterministic equality. A Host App shipping an AI feature would find a gap between the
rule's current scope and this practice.

## Disposition

`noted` — a candidate extension, not yet actioned. If a Host App adopting this bundle builds
LLM-powered features, `rules/testing.md` (and its deferred deep doc
`docs/rules/testing-postmortems.md`) should gain an **evals** section: when a task-specific eval is
required, how it runs in CI, and its relationship to the coverage floor. Left `noted` here because the
Generic Baseline itself ships no LLM-feature code to evaluate — the trigger is a host adopting one. A
sweep that finds a host doing so should raise this to `actioned` with a tracking issue.
