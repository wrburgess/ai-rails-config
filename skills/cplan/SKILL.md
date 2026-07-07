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
2. **Right-size the plan to the task.** Match the plan's altitude to how much is actually known. For a
   well-understood change, write the full ordered plan below. For an **exploratory/discovery issue** —
   where the outcome is genuinely uncertain and a full ordered plan would be written against unknowns —
   produce instead a **thin hypothesis + a spike/prototype step + an explicit re-plan checkpoint**: the
   smallest experiment that resolves the uncertainty, plus the named question it must answer before the
   real plan is written. That *is* the right-sized plan for a discovery task — *a plan to learn*, not a
   lighter gate: it is still posted and still approved. The AC **surfaces** the exploratory path and its
   rationale; the **HC elects it** — the AC never self-selects a compressed or exploratory workflow (see
   the [development lifecycle](../../docs/standards/development-lifecycle.md)).
3. **Break the work into discrete, ordered tasks** — each specific enough to implement without
   guessing, with the files it creates or modifies named. (For an exploratory plan, the ordered tasks
   are the spike itself; the production tasks are authored in the post-spike re-plan.)
4. **Define the testing strategy — decided now, not during implementation.** This is the load-bearing
   part of the plan. Following [`rules/testing.md`](../../rules/testing.md), decide:
   - Which test types the change needs (unit, integration, end-to-end, and whatever tiers the Host
     App's stack uses).
   - The specific scenarios each test covers — the happy path *and* the sad paths.
   - Edge cases: invalid input, duplicates, boundary values, concurrent operations.
   - Any shared fixtures/helpers/contexts to build (building test infrastructure is part of the work,
     not a reason to skip a test).
   - If the Host App enforces a coverage floor, how the change stays above it.

   **For an exploratory (spike-then-plan) issue,** this full strategy is decided in the **post-spike
   re-plan, before any production code** — the spike step itself names only what it must *learn*.
   "Decided now" means *when the plan for the production work is authored*; for discovery work that is
   after the spike. Test planning is deferred in detail, **never skipped**.
5. **Plan any data/schema change** — the migration or data-backfill steps, and their safety
   (reversibility, lock risk, multi-step rollout) per the host's migration rules.
6. **Determine the development environment** — a simple feature branch for single-focus work, or an
   isolated worktree when the work needs isolation (parallel agents, or a long-running change beside
   hotfixes). Branch naming follows [`PROJECT.md`](../../PROJECT.md) → *Branch & PR Policy*.
7. **Recommend an agent strategy** (the AC recommends; the HC decides) — a single agent for tightly
   coupled work; parallel agents (each owning an exclusive set of files) for large, independent
   subsystems if the host supports them; a background agent for a long-running check while the main
   agent continues.
8. **Check for risks** — schema/migration safety, authorization changes, breaking changes to existing
   behavior, search/index implications, deployment implications.
9. **Write the plan** in the structured format below.

</procedure>

<output>

Post the plan to the issue via the lifecycle host's issue-comment mechanism
([`PROJECT.md`](../../PROJECT.md) → *Lifecycle Host*), and also display it in the conversation for HC
review. Use this template:

```markdown
## Implementation Plan

### Development Environment
- Plan type: [full | exploratory: spike-then-plan]
- Environment: [simple branch | worktree]
- Branch: [name per PROJECT.md → Branch & PR Policy]
- Agent strategy: [single agent | parallel agents]
- Estimated scope: [X files, Y tests]

### Tasks
1. [Task] — [files affected]
2. [Task] — [files affected]

### Re-plan Checkpoint
- Exploratory plans only: what the spike must resolve before the production plan is authored (the named
  question, and how its answer feeds the re-plan). Omit for a full plan.

### Testing Strategy
Define EVERY test that will be written — by test type, the scenarios each covers, and the edge cases
(invalid input, duplicates, boundary values, concurrent operations). Note any shared fixtures/helpers
to build and how coverage stays above the host's floor. (For an exploratory plan, define these in the
post-spike re-plan; here, state only what the spike must *learn*.)

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

An approved plan is **revisable direction, not a frozen contract.** Discovering mid-`impl` that the
plan was wrong — an assumption broke, the spike taught something the plan didn't foresee — is an
**expected, valid outcome** that loops back to re-plan (re-run `cplan` → plan approval), not a
deviation or a failure. This **does not weaken the plan-approval gate**: the gate's job is a human
checkpoint against confidently building the wrong thing at scale, which a re-plan *serves* rather than
bypasses ([ADR 0017](../../docs/adr/0017-right-size-plan-revisable-direction.md)).

## Quality standard

Before posting, self-review: is every task specific enough to implement without guessing? Does the
testing strategy cover the full definition of done in [`rules/testing.md`](../../rules/testing.md) —
including edge and sad paths? Would a critical reviewer find a missing scenario or an unstated risk? If
the plan is exploratory, is the spike the *smallest* experiment that resolves the uncertainty, is the
re-plan checkpoint explicit, and did the HC elect this path (not the AC)?

</output>
