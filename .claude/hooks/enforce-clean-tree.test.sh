#!/usr/bin/env bash
#
# Tests for enforce-clean-tree.sh (Layer 3 fast-fail guard, ADR 0031).
#
# Run:  .claude/hooks/enforce-clean-tree.test.sh
# Exit: 0 if every case passes, 1 otherwise.
#
# These build throwaway git repos in a temp dir and feed the hook real
# PreToolUse-shaped JSON payloads on stdin, asserting the exit code
# (0 = allow, 2 = block). No network, no touching the real repo.
#
# Coverage map (what each block proves):
#   - A destructive git op on a DIRTY tree is blocked through every realistic
#     Bash form: plain, `git -C <dir>`, `cd <dir> && git`, and leading `ENV=val`.
#   - The op-aware dirty test: `clean` looks only for untracked files; `reset
#     --hard` / `checkout` / `restore` look only for tracked changes. A repo that
#     is "dirty" in the OTHER sense than the op destroys is allowed.
#   - Non-destructive spellings (checkout -b, bare checkout, reset --soft, clean
#     -n, restore --staged, ...) are allowed even on a dirty tree.
#   - String-literal / heredoc content mentioning a destructive command is DATA,
#     not a command (regression against the false-block class the branch hook
#     already fixed).
#   - Clean tree + any destroyer is allowed (the false-positive guard).
#
# This guard is a per-tool ACCELERATOR over the Lean-Core self-review rule; its
# degradation floor is that rule (rule-only on harnesses with no PreToolUse hook).
# It fails OPEN (never exit 1) by design (ADR 0031 / ADR 0009).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/enforce-clean-tree.sh"

