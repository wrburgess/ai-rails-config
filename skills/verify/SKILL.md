---
name: verify
description: Stage 4 of the development lifecycle. Self-review an existing PR against its approved plan for drift, test quality, cleanliness, and description completeness before the Reviewer sees it. Use on the PR that impl opened. It operates on the existing PR and never creates one.
---

<what-to-do>

Self-review the existing PR named in the invocation against its approved implementation plan, so that
when the Reviewer sees it they find nothing. This is **Stage 4 (Verify)** of the
[development lifecycle](../../docs/standards/development-lifecycle.md).

Read host-specific values — the review severities from [`PROJECT.md`](../../PROJECT.md) → *Review
Severity Framework*, the quality-check commands from *Quality Checks*, the lifecycle host from
*Lifecycle Host*, the attribution/model from *Attribution & Model Declaration*. Never hardcode them.

**This stage operates on the PR `impl` already opened — it never opens one.** If there is no PR, a
prior stage's terminal artifact was skipped: stop and recheck, don't reinterpret the lifecycle.

</what-to-do>

<how-to-run>

To keep the orchestrator's context lean, `verify` may be **offloaded to a read-only sub-agent** that
reads the whole PR diff and the plan in its discarded context and returns a compact **drift-report**;
the orchestrator supplies only pointers (the PR id, the linked issue id, and — when available —
`impl`'s returned check-result so the checks aren't re-run) and consumes the report.

*Graceful degradation ([ADR 0003](../../docs/adr/0003-skills-canonical-body-thin-shims-graceful-degradation.md),
[ADR 0005](../../docs/adr/0005-ship-hybrid-delegation-offload-retrieval-protect-judgment.md)):* on a
tool without sub-agents, run Steps 1–7 **inline**. The sub-agent (or you, inline) never posts to the
lifecycle host — the orchestrator owns that I/O and the attribution.

### drift-report (sub-agent → orchestrator)
```
{ plan_alignment:   { all_implemented: bool, missing_items: [str], scope_creep_files: [str] },
  test_quality:     { meaningful: bool, false_greens: [str], gaps: [str] },
  test_coverage_summary: { by_type: str, edge_cases: str },
  quality_checks:   [ { purpose, status: "pass"|"fail"|"not_run" } ],
  quality_checks_source: "impl_check_result" | "ran_here",
  cleanliness:      { debug_code: [str], commented_code: [str], todos: [str] },
  pr_description:   { complete: bool, missing_sections: [str] },
  findings:         [ { severity, file, line, summary } ],   # severity per PROJECT.md → Review Severity Framework
  self_review_comment_markdown: str,   # ready-to-post `## Self-Review Complete` body
  verdict:          "ready" | "needs_fixes" }
```
`quality_checks` carries one entry per [`PROJECT.md`](../../PROJECT.md) → *Quality Checks* row. When
`impl` already ran them, copy its check-result (`quality_checks_source: impl_check_result`) rather than
re-running; standalone, run them here (`ran_here`). `not_run` = ran-but-nothing-applicable, not
skipped.

</how-to-run>

<procedure>

1. **Read the PR** — its description and full diff.
2. **Read the approved plan** from the linked issue — find the linked issue via the PR's closing
   references, falling back to the bare issue number in the PR body (`Closes #N` leaf preferred, then
   `Part of #N`), and fetch the plan comment specifically. If the plan was revised after a Reviewer
   plan review, check against the *final* plan.
3. **Check plan alignment** — every plan task has a corresponding change in the diff; no files changed
   that aren't in the plan (no scope creep); no plan item missing.
4. **Review test quality** — apply [`rules/testing.md`](../../rules/testing.md)'s definition of done
   to every test in the diff. Are assertions meaningful, or a false green (e.g. only asserting a
   success status)? For each: "if this test passed but the feature were broken, would I know?" Are the
   edge cases (invalid input, duplicates, boundary values) tested?
5. **Check for the findings a Reviewer commonly catches** — incomplete test coverage (the most
   frequent), missing error/edge-case handling, requirements from the issue not fully addressed, and
   code-quality issues (naming, structure, duplication). Classify each by the
   [`PROJECT.md`](../../PROJECT.md) → *Review Severity Framework*.
6. **Check cleanliness** — no debug code, no commented-out code, no "TODO"/"needs manual testing"
   comments, no unrelated changes.
7. **Review the PR description** — Summary, Changes, Technical Approach, Testing, and Checklist present
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
- [x] No scope creep — only planned files changed
- [Any deviations and why]

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
Declaration*. Then notify the HC the PR is ready to send to the Reviewer; after Reviewer feedback the
HC runs the review-response skill (`rtr`) then the deliver skill (`final`).

**Terminal artifact:** the self-review comment on the PR.

</output>
