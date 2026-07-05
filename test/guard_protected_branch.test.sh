#!/usr/bin/env bash
#
# Tests for bin/guard-protected-branch (Layer 2 git-hook guard, ADR 0009).
#
# Run:  test/guard_protected_branch.test.sh
# Exit: 0 if every case passes, 1 otherwise.
#
# The guard accepts the branch name as $2, so these tests need NO real git repo:
# they copy the guard + a fabricated .githooks/protected-branches sidecar into a
# temp dir (the guard resolves the sidecar relative to its own location) and
# assert the exit code (0 = allow, 2 = block) for each branch.
#
# AC-vs-human exemption: the guard treats a non-TTY shell as an AC, and every
# invocation here forces CLAUDE_CODE=1 so the security-relevant AC path is
# exercised deterministically. The human-exempt path requires an interactive
# TTY (`[ -t 0 ]`) that a headless test can't supply; its logic is trivial and
# identical to the proven Markaz guard, so it is intentionally not exercised here.

set -uo pipefail

SRC_GUARD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/guard-protected-branch"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/.githooks"
cp "$SRC_GUARD" "$TMP/bin/guard-protected-branch"
chmod +x "$TMP/bin/guard-protected-branch"
GUARD="$TMP/bin/guard-protected-branch"
SIDECAR="$TMP/.githooks/protected-branches"

PASS=0; FAIL=0

# write_sidecar <branch> [<branch> ...] — (re)write the derived sidecar.
write_sidecar() { printf '%s\n' "$@" > "$SIDECAR"; }

# expect <name> <want-exit> <branch>  — run the guard as an AC against <branch>.
expect() {
  local name="$1" want="$2" branch="$3" got
  CLAUDE_CODE=1 "$GUARD" "commit" "$branch" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1)); printf '  ok   %-56s (exit %s)\n' "$name" "$got"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL %-56s (want %s, got %s)\n' "$name" "$want" "$got"
  fi
}

echo "Default sidecar (main/master/develop):"
write_sidecar main master develop
expect "AC commit on main -> block" 2 "main"
expect "AC commit on master -> block" 2 "master"
expect "AC commit on develop -> block" 2 "develop"
expect "AC commit on feature/x -> allow" 0 "feature/x"
expect "AC commit on detached HEAD -> allow" 0 "HEAD"
expect "branch named feature/main-thing -> allow (not an exact match)" 0 "feature/main-thing"

echo "Host-trimmed sidecar (main only):"
write_sidecar main
expect "trimmed list: commit on main -> block" 2 "main"
expect "trimmed list: commit on develop -> allow (not protected here)" 0 "develop"

echo "Host-extended sidecar (adds release):"
write_sidecar main master develop release
expect "extended list: commit on release -> block" 2 "release"

echo "Sidecar with blank lines / whitespace / comments:"
printf '\n  main  \n# a comment\n\tdevelop\n' > "$SIDECAR"
expect "whitespace/comment tolerated: main -> block" 2 "main"
expect "whitespace/comment tolerated: develop -> block" 2 "develop"
expect "whitespace/comment tolerated: feature/x -> allow" 0 "feature/x"

echo "Missing sidecar (fail closed to default):"
rm -f "$SIDECAR"
expect "no sidecar: commit on main -> block (fail-closed)" 2 "main"
expect "no sidecar: commit on develop -> block (fail-closed)" 2 "develop"
expect "no sidecar: commit on feature/x -> allow" 0 "feature/x"

echo "Human exemption smoke (AC vars unset, non-TTY still treated as AC):"
write_sidecar main master develop
# With no AC var and a non-TTY stdin the guard still blocks (non-TTY => AC).
env -u CLAUDE_CODE -u CODEX -u GITHUB_COPILOT_AGENT "$GUARD" "commit" "main" </dev/null >/dev/null 2>&1
if [ "$?" = "2" ]; then
  PASS=$((PASS + 1)); printf '  ok   %-56s (exit 2)\n' "non-TTY with no AC var -> block (fallback)"
else
  FAIL=$((FAIL + 1)); printf '  FAIL %-56s\n' "non-TTY with no AC var -> block (fallback)"
fi

echo
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
