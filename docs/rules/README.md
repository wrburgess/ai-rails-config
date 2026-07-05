# Deferred Deep Docs (Tier 2)

Tier 2 of the two-tier Rules Layer ([ADR 0004](../adr/0004-two-tier-rules-layer-progressive-context.md)). Heavy, subsystem-specific case studies live here as `docs/rules/<domain>-postmortems.md`. They are **not** auto-loaded: an agent reads one **on demand** (or via a dispatched sub-agent) when its work touches that subsystem, guided by the trigger table below. Keeping this depth *out* of the Tier-1 Lean Core (`rules/*.md`) is what actually keeps session context lean — a Tier-1 file that grows heavy is a signal to push detail down here, not to bloat the core.

## Baseline note

The Generic Baseline ships this structure and the trigger table; the deep docs themselves are **absent until a host has a real postmortem to record**. Create `docs/rules/<domain>-postmortems.md` when you write the first case study for that domain, add its `(Reference: #NNNN)` entries, and point the matching Tier-1 file's header at it. This "absent until needed" default keeps the baseline free of empty placeholder files while leaving each host an obvious place to grow depth.

## Trigger table

Each Tier-1 rule names the deferred deep doc to read when working in its area:

| Working in… | Tier-1 rule | Deferred deep doc |
|---|---|---|
| `app/models/`, `app/controllers/`, `app/jobs/`, `app/services/` | `rules/backend.md` | `docs/rules/backend-postmortems.md` |
| `app/javascript/`, `app/views/`, `app/components/`, `app/assets/` | `rules/frontend.md` | `docs/rules/frontend-postmortems.md` |
| `spec/` (tests) | `rules/testing.md` | `docs/rules/testing-postmortems.md` |
| `app/`, `config/`, `lib/` (secrets, scanners) | `rules/security.md` | `docs/rules/security-postmortems.md` |
| `bin/`, `scripts/` (bundled scripts) | `rules/scripting.md` | `docs/rules/scripting-postmortems.md` |
| before declaring work done | `rules/self-review.md` | (none — the checklist is the whole rule) |

Extend this table per host as you add domains.
