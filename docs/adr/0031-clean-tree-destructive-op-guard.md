# A harness PreToolUse hook guards destructive git ops on a dirty tree; the Lean-Core rule is its degradation floor

**Status:** accepted

## Context

An agent can silently and unrecoverably destroy uncommitted work with a single
git command: `git reset --hard`, `git checkout -- <path>` / `git checkout .` /
`git checkout <ref> -f`, `git restore <path>`, or `git clean -f`. Unlike a bad
commit, there is no reflog or `ORIG_HEAD` to recover from — the tracked edits are
gone from the working tree, and `git clean` deletes untracked files outright. This
has bitten the repo before: a `git checkout` undoing a mutation-test change
reverted an uncommitted review fix ([#114](https://github.com/wrburgess/ai-config/issues/114)),
and [#134](https://github.com/wrburgess/ai-config/issues/134) asks for a general
guard against the whole class.

The protected-branch work ([ADR 0009](0009-defense-in-depth-branch-protection-all-agents.md))
established a three-layer, defense-in-depth model — server-side rules, local
git hooks, and per-tool accelerators — and the invariant that **a Layer-3
accelerator must never be the only guard**. The obvious move is to reuse that
model here. It does not port cleanly, and that mismatch is what this ADR settles.

**Git exposes no interception point for these ops.** The protected-branch guard's
portable primary (Layer 2) is a set of git-level hooks — `pre-commit`,
`pre-push`, `pre-merge-commit`, `pre-rebase` — that fire on the real operation no
matter which agent (or human) triggers it. Git ships **no** `pre-checkout`,
`pre-reset`, or `pre-clean` hook. (Its client-side hook set is fixed:
`pre-commit`, `prepare-commit-msg`, `commit-msg`, `post-commit`, `pre-rebase`,
`post-checkout`/`post-merge` — which fire *after* the destruction —
`pre-push`, and a few others; there is no *pre*-hook for checkout, reset, or
clean.) So for this op class there is no Layer-1/Layer-2 git-level backstop to
build — only a per-tool (Layer 3) interception is available at all.

## Decision

Ship a **Layer-3-only** guard: a Claude `PreToolUse` hook,
`.claude/hooks/enforce-clean-tree.sh`, wired in `.claude/settings.json` on the
`Bash` matcher, that blocks a destructive git op **only when the working tree is
dirty in the sense that op destroys**. Its degradation floor — the guard that
satisfies ADR 0009's "never the only guard" — is a **Lean-Core self-review rule**,
not another enforcement layer.

1. **The accelerator.** The hook mirrors the branch-creation guard's payload
   parser wholesale (read the JSON on stdin, cut heredoc bodies, split on the
   shell separators with pure parameter expansion, strip leading `ENV=val`, track
   `cd`, honor `-C` / `--git-dir`, and — critically — do **not** unwrap quotes, so
   a commit message or heredoc that merely *mentions* a destructive command stays
   data). It then classifies the subcommand into one of three destructive classes
   and applies an **op-aware** dirty test via `git status --porcelain`:
   reset-hard / checkout-discard / restore-worktree block only on a **tracked**
   change (a porcelain line not starting with `??`); `clean -f` blocks only on an
   **untracked** file (a line starting with `??`). A destroyer on a clean tree —
   or on a tree dirty only in the *other* sense — destroys nothing and is allowed.

2. **The degradation floor is a rule, not a layer.** Because there is no git-level
   pre-hook to build (see Context), the all-harness coverage that ADR 0009 demands
   cannot come from another enforcement layer. It comes from a Tier-1 Lean-Core
   anti-pattern in [`rules/self-review.md`](../../rules/self-review.md): *never run
   a destructive git op on a dirty tree without first running `git status` and
   stashing/committing.* Every configured harness reads that rule; on a harness
   with no `PreToolUse` mechanism the guard is rule-only, which is the correct
   degradation ([ADR 0003](0003-skills-canonical-body-thin-shims-graceful-degradation.md)).
   The hook is a best-UX accelerator that blocks the destruction *before* it runs;
   the rule is the floor that holds everywhere.

3. **Fail-open, never exit 1.** The hook's exit contract is `0` = allow, `2` =
   block, and it **never** exits 1 — any non-2 nonzero would let the tool run
   anyway. Unlike a write-blocking guard, fail-open is the *correct* direction
   here: the hook is an accelerator over the rule, so a parser miss must degrade
   to "the rule catches it", never to a false block that strands the agent. Every
   path ends in an explicit `allow`/`block`, with a trailing `allow` safety net,
   and an unparseable or non-`Bash` payload early-allows.

**Worktree isolation is a separate, deferred concern.** A sibling hazard — two
agents sharing one working tree and clobbering each other's uncommitted edits — is
captured as a Lean-Core anti-pattern in the same file, but its *mechanical*
enforcement is deferred (tracked in #110 /
[ADR 0028](0028-context-reset-boundary-resumable-stops-autonomous-listen.md)). This
ADR guards a single agent's own destructive commands, not concurrency.

## Considered options

- **A — build a git-level (Layer 2) hook, as the protected-branch guard did.**
  Rejected as impossible: git ships no `pre-checkout` / `pre-reset` / `pre-clean`
  hook, so there is no invocation-agnostic interception point for these ops. The
  protected-branch guard could be Layer 2 precisely because commit/push/merge/rebase
  *do* have pre-hooks; this op class does not.
- **B — block every invocation of these ops, dirty or clean.** Rejected: a
  false-positive storm. `git reset --hard` to re-sync a clean checkout, or `git
  clean -f` with nothing untracked, destroys nothing and is routine; blocking it
  trains agents to route around the guard.
- **C — ship only the Lean-Core rule, no hook.** Rejected as insufficient on
  Claude: guidance a body *reads* is not a gate, and a run that forgets it still
  destroys the tree. The accelerator is the pre-run block that makes the rule
  bite where a `PreToolUse` mechanism exists.
- **D — a porcelain-gated Layer-3 accelerator whose floor is the Lean-Core rule
  (chosen).** Op-aware, fail-open, best-UX on Claude, and degrading to rule-only
  elsewhere — the only shape that fits an op class with no git-level backstop.

## Consequences

- On Claude, a destructive git op on a dirty tree is blocked before it runs, with
  a message telling the agent to `git status` and stash/commit first. The hook's
  full contract is pinned by `.claude/hooks/enforce-clean-tree.test.sh` (run
  unconditionally in CI, like the branch-hook self-test), and the file is added to
  the parity check's `GUARDRAIL_FILES` so its absence reddens the gate.
- On any harness without a `PreToolUse` hook, the guard is the Lean-Core rule
  alone — the intended degradation, and the reason ADR 0009's "never the only
  guard" holds here without a second enforcement layer.
- **Known limit — parser, not sandbox.** A string parser cannot defeat a
  Turing-complete shell: an op reached through `bash -c '<quoted>'`, `eval`, a
  base64-decoded command, or a repo path built at runtime can still slip past,
  and — because the guard is deliberately fail-open — a genuinely novel spelling
  degrades to the rule rather than to a block. That trade is intentional: the cost
  of a miss is "the rule catches it", not a corrupted repo, whereas the cost of
  over-blocking would be an agent stranded mid-task.
