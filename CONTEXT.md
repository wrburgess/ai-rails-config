# ai-config

A generic, model-agnostic AI-agent configuration layer for software projects. It ships as a portable, business-neutral baseline that is vendored into a host application and then customized. It drives multiple AI coding agents (Claude, Codex, Copilot, Gemini) from a single source of truth.

## Language

**Config Bundle**:
The portable set of AI instructions, skills, and per-tool adapters this repo produces — the deliverable that gets vendored into a host app.
_Avoid_: "the config" (ambiguous), "the framework"

**Generic Baseline**:
The business-neutral, ready-to-vendor state of the Config Bundle. Contains no reference to any specific company, product, or domain.
_Avoid_: "default config", "boilerplate"

**Customization**:
The changes a host app makes after vendoring the Generic Baseline to fit its own domain, tooling, and conventions. Kept separate from the baseline so upstream updates stay mergeable.
_Avoid_: "overrides", "config"

**Stack Overlay** (a.k.a. **Sidecar Bundle**):
A stack-specific overlay Config Bundle (e.g. `ai-config-rails`) a Host App vendors *alongside* the Generic Baseline to restore the concrete, stack-named patterns and anti-patterns the baseline states only as neutral, stack-agnostic principles. The baseline names no stack; each overlay supplies one stack's concretes.
_Avoid_: "plugin", "extension", "fork"

**Host App** (a.k.a. **Consuming App**):
A software project that vendors the Config Bundle. The Config Bundle never assumes anything about a specific Host App's domain or stack.
_Avoid_: "client", "target repo"

**Canonical Source** (a.k.a. **Source of Truth**):
The one authored, model-neutral instruction/skill content from which every per-tool Adapter is derived. Agents must never receive drifted or divergent instructions.
_Avoid_: "master file", "the docs"

**Adapter**:
A per-tool projection of the Canonical Source onto a specific agent's native config surface (e.g. `CLAUDE.md`, `AGENTS.md`, `.github/copilot-instructions.md`, `GEMINI.md`).
_Avoid_: "wrapper", "integration"

**Skill**:
A portable, model-agnostic capability the Config Bundle provides (e.g. `grill-with-docs`, `assess`, `cplan`, `verify`, `rtr`, `final`, `ship`). Authored once as a canonical body; invokable by any configured agent through an Invocation Shim.
_Avoid_: "command", "workflow" (both are tool-specific invocation mechanisms, not the skill itself)

**Invocation Shim**:
The thin, tool-specific entry point that routes a tool's native invocation (a Claude slash command, a Codex/Copilot/Gemini prompt or documented procedure) to a Skill's canonical body. Carries no procedure of its own.
_Avoid_: "wrapper", "stub"

**Graceful Degradation**:
The rule that a Skill's procedure and quality gates are identical on every tool, while tool-specific *execution enhancements* (e.g. `ship`'s sub-agent-per-phase offloading) fall back to a documented inline path on tools that lack them. The mechanism degrades; the quality bar never does.
_Avoid_: "fallback mode", "compatibility mode"

**Project Config**:
The thin, per-Host-App file the Skills read for host-specific values (attribution string, quality-check commands, branch policy, review-severity framework, Lifecycle Host, issue/PR conventions). Lets Skills stay generic.
_Avoid_: "settings", "the customization" (Customization is broader)

**Lifecycle Host**:
The external platform where lifecycle artifacts live — assessments/plans on an issue, the PR that `impl` opens, the SOW on the PR. GitHub by default; set in Project Config and remappable to another platform.
_Avoid_: "the repo", "CI"

**Rules Layer**:
The tiered home for host guidance — patterns and anti-patterns. Split into a **Lean Core** (always resident) and **Deferred Deep Docs** (read on demand). Distinct from Project Config, which holds settings, not knowledge.
_Avoid_: "docs", "guidelines"

**Lean Core**:
Tier 1 of the Rules Layer — small, invariant per-domain rule files that are always loaded, each with a Patterns and an Anti-Patterns section.
_Avoid_: "the rules" (ambiguous with the whole Rules Layer)

**Deferred Deep Docs**:
Tier 2 of the Rules Layer — heavy, subsystem-specific case studies (`docs/rules/<domain>-postmortems.md`) loaded only when a trigger fires. Keeping these out of the Lean Core is what keeps session context lean.
_Avoid_: "postmortems" (host may use another word), "reference docs"

**Anti-Pattern**:
A first-class, required section of every rule file: an imperative "**Never** X — *because* Y" entry (with an optional host-filled reference slot) that steers agents away from choices we never want.
_Avoid_: "gotcha", "warning"

### Intake pipeline

**Intake Pipeline**:
The feedback loop that monitors the AI-engineering field and folds durable learnings back into the Config Bundle's Rules Layer, Skills, and ADRs.
_Avoid_: "the monitor", "the tracker"

**Watchlist**:
The machine-readable list of field sources — the roster in data form — that the `scout` sweep polls for new output.
_Avoid_: "feed list", "sources file"

**Learnings Log**:
The dated, append-only record of intake findings, each entry carrying a stance, a touches target, and a status.
_Avoid_: "the notes", "changelog"

**Manual-drop inbox**:
The human-fed lane where a person drops a raw pointer (a URL + who + one line of why) to field output the `scout` sweep can't fetch on its own — X posts, paywalled or feed-less sources — for the next sweep to turn into a Learnings-Log entry. A drop is raw input and carries no stance; scout assigns it.
_Avoid_: "the queue", "the dropbox"

**Drop skill**:
The intake pipeline's **push front door** (the `drop` Skill): it turns field output a human hands over in any session — a screenshot, a link, or a quote — into a well-formed, stance-less Manual-drop inbox drop, enforcing a real-URL gate, then delegates to `scout` to draft the Learnings-Log entry and open the review PR. Complements the `scout` **pull** sweep; a human still disposes on the PR.
_Avoid_: "the uploader", "the importer"

## Relationships

- The **Config Bundle** contains one **Canonical Source**, many **Adapters**, many **Skills**, one **Rules Layer**, and one **Project Config**.
- The **Rules Layer** = **Lean Core** (Tier 1, always resident) + **Deferred Deep Docs** (Tier 2, on demand); a trigger table links a Tier-1 file to its Tier-2 deep doc.
- A **Host App** vendors the **Generic Baseline**, then applies **Customization** (including its **Project Config**).
- A **Host App** may also vendor one or more **Stack Overlays** (e.g. `ai-config-rails`) alongside the **Generic Baseline**: the baseline states each rule as a neutral, stack-agnostic principle; the overlay supplies that stack's concrete patterns and anti-patterns.
- Each **Adapter** is derived from the **Canonical Source**; every **Skill** reads the **Project Config** for host-specific values.
- The **Intake Pipeline** reads a **Watchlist**, accepts human drops through the **Drop skill** (`drop`) into the **Manual-drop inbox** for sources it can't fetch, and records findings in a **Learnings Log** via the `scout` **Skill** — proposing changes to the **Rules Layer**, **Skills**, or ADRs. `scout` pulls on a sweep; `drop` pushes on demand.

## Example dialogue

> **Dev:** "Where does Markaz's rights-data rule go in the **Generic Baseline**?"
> **Maintainer:** "It doesn't. The baseline is business-neutral — that rule is a **Customization** a **Host App** would add after vendoring. Markaz is only a pattern reference for us."

## Flagged ambiguities

- "config" was used to mean the whole **Config Bundle**, the **Project Config**, and a **Host App's Customization** — resolved: these are three distinct things.
