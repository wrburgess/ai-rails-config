---
name: cplan
description: Stage 2 of the development lifecycle. Turn the HC's chosen option from the assessment into a concrete, ordered implementation plan with a testing strategy decided up front. Use after the HC picks an option and before writing any code.
---

<what-to-do>

Create an implementation plan for the tracked issue named in the invocation, based on the option the
HC chose from the [assessment](../../skills/assess/SKILL.md). This is **Stage 2 (Plan)** of the
[development lifecycle](../../docs/standards/development-lifecycle.md).

Read host-specific values — the lifecycle host and artifact map, the branch/PR policy, the
quality-check commands, the attribution/model — from [`PROJECT.md`](../../PROJECT.md). Never hardcode
them here.

</what-to-do>

<procedure>

1. **Read the issue and its comments** — the assessment and the HC's chosen option (and any answers to
   the assessment's open questions).
2. **Break the work into discrete, ordered tasks** — each specific enough to implement without
   guessing, with the files it creates or modifies named.
3. **Define the testing strategy — decided now, not during implementation.** This is the load-bearing
   part of the plan. Following [`rules/testing.md`](../../rules/testing.md), decide:
   - Which test types the change needs (unit, integration, end-to-end, and whatever tiers the Host
     App's stack uses).
   - The specific scenarios each test covers — the happy path *and* the sad paths.
   - Edge cases: invalid input, duplicates, boundary values, concurrent operations.
   - Any shared fixtures/helpers/contexts to build (building test infrastructure is part of the work,
     not a reason to skip a test).
   - If the Host App enforces a coverage floor, how the change stays above it.
4. **Plan any data/schema change** — the migration or data-backfill steps, and their safety
   (reversibility, lock risk, multi-step rollout) per the host's migration rules.
5. **Determine the development environment** — a simple feature branch for single-focus work, or an
   isolated worktree when the work needs isolation (parallel agents, or a long-running change beside
   hotfixes). Branch naming follows [`PROJECT.md`](../../PROJECT.md) → *Branch & PR Policy*.
6. **Recommend an agent strategy** (the AC recommends; the HC decides) — a single agent for tightly
   coupled work; parallel agents (each owning an exclusive set of files) for large, independent
   subsystems if the host supports them; a background agent for a long-running check while the main
   agent continues.
7. **Check for risks** — schema/migration safety, authorization changes, breaking changes to existing
   behavior, search/index implications, deployment implications.
8. **Write the plan** in the structured format below.

</procedure>

<output>

Post the plan to the issue via the lifecycle host's issue-comment mechanism
([`PROJECT.md`](../../PROJECT.md) → *Lifecycle Host*), and also display it in the conversation for HC
review. Use this template:

```markdown
## Implementation Plan

### Development Environment
- Environment: [simple branch | worktree]
- Branch: [name per PROJECT.md → Branch & PR Policy]
- Agent strategy: [single agent | parallel agents]
- Estimated scope: [X files, Y tests]

### Tasks
1. [Task] — [files affected]
2. [Task] — [files affected]

### Testing Strategy
Define EVERY test that will be written — by test type, the scenarios each covers, and the edge cases
(invalid input, duplicates, boundary values, concurrent operations). Note any shared fixtures/helpers
to build and how coverage stays above the host's floor.

### Data / Schema Considerations
- [Migration/backfill steps and their safety — or "None"]

### Risks & Considerations
- [Migration, authorization, search/index, or breaking-change concerns]

### Next Step
HC: send this plan to the Reviewer, then approve to proceed with the implement skill (`impl`) for the
same issue.
```

Sign with the attribution footer from [`PROJECT.md`](../../PROJECT.md) → *Attribution & Model
Declaration*, using your runtime-actual model.

**Terminal artifact:** the plan posted on the issue. **This is the first mandatory human gate (plan
approval)** — the AC does not write code without an approved plan.

## Quality standard

Before posting, self-review: is every task specific enough to implement without guessing? Does the
testing strategy cover the full definition of done in [`rules/testing.md`](../../rules/testing.md) —
including edge and sad paths? Would a critical reviewer find a missing scenario or an unstated risk?

</output>
