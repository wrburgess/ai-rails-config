---
name: verify
description: Stage 4 of the development lifecycle. Self-review an existing PR against its approved plan for drift, test quality, cleanliness, and description completeness before the Reviewer sees it. Use on the PR that invoke opened. It operates on the existing PR and never creates one.
---

<what-to-do>

Self-review the existing PR named in the invocation against its approved implementation plan, so that
when the Reviewer sees it they find nothing. This is **Stage 4 (Verify)** of the
[development lifecycle](../../docs/standards/development-lifecycle.md).

Read host-specific values — the review severities from [`PROJECT.md`](../../PROJECT.md) → *Review
Severity Framework*, the quality-check commands from *Quality Checks*, the lifecycle host from
*Lifecycle Host*, the attribution/model from *Attribution & Model Declaration*. Never hardcode them.

**This stage operates on the PR `invoke` already opened — it never opens one.** If there is no PR, a
prior stage's terminal artifact was skipped: stop and recheck, don't reinterpret the lifecycle.

</what-to-do>

<how-to-run>

To keep the orchestrator's context lean, `verify` may be **offloaded to a read-only sub-agent** that
reads the whole PR diff and the plan in its discarded context and returns a compact **drift-report**;
the orchestrator supplies only pointers (the PR id, the linked issue id, and — when available —
`invoke`'s returned check-result so the checks aren't re-run) and consumes the report.

*Graceful degradation ([ADR 0003](../../docs/adr/0003-skills-canonical-body-thin-shims-graceful-degradation.md),
[ADR 0005](../../docs/adr/0005-ship-hybrid-delegation-offload-retrieval-protect-judgment.md)):* on a
tool without sub-agents, run Steps 1–6 **inline**. The sub-agent (or you, inline) never posts to the
lifecycle host — the orchestrator owns that I/O and the attribution.

### drift-report (sub-agent → orchestrator)
```
{ plan_alignment:   { all_implemented: bool, missing_items: [str], scope_creep_files: [str] },
  test_quality:     { meaningful: bool, false_greens: [str], gaps: [str] },
  test_coverage_summary: { by_type: str, edge_cases: str },
  quality_checks:   [ { purpose, status: "pass"|"fail"|"not_run" } ],
  quality_checks_source: "invoke_check_result" | "ran_here",
  cleanliness:      { debug_code: [str], commented_code: [str], todos: [str] },
  pr_description:   { complete: bool, missing_sections: [str] },
  findings:         [ { severity, file, line, summary } ],   # severity per PROJECT.md → Review Severity Framework
  self_review_comment_markdown: str,   # ready-to-post `## Self-Review Complete` body
  verdict:          "ready" | "needs_fixes" }
```
`quality_checks` carries one entry per [`PROJECT.md`](../../PROJECT.md) → *Quality Checks* row. When
`invoke` already ran them, copy its check-result (`quality_checks_source: invoke_check_result`) rather than
re-running; standalone, run them here (`ran_here`). `not_run` = ran-but-nothing-applicable, not
skipped. `findings[]` is where the **adversarial pass** (procedure Step 4) records the defects it
surfaces, each with a *Review Severity Framework* severity; the schema is unchanged, so the report
still composes with `ship`'s verify handoff.

</how-to-run>

<procedure>

1. **Read the PR** — its description and full diff.
2. **Read the approved plan** from the linked issue — find the linked issue via the PR's closing
   references, falling back to the bare issue number in the PR body (`Closes #N` leaf preferred, then
   `Part of #N`), and fetch the plan comment specifically. If the plan was revised through a
   **sanctioned re-plan** — a Reviewer plan review, or a mid-`invoke` loop-back that re-entered plan
   approval (e.g. a spike's re-plan checkpoint) — check against the *final, approved* plan.
3. **Check plan alignment** — every plan task has a corresponding change in the diff; no plan item
   missing. Divergence from the plan splits two ways: a **sanctioned re-plan** (it went back through
   plan approval — check against that final plan, it is not drift) versus **unsanctioned scope creep**
   (files or behavior that never went back through the gate — that is a finding, regardless of the
   "revisable plan" framing).
4. **Adversarial pass — try to break your own change.** This is the heart of the review: don't just
   confirm each plan item has a change — actively hunt the defect an independent second-model Reviewer
   would flag, and fix it now so their review *confirms* rather than *corrects*.
   - **Refute the change** — construct the input or state where it breaks: off-by-one, `nil`/empty,
     boundary value, duplicate, concurrent operation, unauthorized path. If you can build the failing
     case, that is a finding.
   - **Attack the tests, don't count them** — apply [`rules/testing.md`](../../rules/testing.md)'s
     definition of done and hunt the **false green**: a test that would still pass if the feature were
     reverted, a missing sad path, or an assertion that checks "it ran" instead of "it's correct." For
     each test ask, "if this passed but the feature were broken, would I know?"
   - **Assume the Reviewer's posture** — ask "what is the single most likely thing an independent
     Reviewer flags here?" (incomplete coverage — the most frequent; missing error/edge-case handling;
     a requirement from the issue not fully addressed; naming/structure/duplication) — and address it
     before they see it.
   - **Default skeptical** — an unproven concern is surfaced as a finding, not waved off.

   Record each finding in the `drift-report` `findings[]` with a severity from
   [`PROJECT.md`](../../PROJECT.md) → *Review Severity Framework* — the same contract as before, no new
   schema. This pass runs at full strength whether offloaded to a read-only sub-agent or run inline.
5. **Check cleanliness** — no debug code, no commented-out code, no "TODO"/"needs manual testing"
   comments, no unrelated changes.
