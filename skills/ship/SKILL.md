---
name: ship
description: The hands-off orchestrator. Sequences the six lifecycle skills (assess → cplan → impl → verify → rtr → final) end to end while keeping a lean orchestrator context — delegating output-heavy work to discardable sub-agents and protecting the two mandatory human gates. Use to run the whole development lifecycle for one issue in a single driven flow.
---

<what-to-do>

Run the full [development lifecycle](../../docs/standards/development-lifecycle.md) for the tracked
issue named in the invocation, from Assess through Deliver, by **sequencing the six lifecycle
skills** — [`assess`](../../skills/assess/SKILL.md) → [`cplan`](../../skills/cplan/SKILL.md) →
[`impl`](../../skills/impl/SKILL.md) → [`verify`](../../skills/verify/SKILL.md) →
[`rtr`](../../skills/rtr/SKILL.md) → [`final`](../../skills/final/SKILL.md). `ship` **adds no phase
procedure of its own**: each phase's steps, gates, and terminal artifact remain defined once in that
phase's canonical body, which `ship` reads and follows in order. What `ship` owns is the *sequencing*
— the delegation policy, the session boundaries, the two human gates, the emergency stops, and the
faithfulness backstop.

Read host-specific values — the lifecycle host and its artifact map, the branch/PR policy, the
quality-check commands, the review severities, the attribution/model — from
[`PROJECT.md`](../../PROJECT.md). Never hardcode them here.

**Design goal: a lean main-thread context** ([ADR 0005](../../docs/adr/0005-ship-hybrid-delegation-offload-retrieval-protect-judgment.md)).
`ship` reaches it by delegating **output-heavy, signal-light** work to sub-agents whose context is
discarded, and **keeping judgment-heavy** work in a clean orchestrator — *not* by delegating every
phase uniformly. The cure for context degradation is to keep the *thinking* in a clean window and
offload the *reading*. A dry run should complete without a mid-run compaction.

</what-to-do>

<delegation-policy>

Delegate by **output-weight**, not per phase. Each delegated phase returns a compact **handoff
contract** and its sub-agent context is discarded; each kept phase runs in the clean orchestrator so
the decisions that matter are made on context the orchestrator actually saw.

| Phase | Disposition | What the orchestrator keeps | Handoff contract |
|-------|-------------|------------------------------|------------------|
| `assess` exploration | **Delegate** | Assessment synthesis, option framing, the recommendation | `exploration-summary` ([`assess`](../../skills/assess/SKILL.md)) |
| `cplan` | **Keep** | Plan authoring + reconciliation against the codebase | — (judgment-heavy; no offload) |
| `impl` code + check + fix loop | **Delegate** | Branch setup, commit, push, open PR, issue linking | `check-result` ([`impl`](../../skills/impl/SKILL.md)) |
| `verify` full-diff review | **Delegate** | Reading the report, classifying by severity, posting the self-review | `drift-report` ([`verify`](../../skills/verify/SKILL.md)) |
| `rtr` fetch-and-fix churn | **Delegate** | Severity classification, the stop-and-ask call, the HC summary | `review-response` (defined below) |
| `final` merge-readiness | **Keep** | The green-gate + no-open-must-fix judgment; the SOW | — (judgment-heavy; no offload) |

**Keep in the orchestrator (never delegate):** assessment synthesis, plan authoring/reconciliation,
`rtr` severity + stop-and-ask, and the `final` merge-readiness call. These are the decisions a lossy
summary would corrupt.

### review-response (sub-agent → orchestrator)

The three delegated phases above consume contracts already defined in their own bodies
(`exploration-summary`, `check-result`, `drift-report`). The `rtr` fetch-and-fix churn is offloaded
the same way but its contract is defined here, so every delegated phase has one:

```
{ threads: [ { id, surface: "issue_comment"|"inline_thread"|"review_body",
               author, severity, summary, quoted_excerpt } ],
  severity_tally: { critical, high, medium, low, discussion },
  proposed_resolutions: [ { thread_id, action: "fix"|"explain"|"defer", detail } ],
  quality_checks: [ { purpose, status: "pass"|"fail"|"not_run" } ],   # one row per PROJECT.md → Quality Checks
  verdict: "clean" | "needs_human_call" }
```

`severity` uses [`PROJECT.md`](../../PROJECT.md) → *Review Severity Framework* plus a `discussion`
bucket for non-defect questions. `verdict` is `needs_human_call` whenever any thread is architectural,
ambiguous, or Critical — the sub-agent proposes, but the **orchestrator** owns the severity call and
the stop-and-ask (it never auto-applies fixes past that line). The sub-agent gathers and drafts; it
never posts to the lifecycle host — the orchestrator owns that I/O and the attribution.

