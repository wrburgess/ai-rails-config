# Frontend Rules

**Applies to:** `app/javascript/`, `app/views/`, `app/components/`, `app/assets/`
**Deep doc:** `docs/rules/frontend-postmortems.md` (Tier 2 — deferred; read on demand when a trigger fires)

> Tier-1 Lean Core ([ADR 0004](../docs/adr/0004-two-tier-rules-layer-progressive-context.md)): always-resident invariants. Keep this file lean — push heavy, subsystem-specific case studies down to the deep doc. These are business-neutral starters; **extend per host**.

## Patterns

- **Hotwire first.** Use Turbo (frames, streams) and Stimulus for interactivity; most "we need a frontend framework" cases are a Turbo frame plus a small Stimulus controller.
- **Reusable UI as components.** Extract repeated markup into ViewComponents rather than partial soup, and unit-test the component in isolation.
- **Behavior in Stimulus controllers.** Wire DOM behavior through named controllers/targets/actions so it is discoverable and testable.
- **Style with the design system.** Use the host CSS framework's utility classes and shared stylesheets; keep markup semantic.

## Anti-Patterns

- **Never introduce a SPA/component framework** (React, Vue, Angular, Alpine, Svelte) — because it fractures the Hotwire model and doubles the rendering stack. *(Extend per host.)*
- **Never write inline `<script>` JavaScript in a view** — because it can't be reused or tested; put it in a Stimulus controller. *(Extend per host.)*
- **Never add jQuery or a jQuery plugin** — because Stimulus + Turbo already own DOM interaction; jQuery reintroduces a parallel, untested idiom. *(Extend per host.)*
- **Never add inline styles in a template** — because they bypass the design system; use utility classes or a stylesheet. *(Mailer templates, which require inline CSS for email-client compatibility, are the documented exception.)*
