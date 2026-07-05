# Backend Rules

**Applies to:** `app/models/`, `app/controllers/`, `app/jobs/`, `app/services/`
**Deep doc:** `docs/rules/backend-postmortems.md` (Tier 2 — deferred; read on demand when a trigger fires)

> Tier-1 Lean Core ([ADR 0004](../docs/adr/0004-two-tier-rules-layer-progressive-context.md)): always-resident invariants. Keep this file lean — push heavy, subsystem-specific case studies down to the deep doc. These are business-neutral starters; **extend per host**.

## Patterns

- **Rails ecosystem first.** Before building anything custom, check Rails built-ins (callbacks, concerns, validations, enums, delegations, STI, polymorphic associations), then established, well-maintained gems. Reach for custom code only when nothing fits — and say why in the assessment/plan.
- **Thin controllers.** Keep controller actions to request/response orchestration; put domain logic in models, concerns, or plain Ruby objects under `app/services/`.
- **Authorize every non-public action** with the host's authorization layer — deny by default, never hardcode role checks inline.
- **Enforce invariants in the database too.** Pair model validations with DB-level constraints (`NOT NULL`, unique indexes, foreign keys); a validation is not a guarantee under concurrency.

## Anti-Patterns

- **Never use `default_scope`** — because it silently leaks into every query, association, and `new`, and is painful to bypass; use explicit named scopes instead. *(Extend per host.)*
- **Never iterate a whole table with `.all.each`** — because it loads every row into memory at once; use `find_each` for 100+ records. *(Extend per host.)*
- **Never call `.count` inside a loop** — because it fires a query per iteration; preload the data or use a counter cache. *(Extend per host.)*
- **Never add a service-object framework gem** (Interactor, Trailblazer, Dry-Transaction) without a documented justification — because plain Ruby POROs in `app/services/` cover almost every case. *(Extend per host.)*