*Graceful degradation ([ADR 0003](../../docs/adr/0003-skills-canonical-body-thin-shims-graceful-degradation.md),
[ADR 0005](../../docs/adr/0005-ship-hybrid-delegation-offload-retrieval-protect-judgment.md)):* on a
tool without sub-agent fan-out, run every phase **inline** and **compact between phases**. The
mechanism degrades; the phase procedures, the handoff contracts, and the quality bar do not.

</delegation-policy>

<procedure>

Run the phases in order, following each phase's canonical body for its steps and terminal artifact.
`ship` layers the sequencing controls below on top.

1. **Assess** — follow [`assess`](../../skills/assess/SKILL.md), delegating the codebase exploration
   and folding the returned `exploration-summary` into the assessment you synthesize. Post the
   assessment to the issue.
2. **Plan** — follow [`cplan`](../../skills/cplan/SKILL.md) **in the orchestrator** (no offload). Post
   the plan to the issue. **→ Human gate 1 (plan approval).**
3. **Implement** — follow [`impl`](../../skills/impl/SKILL.md): the orchestrator owns branch setup and
   all lifecycle-host I/O; the code + check + fix loop is delegated, returning a `check-result`.
   Reconcile git state, gate on `verdict`, then commit → push → open the PR.
4. **Verify** — follow [`verify`](../../skills/verify/SKILL.md): delegate the full-diff review, consume
   the `drift-report`, classify findings by severity, post the self-review on the PR.
5. **Review response** — follow [`rtr`](../../skills/rtr/SKILL.md): delegate the fetch-and-fix churn
   (`review-response` contract), but make the severity and stop-and-ask calls in the orchestrator and
   summarize for the HC before any change is applied.
6. **Deliver** — follow [`final`](../../skills/final/SKILL.md) **in the orchestrator**: re-verify the
   PR is green with no open must-fix findings, post the Statement of Work, link it from the issue.
   **→ Human gate 2 (merge).**

## The two human gates (never bypassed)

`ship` replaces every per-stage "wait for the HC" pause with exactly **two** mandatory human gates,
per the [development lifecycle](../../docs/standards/development-lifecycle.md):

1. **Plan approval** — after `cplan` (and any Reviewer plan review), before any code. `ship` does not
   write code without an approved plan.
2. **Merge** — after `final` posts the SOW with a green gate and no open must-fix findings. **`ship`
   never merges** — merge is the HC's.

## Emergency stops (unconditional)

Beyond the two gates, `ship` **stops and asks the HC** the moment any of these appears — it never
works around them:

- A quality check fails and the fix is not obvious / cannot be auto-resolved.
- A discovery that the change touches core logic the plan did not anticipate.
- A review comment that is architectural, ambiguous, or open to more than one interpretation.
- Any handoff contract returns a `needs_human_call` / `failing` verdict the orchestrator cannot
  resolve from context.

## Gates as session boundaries

To keep the orchestrator lean through the delegated heavy ops, treat the gates as **session
boundaries** and **externalize state** to the issue / PR / git rather than carrying it in context:

- Run **assess + plan in one clean session**; the plan gate is a natural boundary.
- Run **build (`impl` → `final`) in a fresh session** so the orchestrator starts lean before the
  delegated code/verify/review churn.
- A **pre-`final` context check** offers another reset before the merge-readiness judgment.
- On resume, a fresh phase **re-reads its durable artifacts** (the issue, the plan comment, the PR)
  rather than trusting a compaction summary — a stage is not done until its terminal artifact exists
  (see the [development lifecycle](../../docs/standards/development-lifecycle.md)).

## Faithfulness backstop

The plan gate and the PR each get an **independent second-model review** (the Reviewer named in
[`PROJECT.md`](../../PROJECT.md) → *Lifecycle Host* / the lifecycle's Reviewer role) so a delegated
summary the orchestrator never saw cannot silently steer the outcome. If **no second model is
reachable**, the backstop **degrades to "stop and ask the HC"** — it is never silently dropped.

</procedure>

<quality-gate>

`ship` changes **no quality bar** — every phase's gate runs at full strength, in order:
`assess`'s option rigor, `cplan`'s testing strategy, `impl`'s green *Quality Checks* +
[`rules/self-review.md`](../../rules/self-review.md), `verify`'s drift/test-quality review, `rtr`'s
severity discipline, and `final`'s merge-readiness. A weaker tool degrades the delegation *mechanism*
(inline + compact between phases), never a gate.

Before declaring a `ship` run complete: both human gates were honored; no emergency stop is
outstanding; every delegated phase returned and was reconciled against its handoff contract; the
terminal artifact of each phase exists (assessment, plan, PR, self-review, review replies, SOW). Sign
every lifecycle-host comment with the attribution footer from [`PROJECT.md`](../../PROJECT.md) →
*Attribution & Model Declaration*, using your runtime-actual model.

**Terminal artifact:** a delivered PR carrying the SOW, with the two human gates intact and the issue
linked — ready for the HC to merge.

</quality-gate>
