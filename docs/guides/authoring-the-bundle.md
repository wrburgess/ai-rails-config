# Authoring the Config Bundle

Conventions for **developing this repo** (adding skills, adapters, rules, and parity checks) — distinct
from the host-facing [`rules/`](../../rules) Lean Core, which is guidance for a Host App's own agents.
These are lessons captured as they were learned; extend as the bundle grows.

## Parity checks: gate on the tree, assert a floor, then check every present member

New structural checks in [`scripts/parity_check.rb`](../../scripts/parity_check.rb) follow one shape,
established by `check_rules`, `check_guardrails`, and `check_skills`:

1. **Gate on the surface existing.** `return unless Dir.exist?(path(SURFACE_DIR))` (or the presence of a
   signalling file, e.g. the guardrail sidecar). A bundle that does not ship the surface must **no-op**,
   so minimal / partial fixtures and downstream bundles are never reddened by a check for something they
   deliberately omit.
2. **Assert a `REQUIRED_*` floor.** A small hardcoded list (e.g. `REQUIRED_RULES`, `REQUIRED_SKILLS`)
   proves the expected members ship. This is the **only** part that grows per issue — usually one line.
3. **Apply the structural (shape) checks to every _present_ member**, discovered from disk — not to a
   hardcoded per-member list. Because the shape is enforced on whatever is present, members a later issue
   adds are **covered by construction**, with no edit to the check.

Keep the checker **stdlib-only** (no gems, no bundler — [ADR 0008](../adr/0008-structural-parity-check-not-model-in-the-loop.md)),
assert **section/heading presence, not content**, so a host freely extends a file's body without
reddening CI, and keep all `puts`/`warn` output **ASCII** (`rules/scripting.md`). Every new check needs a
matching self-test in [`test/parity_check_test.rb`](../../test/parity_check_test.rb): one happy path plus
one case per failure mode, each asserting **both** the non-zero exit **and** the specific error string, so
the check can never become a silent false green.

## Porting a template of record: copy byte-identical, verify with `diff -q`

When porting an artifact that is **already business- and tool-neutral** (e.g. a skill body from the
template-of-record repo), copy it **verbatim** and prove it:

```
diff -q <source>/SKILL.md skills/<name>/SKILL.md   # must report nothing
```

Do **not** "improve," reformat, or re-word it in transit. A verbatim port is trivially reviewable (the
diff is provably the source), avoids silent drift from the template of record, and keeps the reason the
artifact was chosen — that it needed no de-coupling — actually true. If a source file *does* carry
host/domain coupling, that de-coupling is real work: call it out in the assessment and plan, and do it as
a visible, reviewed edit — never fold it silently into a "port."