6. **Review the PR description** — Summary, Changes, Technical Approach, Testing, and Checklist present
   and accurate.

**Fix drift now, don't document it for later.** `verdict: needs_fixes` → fix the drift (inline, or by
re-running the implement loop), then re-verify. `verdict: ready` → post the self-review comment.

</procedure>

<output>

On `verdict: ready`, post this comment on the PR via the lifecycle host, filling the bracketed parts
from the drift-report:

```markdown
## Self-Review Complete

### Plan Alignment
- [x] All plan items implemented
- [x] No scope creep — only files in the final approved plan changed
- [Any deviations and why]

### Adversarial Pass
- [x] Tried to refute the change (off-by-one, nil/empty, boundary, duplicate, concurrent, unauthorized) — [what was attempted]
- [x] Attacked the tests for false greens and missing sad paths — [what was found / confirmed]
- [Findings surfaced and their resolution, or "none"]

### Test Coverage Verified
- [x] By test type: [summary]
- [x] Edge cases: [summary]

### Reviewer Readiness
- [x] No debug code, no TODOs, no commented-out code
- [x] PR description complete
- [x] All quality checks pass (from PROJECT.md → Quality Checks)

PR is ready for the Reviewer.
```

Sign with the attribution footer from [`PROJECT.md`](../../PROJECT.md) → *Attribution & Model
Declaration*, naming your **runtime-actual** model. This step depends on that being honest: the
independence rule below compares the chain against the harness you are actually running as.

## Summon the Reviewer

**`verify` is the sole owner of the PR-gate Reviewer summons** ([ADR 0026](../../docs/adr/0026-reviewer-is-a-project-config-value-ac-summons-floor-preserved.md)).
The **AC** summons here — not the HC — so a run still gets its faithfulness backstop with no human in
the loop. No other Skill issues this summons: a second one produces two review requests, two windows,
and an unanswerable "did the primary respond?". (The *plan*-gate summons is a separate thing and stays
with the HC while plan approval is `required` — see the ADR.)

Read the chain from [`PROJECT.md`](../../PROJECT.md) → *Reviewer*: the **primary**, the **fallback
order**, the **bounded window**, and the **degradation floor**. **Baseline — primary `Codex`,
fallback order `Copilot`, bounded window `30m`, degradation floor `stop-and-ask`.** A Host App
overrides the first three there; **the floor is not configurable** — a run that cannot obtain an
independent review may not certify itself.

Those four values are written out here, not left behind the pointer, because this procedure has to be
executable by a reader who cannot open `PROJECT.md` — the resident-default rule in
[`rules/skills.md`](../../rules/skills.md). They are the Generic Baseline's **placeholders**: whatever
*Reviewer* declares wins, and the values above are what applies when it declares nothing.

After posting the self-review, take each chain entry in order:

1. **No *Invocation paths* row → the entry is UNREACHABLE, not slow.** That table is the membership
   list: an entry with no row has no summons mechanism, so there is nothing to issue and nothing to
   wait for. Fall back **immediately** — do not start the window.

   **No *Reviewer* section at all → every entry is unreachable, so go straight to step 7 and apply
   the floor: stop and ask the HC.** Do not summon anything and do not start a window. A vendored
   `PROJECT.md` that predates the section supplies no *Invocation paths* table, and the baseline
   values above name *who* the chain would try without naming *how* to reach any of them — the
   baseline ships placeholder harnesses, never a summons command it could not honor
   ([ADR 0027](../../docs/adr/0027-reviewer-chain-validated-against-invocation-paths.md)).
2. **The entry names the harness you are running as → also unreachable; fall back.** An AC cannot be
   its own independent backstop, and a same-model review that *appears* to run is worse than none.
   This is **self-reported by construction** — you compare the entry against your own runtime-actual
   identity, and nothing verifies that claim. It is also a **harness**-level check, while the
   standard's requirement is *model*-level: it catches a same-harness entry, and does **not** catch
   two different harnesses that happen to serve the same model.
3. **Precondition — the *Check* cell is optional and host-supplied.** Declared → run it before
   summoning; unmet means do not summon, fall back immediately. **Absent** → the **summons is the
   probe**: issue it, and carry the outcome forward as `unreachable (precondition unverified)` rather
   than as a clean timeout. The baseline ships no executable check, so this is the default path.
4. **Summon via the declared mechanism** and wait up to the **bounded window**.
5. **A response is a reply on _any_ of the three surfaces** — an issue-level PR comment, an **inline
   diff thread**, or a **review body**. Poll all three. Reading only issue-level comments makes an
   automated inline review invisible — the same trap [`listen`](../../skills/listen/SKILL.md) Step 1
   warns about.
6. **Window expires with no response → fall back** to the next entry and repeat from step 1. Never
   wait indefinitely.
7. **Chain exhausted — including a chain that was unreachable end to end → apply the degradation
   floor: stop and ask the HC.** Do not proceed to `listen` or `final` on an unreviewed PR.

**Carry the outcome forward**, and keep **timeout distinct from unreachable** — "no second model
exists" and "the second model is slow" call for different HC responses, and the SOW cannot
reconstruct the difference later. `unreachable (precondition unverified)` is a third, distinct
outcome: it says the summons went out but nothing confirmed it could land. Record which reviewer
answered, or which floor was hit and why;
[`final`](../../skills/final/SKILL.md) reports it in the SOW.

**Terminal artifact:** the self-review comment on the PR.

**Next step:** the review-response skill (`listen`) on the Reviewer's findings, then the deliver
skill (`final`).

</output>
