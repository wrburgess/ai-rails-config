# Self-Review Rules

**Applies to:** every change, before declaring work done
**Deep doc:** none (this file is the checklist itself)

> Tier-1 Lean Core ([ADR 0004](../docs/adr/0004-two-tier-rules-layer-progressive-context.md)): always-resident invariants. Keep this file lean. These are business-neutral, stack-neutral starters; **extend per host** — concrete stack-named examples live in the matching **Stack Overlay** (e.g. `ai-config-rails`), vendored alongside the baseline.

## Patterns

- **Run the full quality gate green before saying "done".** All of the host's checks (declared in `PROJECT.md` → *Quality Checks*) must pass, not "probably pass."
- **Re-read your own diff as a hostile reviewer would**, line by line, and fix what you would flag before anyone else sees it.
- **Confirm every planned item has a corresponding test**, and that each test would actually fail if the feature broke.
- **Source every "verified" / "as-of" / factual claim with a citation that actually states it** — put each claim under the exact URL that supports it and quote the load-bearing line; if you can't quote it, you have not verified it.

## Checklist

- [ ] Every item in the plan is implemented.
- [ ] Every planned test scenario is covered, with meaningful assertions (not just "it runs").
- [ ] Edge cases handled: invalid input, `nil`, duplicates, boundary values.
- [ ] No `TODO` / "needs manual testing" left behind — the test is written, not deferred.
- [ ] The full quality gate passes locally.
- [ ] If this is a lifecycle stage, its terminal artifact actually exists (e.g. `invoke` is not done until the PR exists — a commit is not the artifact).
- [ ] Any `<placeholder>`-style token in text posted to the lifecycle host (issue/PR/comment body) is written host-safe (`{name}` / `NAME`) — GitHub strips angle-bracket tokens.

## Anti-Patterns

- **Never declare work done on a red or un-run check** — because "probably fine" is exactly how regressions ship. *(Extend per host.)*
- **Never leave a "TODO / needs manual testing" comment in place of a test** — because it never gets written; build the test now. *(Extend per host.)*
- **Never ship minimal assertions and call it complete** — because the last 20% (edge cases, sad paths, thorough assertions) is where quality lives. *(Extend per host.)*
- **Never put `<angle-bracket>` placeholders in text you post to the lifecycle host** (issue/PR/comment bodies) — because GitHub's markdown sanitizer silently strips them (even inside backticks), so `path/<name>/file` renders as `path//file` and reads as a typo; use `{name}` or `NAME` in prose bound for a host artifact (angle brackets are fine in committed source files). *(Extend per host.)*
- **Never dismiss a surprising code path on one fixture's symptom** — because the fixture you happen to hold may make the flaw fail *loudly* (a visible error) while a neighbouring input makes the identical flaw fail *silently*, and grading the symptom instead of the mechanism inverts the severity from must-fix to cosmetic. Before waving an anomaly off, spend one input: ask what the mechanism does to a hostile neighbour of the case in hand — the same shape with the failure moved, hidden, or inverted — and grade the worst reachable outcome, not the observed one. "It still errored" is evidence about your fixture, not about the code, and "pre-existing" is a scheduling note, never a severity. *(Provenance: issue #103 / PR #111; case study in `docs/rules/testing-postmortems.md`; extend per host.)*
- **Never cite a source that doesn't support the claim placed under it** — because a dated URL manufactures false rigor: a reader who follows it finds nothing, and the "verified" label becomes a lie. Attribute each claim to the source that actually states it, and quote the exact supporting line (a structural link-check confirms a URL *resolves*, never that it *supports* the claim — that gap is author-owned). *(Provenance: issue #56 / PR #61; extend per host.)*
- **Never act on a remote-authoritative namespace from stale local state** — because ADR numbers, issue numbers, and the default branch's commit graph live on the remote, so a value computed from a possibly-behind local checkout collides the instant a parallel branch moved first (a gap, a duplicate, a stale rebase base): sync-before-create, search-before-file, fetch-before-rebase. *(Provenance: #133 / #131; extend per host.)*
- **Never run a destructive git op on a dirty working tree** — `git reset --hard`, `git checkout -- <path>` / `git checkout .` / `git checkout <ref> -f`, `git restore <path>`, or `git clean -f` — without first running `git status` and stashing or committing anything you might want back, because each silently and unrecoverably discards uncommitted work: the reset/checkout/restore forms drop tracked edits, and `git clean -f` deletes untracked files, with no reflog or undo to recover them. The narrow mutation-run case is called out in [`rules/testing.md`](testing.md) → *Anti-Patterns*; this is the general rule, so cross-reference it rather than duplicating. *(Provenance: issue #134; a Layer-3 PreToolUse accelerator blocks this pre-run on harnesses that support one — [ADR 0031](../docs/adr/0031-clean-tree-destructive-op-guard.md) — but this rule is the all-harness floor; extend per host.)*
- **Never share a worktree with a concurrently-editing agent** — because two agents writing the same working tree race on the same files and silently clobber each other's uncommitted edits with no merge boundary; give each agent its own worktree or checkout. Mechanical enforcement of this isolation is deferred (tracked in #110 / [ADR 0028](../docs/adr/0028-context-reset-boundary-resumable-stops-autonomous-listen.md)). *(Provenance: issue #134; extend per host.)*
