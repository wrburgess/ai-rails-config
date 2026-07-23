#!/usr/bin/env bash
#
# enforce-clean-tree.sh — PreToolUse guard (Layer 3 fast-fail accelerator, ADR 0031)
#
# Purpose: stop a DESTRUCTIVE git op from silently discarding uncommitted work on
# a DIRTY working tree. Three op classes, each with its own notion of "dirty":
#
#   - RESET_HARD       `git reset --hard [...]`            (a tracked change is lost)
#   - CHECKOUT_DISCARD `git checkout -- <path>` / `.` / `:/` / `<ref> -f`,
#                      and `git restore <path>` in worktree mode               (ditto)
#   - CLEAN            `git clean -f[...]` without `-n`/--dry-run  (untracked files deleted)
#
# The dirty test is OP-AWARE: reset/checkout/restore look for a *tracked* change
# (a `git status --porcelain` line NOT starting with `??`); clean looks for an
# *untracked* file (a line starting with `??`). So `git clean -f` with only
# tracked edits, or `git reset --hard` with only untracked files, is allowed —
# the op would destroy nothing.
#
# Wired in .claude/settings.json as a PreToolUse hook matching "Bash". The full
# tool payload arrives as JSON on stdin; we read it rather than trusting
# $CLAUDE_PROJECT_DIR (a resumed session can re-root that onto the wrong checkout).
#
# Exit codes (PreToolUse contract):
#   0  → allow the tool call
#   2  → block the tool call; stderr is shown to the agent
# We deliberately NEVER exit 1: a non-2 nonzero would let the tool run anyway
# (fail-open). Unlike a write-blocking guard, fail-open is the correct direction
# here — this hook is an ACCELERATOR over the Lean-Core self-review rule (its
# degradation floor), which remains in force on any harness without a PreToolUse
# hook. So a parser miss degrades to "the rule catches it", never to a false block.
# Every path below ends in an explicit `allow` or `block`; a trailing `allow` is
# the safety net.
#
# Git has no pre-checkout / pre-reset / pre-clean hook, so — unlike the
# protected-branch guard — there is no Layer-1/Layer-2 git-level backstop for
# these ops. The Lean-Core rule (rules/self-review.md) is the all-harness floor
# that satisfies ADR 0009's "a Layer-3 accelerator must never be the only guard".