command -v jq >/dev/null 2>&1 || { echo "tests require jq"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- build fixture repos ----------------------------------------------------
new_repo() {  # new_repo <path> — a repo with two committed tracked files, clean tree
  local path="$1"
  git init -q -b work "$path"
  git -C "$path" config user.email t@t.test
  git -C "$path" config user.name test
  printf 'original\n' > "$path/tracked.txt"
  printf 'sibling\n'  > "$path/other.txt"
  git -C "$path" add tracked.txt other.txt
  git -C "$path" commit -q -m init
  # A real branch ref, so a bare `git checkout otherbranch` resolves as a ref
  # (the FIX-2 ref-vs-pathspec distinction) rather than being read as a pathspec.
  git -C "$path" branch otherbranch
}

CLEAN_REPO="$TMP/clean";          new_repo "$CLEAN_REPO"
TRACKED_DIRTY="$TMP/tracked";     new_repo "$TRACKED_DIRTY"
UNTRACKED_DIRTY="$TMP/untracked"; new_repo "$UNTRACKED_DIRTY"
NEUTRAL="$TMP/neutral";           new_repo "$NEUTRAL"    # clean; a cwd to run -C from
NONREPO="$TMP/plain_dir";         mkdir -p "$NONREPO"    # not a git repo

# TRACKED_DIRTY: a tracked file modified, NO untracked files present.
printf 'changed\n' > "$TRACKED_DIRTY/tracked.txt"
# UNTRACKED_DIRTY: an untracked file present, NO tracked changes.
printf 'brand new\n' > "$UNTRACKED_DIRTY/untracked.txt"

PASS=0; FAIL=0

# expect <name> <expected-exit> <json-payload>
expect() {
  local name="$1" want="$2" payload="$3" got
  printf '%s' "$payload" | "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1)); printf '  ok   %-64s (exit %s)\n' "$name" "$got"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL %-64s (want %s, got %s)\n' "$name" "$want" "$got"
  fi
}

# Resolve a timeout wrapper so a FIX-1 regression (the shift-2 infinite loop in
# the global-option walk) surfaces as a LOUD failure — exit 124 ≠ the expected 0
# — instead of hanging the whole suite. Falls back to running unwrapped only on a
# host with neither `timeout` nor `gtimeout` (accepting the hang risk there).
TIMEOUT=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT="timeout 5"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT="gtimeout 5"; fi

# expect_bounded <name> <expected-exit> <json-payload> — like expect, but runs the
# hook under $TIMEOUT so a hang becomes a visible FAIL (124), never a stuck suite.
expect_bounded() {
  local name="$1" want="$2" payload="$3" got
  # shellcheck disable=SC2086
  printf '%s' "$payload" | $TIMEOUT "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1)); printf '  ok   %-64s (exit %s)\n' "$name" "$got"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL %-64s (want %s, got %s)\n' "$name" "$want" "$got"
  fi
}

bash_payload() {   # bash_payload <command> <cwd>
  jq -nc --arg cmd "$1" --arg c "$2" \
    '{tool_name:"Bash", cwd:$c, tool_input:{command:$cmd}}'
}
write_payload() {  # write_payload <tool> <file_path> <cwd>
  jq -nc --arg t "$1" --arg f "$2" --arg c "$3" \
    '{tool_name:$t, cwd:$c, tool_input:{file_path:$f}}'
}

echo "reset --hard on a dirty (tracked-change) tree -> block:"
expect "git reset --hard, tracked file modified -> block" 2 \
  "$(bash_payload 'git reset --hard' "$TRACKED_DIRTY")"
expect "git reset --hard HEAD~1, tracked file modified -> block" 2 \
  "$(bash_payload 'git reset --hard HEAD~1' "$TRACKED_DIRTY")"

echo "checkout that discards on a dirty (tracked-change) tree -> block:"
expect "git checkout -- <file>, tracked modified -> block" 2 \
  "$(bash_payload 'git checkout -- tracked.txt' "$TRACKED_DIRTY")"
expect "git checkout ., tracked modified -> block" 2 \
  "$(bash_payload 'git checkout .' "$TRACKED_DIRTY")"
expect "git checkout :/, tracked modified -> block" 2 \
  "$(bash_payload 'git checkout :/' "$TRACKED_DIRTY")"
expect "git checkout <branch> -f, tracked modified -> block" 2 \
  "$(bash_payload 'git checkout otherbranch -f' "$TRACKED_DIRTY")"
expect "git checkout --force <branch>, tracked modified -> block" 2 \
  "$(bash_payload 'git checkout --force otherbranch' "$TRACKED_DIRTY")"

echo "restore (worktree mode) on a dirty (tracked-change) tree -> block:"
expect "git restore <file>, tracked modified -> block" 2 \
  "$(bash_payload 'git restore tracked.txt' "$TRACKED_DIRTY")"
expect "git restore ., tracked modified -> block" 2 \
  "$(bash_payload 'git restore .' "$TRACKED_DIRTY")"

echo "clean (force) with untracked files present -> block:"
expect "git clean -f, untracked present -> block" 2 \
  "$(bash_payload 'git clean -f' "$UNTRACKED_DIRTY")"
expect "git clean -fd, untracked present -> block" 2 \
  "$(bash_payload 'git clean -fd' "$UNTRACKED_DIRTY")"
expect "git clean -d -f, untracked present -> block" 2 \
  "$(bash_payload 'git clean -d -f' "$UNTRACKED_DIRTY")"
expect "git clean -xf, untracked present -> block" 2 \
  "$(bash_payload 'git clean -xf' "$UNTRACKED_DIRTY")"

echo "repo-targeting variants must STILL block:"
expect "git -C <dirtyrepo> reset --hard from clean cwd -> block (-C)" 2 \
  "$(bash_payload "git -C $TRACKED_DIRTY reset --hard" "$NEUTRAL")"
expect "cd <dirtyrepo> && git reset --hard from clean cwd -> block (cd)" 2 \
  "$(bash_payload "cd $TRACKED_DIRTY && git reset --hard" "$NEUTRAL")"
expect "ENV=1 git reset --hard on dirty cwd -> block (env-prefix)" 2 \
  "$(bash_payload 'GIT_PAGER=cat git reset --hard' "$TRACKED_DIRTY")"

echo "clean tree + any destroyer -> allow (false-positive guard):"
expect "git reset --hard on clean repo -> allow" 0 \
  "$(bash_payload 'git reset --hard' "$CLEAN_REPO")"
expect "git clean -f on clean repo -> allow" 0 \
  "$(bash_payload 'git clean -f' "$CLEAN_REPO")"

echo "non-destructive spellings on a dirty tree -> allow:"
expect "git checkout -b <new> on dirty -> allow (creates branch)" 0 \
  "$(bash_payload 'git checkout -b newbranch' "$TRACKED_DIRTY")"
expect "bare git checkout <branch> on dirty -> allow (git self-guards)" 0 \
  "$(bash_payload 'git checkout otherbranch' "$TRACKED_DIRTY")"
expect "git reset --soft HEAD~1 on dirty -> allow" 0 \
  "$(bash_payload 'git reset --soft HEAD~1' "$TRACKED_DIRTY")"
expect "git reset --mixed on dirty -> allow" 0 \
  "$(bash_payload 'git reset --mixed' "$TRACKED_DIRTY")"
expect "bare git reset on dirty -> allow" 0 \
  "$(bash_payload 'git reset' "$TRACKED_DIRTY")"
expect "git stash on dirty -> allow" 0 \
  "$(bash_payload 'git stash' "$TRACKED_DIRTY")"
expect "git clean -n on untracked-dirty -> allow (dry-run)" 0 \
  "$(bash_payload 'git clean -n' "$UNTRACKED_DIRTY")"
expect "git clean --dry-run on untracked-dirty -> allow" 0 \
  "$(bash_payload 'git clean --dry-run' "$UNTRACKED_DIRTY")"
expect "git restore --staged <file> on dirty -> allow (unstages only)" 0 \
  "$(bash_payload 'git restore --staged tracked.txt' "$TRACKED_DIRTY")"

echo "op-aware dirtiness precision:"
expect "git clean -f, only tracked modified (no untracked) -> allow" 0 \
  "$(bash_payload 'git clean -f' "$TRACKED_DIRTY")"
expect "git reset --hard, only untracked exists (no tracked change) -> allow" 0 \
  "$(bash_payload 'git reset --hard' "$UNTRACKED_DIRTY")"
expect "git checkout -- <file>, only untracked exists -> allow" 0 \
  "$(bash_payload 'git checkout -- tracked.txt' "$UNTRACKED_DIRTY")"

echo "message / heredoc text is DATA, not a command:"
expect "git commit -m mentioning reset --hard on dirty -> allow" 0 \
  "$(bash_payload 'git commit -m "revert the reset --hard change"' "$TRACKED_DIRTY")"
expect "heredoc body mentioning git clean -f on untracked-dirty -> allow" 0 \
  "$(bash_payload "cat > notes.txt <<'EOF'
git clean -f
EOF" "$UNTRACKED_DIRTY")"
expect "echo mentioning git reset --hard on dirty -> allow" 0 \
  "$(bash_payload 'echo "git reset --hard"' "$TRACKED_DIRTY")"

echo "non-git / read-only / degraded -> allow:"
expect "ls -la on dirty -> allow (no git)" 0 \
  "$(bash_payload 'ls -la' "$TRACKED_DIRTY")"
expect "git status on dirty -> allow (read-only)" 0 \
  "$(bash_payload 'git status' "$TRACKED_DIRTY")"
expect "git diff on dirty -> allow (read-only)" 0 \
  "$(bash_payload 'git diff' "$TRACKED_DIRTY")"
expect "git log on dirty -> allow (read-only)" 0 \
  "$(bash_payload 'git log' "$TRACKED_DIRTY")"
expect "git reset --hard outside any repo -> allow (dirtiness undeterminable)" 0 \
  "$(bash_payload 'git reset --hard' "$NONREPO")"
expect "Write tool payload -> allow (only Bash is inspected)" 0 \
  "$(write_payload Write "$TRACKED_DIRTY/f.txt" "$TRACKED_DIRTY")"
expect "Edit tool payload -> allow (only Bash is inspected)" 0 \
  "$(write_payload Edit "$TRACKED_DIRTY/tracked.txt" "$TRACKED_DIRTY")"
expect "absent tool_name -> allow (degraded, fail-open)" 0 \
  "$(jq -nc --arg c "$TRACKED_DIRTY" '{cwd:$c, tool_input:{command:"git reset --hard"}}')"
expect "empty tool_name -> allow (degraded, fail-open)" 0 \
  "$(jq -nc --arg c "$TRACKED_DIRTY" '{tool_name:"", cwd:$c, tool_input:{command:"git reset --hard"}}')"

echo "FIX 1 — a trailing value-expecting global option must not hang (shift-2 guard):"
expect_bounded "git -C (value option as final token) -> allow, no hang" 0 \
  "$(bash_payload 'git -C' "$TRACKED_DIRTY")"
expect_bounded "git -c (value option as final token) -> allow, no hang" 0 \
  "$(bash_payload 'git -c' "$TRACKED_DIRTY")"

echo "FIX 2 — bare 'git checkout <tok>' (no --): pathspec discard vs ref switch:"
expect "git checkout <dirty-tracked-file> (not a ref) on dirty -> block" 2 \
  "$(bash_payload 'git checkout tracked.txt' "$TRACKED_DIRTY")"
expect "git checkout <existing-branch> (a ref) on dirty -> allow (branch switch)" 0 \
  "$(bash_payload 'git checkout otherbranch' "$TRACKED_DIRTY")"
expect "git checkout <tracked-file> on a clean tree -> allow (nothing to lose)" 0 \
  "$(bash_payload 'git checkout tracked.txt' "$CLEAN_REPO")"

echo "FIX 4 — path-scoped dirty test names only what is actually dirty:"
expect "git checkout -- <clean-file> while a DIFFERENT file is dirty -> allow" 0 \
  "$(bash_payload 'git checkout -- other.txt' "$TRACKED_DIRTY")"
expect "git checkout -- <dirty-file> -> block (named path loses changes)" 2 \
  "$(bash_payload 'git checkout -- tracked.txt' "$TRACKED_DIRTY")"

echo
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
