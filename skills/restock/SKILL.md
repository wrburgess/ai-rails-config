---
name: restock
description: Refresh the Tooling Pegboard — re-verify each tracked harness/model entry's facts against its own sources, apply only the real field-level deltas (reconfirm-or-age, never fabricate), flag estimates a version bump has outdated, and open a deltas-only PR — staying quiet when nothing changed. Use to keep the current-best-tools snapshot current without babysitting the release firehose.
---

<what-to-do>

Run one **Pegboard refresh**: read the [Tooling Pegboard](../../CONTEXT.md) — the current-state snapshot
of the coding harnesses and models worth weighing for software development — re-verify each entry's facts
against its own `sources:`, and open a pull request carrying **only what changed** for a human to review.
This is the mechanism that keeps the Pegboard current; `restock` **proposes** the deltas, a human
**disposes** on the PR.

`restock` is the **sibling** of [`scout`](../scout/SKILL.md): where `scout` drafts stance-bearing
*learnings* from field voices, `restock` maintains *facts* about tools. A version bump or a price change
is not a judgment to be argued — it is a fact to be **verified**, so `restock` carries no `stance`; its
discipline is provenance (every changed value traced to a real source; an unconfirmable value ages rather
than being invented).

Read host-specific values from [`PROJECT.md`](../../PROJECT.md): the **Pegboard location** from *Tooling
Pegboard*, the branch/PR/issue-linking policy from *Branch & PR Policy*, and the attribution/model from
*Attribution & Model Declaration*. Never hardcode a path, a branch name, a platform verb, or any product
name here — the body stays business-neutral and a Host App repoints its Pegboard in Project Config.

**Terminal artifact: an open PR** carrying the field-level deltas — or, when nothing changed, **no PR at
all**. `restock` never commits directly to a protected branch, and never opens an empty PR.

</what-to-do>

<procedure>

1. **Resolve the Pegboard location from Project Config.** Read [`PROJECT.md`](../../PROJECT.md) →
   *Tooling Pegboard* for the artifact's path. Everything below refers to it by role, never by a
   hardcoded path.

2. **Load the Pegboard and re-verify each entry against its own `sources:`.** For every harness and model
   entry, poll its `sources:` URLs (with `WebFetch` / `WebSearch`) for the current value of each tracked
   fact — version, release date, price, effort tiers, benchmark, config features. **Never invent a source
   or a value.** A `sources:` list that no longer resolves is *staleness to surface* (step 6), never
   papered over with a placeholder.

3. **Reconcile — apply only real, field-level deltas (reconfirm-or-age).** For each entry:
   - A **fact that changed** (a new stable version, a moved price, an added effort tier, a status change)
     is updated in place, and that entry's `verified` is set to today — its facts were re-confirmed.
   - A **fact confirmed unchanged** leaves the entry **untouched**, `verified` included, so the eventual
     diff carries *changed entries only*, never a rehash of the whole board.
   - A **fact that can no longer be confirmed** is **left at its last value to age** (its `verified` falls
     behind) — surfaced as staleness, never fabricated or blanked. This is the `voices.yml` unresolved-feed
     discipline applied to facts.
   - A subjective `dumb_zone` estimate is **never machine-authored**; preserve it verbatim. **When an
     entry's `stable_version` changes and it carries a `dumb_zone`, flag that estimate as possibly-stale**
     in the digest — the guess predates the new version and wants a human re-estimate.

4. **Weigh roster changes against the inclusion test — propose, don't decide.** A tool that has newly
   cleared, or newly fails, the Pegboard's inclusion test (does it plausibly enter a rotation decision for
   software development?) may be proposed as an **add** or a **retire** (`status: dormant`) — but roster
   changes are a human's call: surface them in the PR for disposition rather than adding or dropping
   silently. Never fabricate an entry for a tool whose facts can't be sourced.

5. **Empty refresh → no PR, no commit.** If **no** entry's facts changed — every tracked value
   re-confirmed unchanged, or only aged — the refresh is *empty*: open **no** pull request and commit
   nothing (a scheduled session logs "refreshed, nothing changed" and exits clean). The board is left
   exactly as it was so the next run re-checks it. An empty refresh is a valid, expected result — never a
   reason to open an empty PR, to bump a date for its own sake, or to invent a change. Steps 6–7 apply
   **only when at least one fact changed.**

6. **Render the deltas-only digest.** Summarize **only what moved** since the last state — new entries,
   retired entries, version bumps, price changes, and any `dumb_zone` flagged stale by a version bump —
   plus a short **staleness** note listing any `sources:` that no longer resolved and any entry whose
   `verified` is now aging. Never restate unchanged rows. This digest is the PR body and the payload a
   host's push transport delivers.

7. **Open the PR — never commit directly.** Create the feature branch per
   [`PROJECT.md`](../../PROJECT.md) → *Branch & PR Policy*, commit the changed entries with the
   attribution trailer from *Attribution & Model Declaration*, push, and open a pull request whose body is
   the deltas-only digest. Link the issue per policy. The PR is a **proposal**: the human accepts, edits,
   or rejects the deltas — and any roster add/retire — before anything merges.

*Graceful degradation ([ADR 0003](../../docs/adr/0003-skills-canonical-body-thin-shims-graceful-degradation.md)):*
the poll-and-reconcile churn (steps 2–3) is output-heavy and **may be offloaded to a sub-agent** that
returns the proposed deltas + staleness notes; the invoking context keeps the judgment (what counts as a
real delta, the inclusion-test add/retire call) and owns the lifecycle-host I/O (commit, push, open PR). A
**scheduled/headless** run opens the PR for asynchronous disposition; an **interactive** run may walk the
deltas with the human first — the reviewable PR is the floor and the terminal artifact either way. On a
tool without sub-agents, run every step inline. The mechanism degrades; the provenance discipline and the
human-disposes gate never do.

</procedure>

<quality-gate>

Before opening the PR: every **changed** value traces to a real `sources:` URL (no invented fact); every
**unconfirmable** value was left to age (never fabricated or blanked); no unchanged entry was rewritten
(the diff is deltas-only, not a rehash); a `dumb_zone` outdated by a version bump is flagged; and roster
add/retire proposals are surfaced for the human, not applied silently. On an **empty refresh** — no fact
changed — the correct output is **no PR and no commit**, never an empty PR. Whenever at least one fact
changed, the output is a reviewable PR, **never a direct commit** to a protected branch. Sign the PR and
any lifecycle-host comment with the footer from [`PROJECT.md`](../../PROJECT.md) → *Attribution & Model
Declaration*, using your runtime-actual model.

**The gate that never degrades:** `restock` **proposes** verified deltas and a human **disposes** on the
PR. It re-checks facts and stamps provenance; it does not decide, on its own, that a tool joins or leaves
the board.

</quality-gate>
</output>