allow() { exit 0; }
block() { echo "$1" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Read the JSON payload from stdin and pull out the few fields we need.
# ---------------------------------------------------------------------------
payload="$(cat)"

# json_get <jq-filter> <python-key-path> — extract a string field.
# Prefers jq, falls back to python3. If both are absent we cannot parse the
# command, so the dispatch below early-allows (fail-open — the rule is the floor).
json_get() {
  local jq_filter="$1" py_path="$2" out=""
  if command -v jq >/dev/null 2>&1; then
    out="$(printf '%s' "$payload" | jq -r "$jq_filter // empty" 2>/dev/null)"
  elif command -v python3 >/dev/null 2>&1; then
    out="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
cur = data
for key in sys.argv[1].split("."):
    if isinstance(cur, dict):
        cur = cur.get(key)
    else:
        cur = None
        break
if cur is not None:
    print(cur)
' "$py_path" 2>/dev/null)"
  fi
  printf '%s' "$out"
}

tool_name="$(json_get '.tool_name' 'tool_name')"
cwd="$(json_get '.cwd' 'cwd')"
command="$(json_get '.tool_input.command' 'tool_input.command')"

# Session cwd is the worktree the agent is operating in. Fall back to the hook
# process's own cwd (also the session dir) if stdin gave us nothing.
[ -n "$cwd" ] || cwd="$PWD"

# ---------------------------------------------------------------------------
# Helpers (shared with the branch-creation guard's Bash-command parser)
# ---------------------------------------------------------------------------

# Resolve a possibly-relative path against a base dir (no realpath dependency).
resolve_dir() {
  local d="$1" base="$2"
  case "$d" in
    /*) printf '%s' "$d" ;;
    *)  printf '%s/%s' "$base" "$d" ;;
  esac
}

# Un-glue shell *grouping* punctuation a token may be prefixed/suffixed with, so
# a real subshell or command substitution — `(cd`, `$(git`, `commit)` — is still
# recognized. We deliberately do NOT strip quotes or backticks: prose inside a
# commit message or string literal must stay un-command-like so it is skipped,
# not mistaken for an executed command (the key false-positive defense).
strip_wrappers() {
  local t="$1" i
  for i in 1 2 3; do t="${t#[\$\(\{]}"; done
  for i in 1 2; do t="${t%[\)\}]}"; done
  printf '%s' "$t"
}

# --- op classifiers ---------------------------------------------------------
# Each takes the args that FOLLOW the git subcommand and returns 0 (destructive)
# or 1 (harmless / not-this-class). Flags only; pathspecs are irrelevant to the
# classification (the dirty test does the gating).

# `git reset` is destructive only with --hard (NOT --soft/--mixed/bare).
reset_is_hard() {
  local a
  for a in "$@"; do
    case "$a" in --hard) return 0 ;; esac
  done
  return 1
}

# `git checkout` discards worktree changes when it has a `--` pathspec, a `.`/`:/`
# target, or a -f/--force. NOT when creating a branch (-b/-B), NOT a bare
# `git checkout <branch>` (git enforces its own dirty-tree safety there).
checkout_is_discard() {
  local a dashdash=0 force=0 mkbranch=0 pathtarget=0
  for a in "$@"; do
    case "$a" in
      --)          dashdash=1 ;;
      -f|--force)  force=1 ;;
      -b|-B)       mkbranch=1 ;;
      .|:/)        pathtarget=1 ;;
    esac
  done
  [ "$mkbranch" -eq 1 ] && return 1
  [ "$dashdash" -eq 1 ] && return 0
  [ "$force" -eq 1 ] && return 0
  [ "$pathtarget" -eq 1 ] && return 0
  return 1
}

# `git checkout` creates a branch (never a worktree discard) when it carries a
# branch-creating flag. Used to exclude those from the bare-positional path check
# below — `git checkout -b <name>` must not be mistaken for a pathspec discard.
checkout_makes_branch() {
  local a
  for a in "$@"; do
    case "$a" in -b|-B|--orphan) return 0 ;; esac
  done
  return 1
}

# For a `git checkout` that is NOT already a known discard and does NOT create a
# branch, echo its SOLE non-flag positional token when there is exactly one; echo
# nothing for zero or multiple positionals. That lone token is either a ref (a
# branch/commit switch — git self-guards) or a pathspec whose uncommitted changes
# a bare `git checkout <path>` would silently discard; the caller resolves which.
lone_positional() {
  local a n=0 tok=""
  for a in "$@"; do
    case "$a" in
      -*) ;;                       # flag or `--` — not a positional
      *)  n=$((n + 1)); tok="$a" ;;
    esac
  done
  [ "$n" -eq 1 ] && printf '%s' "$tok"
}

# `git restore` touches the worktree unless it is a --staged-ONLY (index) restore.
# Default (no --staged) is worktree; explicit --worktree/-W is worktree even
# alongside --staged.
restore_is_discard() {
  local a worktree=0 staged=0
  for a in "$@"; do
    case "$a" in
      --worktree|-W) worktree=1 ;;
      --staged|-S)   staged=1 ;;
    esac
  done
  [ "$worktree" -eq 1 ] && return 0
  [ "$staged" -eq 1 ] && return 1
  return 0
}

# `git clean` deletes untracked files only with -f/--force AND without a
# -n/--dry-run. Short flags may be clustered (-fd, -xf, -df), so inspect each
# short-flag cluster character-by-character.
clean_is_destructive() {
  local a cluster force=0 dry=0
  for a in "$@"; do
    case "$a" in
      --force)   force=1 ;;
      --dry-run) dry=1 ;;
      --*)       : ;;                 # any other long flag
      -*)
        cluster="${a#-}"
        case "$cluster" in *f*) force=1 ;; esac
        case "$cluster" in *n*) dry=1 ;; esac
        ;;
    esac
  done
  [ "$force" -eq 1 ] || return 1
  [ "$dry" -eq 1 ] && return 1
  return 0
}

# --- op-aware dirty tests (read a `git status --porcelain` blob) -------------
# Untracked lines start with `??`; every other non-empty line is a tracked
# change (` M`, `M `, `A `, `D `, ...). `??` is QUOTED in each case pattern so it
# matches literally rather than as the two-char glob it would otherwise be.
has_tracked_change() {
  local line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in '??'*) continue ;; *) return 0 ;; esac
  done <<EOF
$1
EOF
  return 1
}
has_untracked() {
  local line
  while IFS= read -r line; do
    case "$line" in '??'*) return 0 ;; esac
  done <<EOF
$1
EOF
  return 1
}

# ---------------------------------------------------------------------------
# Bash tool: scan each command segment for a destructive git op on a dirty tree.
# Reuses the branch guard's parser wholesale: cut heredoc bodies, split on the
# shell separators with pure param-expansion (never sed — a missing tool must not
# silently blank the command), strip leading ENV=val, track `cd`, honor
# `-C`/--git-dir, then inspect the subcommand. Quotes/backticks are NOT unwrapped,
# so a commit message or heredoc that merely MENTIONS a destructive command stays
# data. Block on the first destructive-op-on-dirty segment; otherwise allow.
#
# RESIDUAL (documented, not covered here — the same residual the branch guard
# carries): the separator split is quote-BLIND by design, so an INLINE message
# that literally contains a command separator AND destructive git text — e.g.
# `git commit -m "undo; git reset --hard"` — can over-block: the `;` splits the
# message and the trailing fragment reads as a real `git reset --hard`. This
# over-block degrades toward the Lean-Core self-review rule (the floor), never to
# a silent discard. For such messages use a heredoc (`git commit -F - <<EOF…`) or
# `-F <file>`, whose body is cut before scanning and stays data.
# ---------------------------------------------------------------------------
guard_bash() {
  local cmd="$1"
  [ -n "$cmd" ] || allow

  # Everything from the first `<<` to the end is a heredoc body — DATA fed to a
  # command, not commands to run. Cut it before inspecting anything.
  cmd="${cmd%%<<*}"

  case "$cmd" in *git*) ;; *) allow ;; esac      # no git token → nothing to guard

  set -f   # no globbing: `set -- $seg` must word-split only, never expand `*.rb`
  local curdir="$cwd" seg
  # Split on command separators into one segment per line, using pure bash
  # parameter expansion. Crude (ignores quoting) but only ever WIDENS what we
  # inspect; the op-classifier + dirty test below is what actually gates a block.
  local normalized="$cmd"
  normalized="${normalized//&&/$'\n'}"   # `a && b`
  normalized="${normalized//||/$'\n'}"   # `a || b`
  normalized="${normalized//|/$'\n'}"    # `a | b`
  normalized="${normalized//;/$'\n'}"    # `a ; b`

  while IFS= read -r seg; do
    # shellcheck disable=SC2086
    set -- $seg
    [ "$#" -gt 0 ] || continue

    # Un-glue grouping punctuation so a subshell / command substitution is still
    # recognized. Quotes/backticks are deliberately NOT stripped (see
    # strip_wrappers) — that keeps prose in a message from looking like a command.
    local -a _toks=() _t
    for _t in "$@"; do _toks+=("$(strip_wrappers "$_t")"); done
    set -- "${_toks[@]}"
    [ "$#" -gt 0 ] || continue

    # Strip leading `ENV=value` assignments (`GIT_PAGER=cat git reset --hard`).
    while [ "$#" -gt 0 ]; do
      case "$1" in
        [A-Za-z_]*=*) shift ;;
        *) break ;;
      esac
    done
    [ "$#" -gt 0 ] || continue

    # Track directory changes so `cd <dir> && git reset` is evaluated in <dir>.
    if [ "$1" = "cd" ] && [ -n "${2:-}" ]; then
      curdir="$(resolve_dir "$2" "$curdir")"
      continue
    fi

    # Is this segment a git invocation? (`git`, `/usr/bin/git`, ...)
    case "$1" in
      git|*/git) ;;
      *) continue ;;
    esac
    shift   # drop the `git` token

    # Walk git's global options to find -C <dir> / --git-dir and the subcommand.
    #
    # A value-expecting global option as the FINAL token (e.g. `git -C`, `git -c`)
    # has no following value AND no subcommand after it. `shift 2` on a 1-element
    # "$@" is a no-op in bash, so `continue` would re-enter the same token forever
    # (an infinite loop → the hook hangs). Guard each value-option: consume the
    # pair only when a second token exists; otherwise stop walking — a trailing
    # value-option means no subcommand follows, so there is nothing destructive to
    # inspect and we fall through to allow.
    local repodir="$curdir" sub=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -C)            repodir="$(resolve_dir "${2:-.}" "$curdir")"; if [ "$#" -ge 2 ]; then shift 2; continue; else break; fi ;;
        --git-dir=*)   repodir="$(resolve_dir "${1#--git-dir=}" "$curdir")"; shift; continue ;;
        --git-dir)     repodir="$(resolve_dir "${2:-.}" "$curdir")"; if [ "$#" -ge 2 ]; then shift 2; continue; else break; fi ;;
        -c)            if [ "$#" -ge 2 ]; then shift 2; continue; else break; fi ;;   # `-c key=val` config override
        -*)            shift; continue ;;       # any other global flag
        *)             sub="$1"; shift; break ;;
      esac
    done
    [ -n "$sub" ] || continue

    # Classify the subcommand into a destructive class + its dirty-test flavor.
    # `dirty_kind` is `tracked` (reset/checkout/restore) or `untracked` (clean).
    # `discard_paths` names the EXPLICIT pathspec a discard op targets, so the
    # dirty test can be scoped to just those paths (FIX 4); it stays empty for a
    # pathless op (`reset --hard`, `checkout .` / `<ref> -f`, `clean`), which uses
    # a whole-repo test. Scoping only ever RELAXES a block (a clean named path →
    # allow), so a mis-scope degrades toward the rule floor, never to a false block.
    local dirty_kind="" _p _tok _after
    local -a discard_paths=()
    case "$sub" in
      reset)
        reset_is_hard "$@" && dirty_kind=tracked
        ;;
      checkout)
        if checkout_is_discard "$@"; then
          dirty_kind=tracked
          # Only the `-- <path>...` form names an explicit pathspec; `.` / `:/` /
          # `-f` are whole-tree discards (leave discard_paths empty).
          _after=0
          for _p in "$@"; do
            if [ "$_after" -eq 1 ]; then discard_paths+=("$_p"); continue; fi
            [ "$_p" = "--" ] && _after=1
          done
        elif ! checkout_makes_branch "$@"; then
          # Bare `git checkout <tok>` — a single non-flag positional, no `--`/`-b`.
          # If <tok> resolves to a commit it is a branch/ref switch (git enforces
          # its own overwrite safety) → allow. If it does NOT resolve, it is a
          # pathspec whose uncommitted changes checkout would silently discard.
          _tok="$(lone_positional "$@")"
          if [ -n "$_tok" ] && \
             ! git -C "$repodir" rev-parse --verify --quiet "${_tok}^{commit}" >/dev/null 2>&1; then
            dirty_kind=tracked
            discard_paths+=("$_tok")
          fi
        fi
        ;;
      restore)
        if restore_is_discard "$@"; then
          dirty_kind=tracked
          # Collect positional pathspecs; skip flags and the -s/--source tree-ish
          # value; after `--`, every token is a path.
          _after=0
          local _skip=0
          for _p in "$@"; do
            if [ "$_after" -eq 1 ]; then discard_paths+=("$_p"); continue; fi
            if [ "$_skip" -eq 1 ]; then _skip=0; continue; fi
            case "$_p" in
              --)          _after=1 ;;
              -s|--source) _skip=1 ;;
              -*)          : ;;
              *)           discard_paths+=("$_p") ;;
            esac
          done
        fi
        ;;
      clean)
        clean_is_destructive "$@" && dirty_kind=untracked
        ;;
    esac
    [ -n "$dirty_kind" ] || continue

    # Op-aware dirty test in the resolved repo. Scope to the explicit pathspec when
    # the op named one; otherwise test the whole tree. If git status cannot run
    # (not a repo), we cannot confirm dirtiness — do NOT block (rule is the floor).
    local status_out
    if [ "${#discard_paths[@]}" -gt 0 ]; then
      status_out="$(git -C "$repodir" status --porcelain -- "${discard_paths[@]}" 2>/dev/null)" || continue
    else
      status_out="$(git -C "$repodir" status --porcelain 2>/dev/null)" || continue
    fi

    if [ "$dirty_kind" = "tracked" ]; then
      if has_tracked_change "$status_out"; then
        if [ "${#discard_paths[@]}" -gt 0 ]; then
          block "Refusing 'git $sub ${discard_paths[*]}' in '$repodir' - it would discard uncommitted tracked changes to that path. Run 'git status', then stash or commit first."
        else
          block "Refusing 'git $sub' on a dirty working tree in '$repodir' - it would discard uncommitted tracked changes. Run 'git status', then stash or commit first."
        fi
      fi
    else
      if has_untracked "$status_out"; then
        block "Refusing 'git $sub' on a tree with untracked files in '$repodir' - it would permanently delete them. Run 'git status', then review or stash first."
      fi
    fi
  done <<EOF
$normalized
EOF

  allow
}

# ---------------------------------------------------------------------------
# Dispatch — only Bash is inspected; every other tool (and a degraded payload)
# early-allows (fail-open: this guard is an accelerator over the Lean-Core rule).
# ---------------------------------------------------------------------------
case "$tool_name" in
  Bash) guard_bash "$command" ;;
  "")   allow ;;
  *)    allow ;;
esac

allow
