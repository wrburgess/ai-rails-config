#!/usr/bin/env ruby
# frozen_string_literal: true

# parity_check.rb — structural parity check for the Config Bundle (ADR 0008).
#
# Verifies, WITHOUT any model-in-the-loop testing, that every per-tool Adapter still resolves to the
# Canonical Source and that the Project Config is structurally intact. Dependency-free: standard
# library only (no gems, no bundler), so it runs on a bare Ruby in CI.
#
# Usage:
#   ruby scripts/parity_check.rb [--root DIR]
#     --root DIR   Directory to check (default: current directory). Used by the self-test to point
#                  the checker at fixture bundles.
#
# Exit status: 0 when every invariant holds; 1 when any fails (all failures are printed).
#
# Adapter marker conventions (kept in lockstep with AGENTS.md / PROJECT.md):
#   Native-discovery adapter:  <!-- parity:native source=AGENTS.md -->
#   Rendered adapter:          <!-- parity:render source=AGENTS.md --> … <!-- parity:endrender -->
#                              (the region between the markers must equal AGENTS.md byte-for-byte)

require "optparse"
require_relative "protected_branches"
require_relative "human_gates"

class ParityCheck
  CANONICAL = "AGENTS.md"

  # Import Adapters: files that resolve to the Canonical Source. The existence + count invariants apply
  # to every entry; how each is allowed to resolve is governed by NATIVE_CAPABLE_ADAPTERS below.
  IMPORT_ADAPTERS = ["CLAUDE.md", "GEMINI.md"].freeze

  # Adapters that may resolve via NATIVE discovery instead of an `@AGENTS.md` import. `GEMINI.md`
  # qualifies: Google's Antigravity CLI (which superseded Gemini CLI, announced 2026-05-19) reads
  # `AGENTS.md` natively since v1.20.3, and a host may point the tool straight at `AGENTS.md` via the
  # `context.fileName` setting — both are first-class resolutions per ADR 0002, so a Gemini adapter
  # that declares native discovery (a `parity:native source=AGENTS.md` marker, the same mechanism the
  # Copilot adapter uses) must not false-fail parity. `CLAUDE.md` is NOT native-capable — Claude Code
  # has no native `AGENTS.md` discovery, so the import is its only resolution.
  #
  # ADR 0008 boundary: this stays a purely STRUCTURAL check — it verifies the Adapter *file* resolves
  # to `AGENTS.md`, not that the external tool actually reads that filename. No structural check can
  # detect a future tool renaming its default context file (a false-green); that liveness is re-verified
  # out-of-band in docs/research/tool-config-discovery.md (last re-verified for Antigravity CLI, #56).
  NATIVE_CAPABLE_ADAPTERS = ["GEMINI.md"].freeze

  COPILOT_ADAPTER = ".github/copilot-instructions.md"
  PROJECT_CONFIG = "PROJECT.md"

  # Files whose relative markdown links must resolve: the Canonical Source, its Adapters, the Project
  # Config, and EVERY bundle-owned markdown file the bundle ships. Each is link-checked only if present
  # (check_links skips missing files), so a minimal fixture bundle — and a host that vendored only part
  # of the tree — is unaffected.
  #
  # WHY AN EXPLICIT ENUMERATION AND NOT A GLOB (issue #96). A glob (`docs/**/*.md`) evaluated at check
  # time would, after vendoring, sweep a HOST APP's own docs and redden its parity on day one for dead
  # links the bundle never shipped — the exact failure pattern this list exists to stop. An enumeration
  # names only bundle-owned paths, so the host blast radius is zero. The cost is that the list can rot;
  # that is bought back by `test_link_checked_enumerates_every_bundle_owned_markdown_file` in
  # test/parity_check_test.rb, which globs the subtrees below and fails naming any unlisted file. That
  # guard lives in test/, which ai-config-sync deliberately never vendors, so it runs in the bundle and
  # never in a host — which is precisely what lets the SHIPPED constant stay a safe, explicit list.
  #
  # THE RULE: every markdown file this bundle VENDORS is enumerated here. The drift guard derives its
  # expected set by walking ai-config-sync's own ALLOW manifest — not by re-globbing the subtrees named
  # below — so an entire omitted *subtree* is caught, not just an omitted file. (A guard that globbed
  # the same subtrees this list enumerates could only ever agree with itself.) Add a new ADR, guide,
  # Learnings entry, Skill body, or shim? Add it here too; the drift test names anything you miss.
  #
  # NOTE: this constant also drives check_rendered_regions, which scans the same files for a
  # `parity:render` block. Both scans are code-span aware (see strip_code), so a doc may safely SHOW a
  # marker or a link inside a fenced example without tripping either check.
  LINK_CHECKED = [
    # Canonical Source, its Adapters, and the Project Config
    "AGENTS.md",
    "CLAUDE.md",
    "GEMINI.md",
    "PROJECT.md",
    ".github/copilot-instructions.md",
    "README.md",
    # Context Map
    "CONTEXT.md",
    # Claude Invocation Shims (ADR 0003 / ADR 0010). check_skills asserts each shim CONTAINS the
    # literal `skills/<name>/SKILL.md`, which a wrong relative prefix (`../skills/...`) still
    # satisfies — link-checking them is what actually proves the pointer resolves.
    ".claude/commands/assess.md",
    ".claude/commands/clip.md",
    ".claude/commands/create-skill.md",
    ".claude/commands/devise.md",
    ".claude/commands/distill.md",
    ".claude/commands/final.md",
    ".claude/commands/follow.md",
    ".claude/commands/invoke.md",
    ".claude/commands/listen.md",
    ".claude/commands/restock.md",
    ".claude/commands/scout.md",
    ".claude/commands/ship.md",
    ".claude/commands/verify.md",
    # Architecture Decision Records
    "docs/adr/0001-distribute-as-copy-in-sync-script.md",
    "docs/adr/0002-agents-md-canonical-pointer-projection.md",
    "docs/adr/0003-skills-canonical-body-thin-shims-graceful-degradation.md",
    "docs/adr/0004-two-tier-rules-layer-progressive-context.md",
    "docs/adr/0005-ship-hybrid-delegation-offload-retrieval-protect-judgment.md",
    "docs/adr/0006-baseline-skill-set-and-github-default-lifecycle-host.md",
    "docs/adr/0007-attribution-includes-model-version-for-audits.md",
    "docs/adr/0008-structural-parity-check-not-model-in-the-loop.md",
    "docs/adr/0009-defense-in-depth-branch-protection-all-agents.md",
    "docs/adr/0010-repo-layout-canonical-skills-at-root.md",
    "docs/adr/0011-ascii-safe-stdout-stays-doc-only.md",
    "docs/adr/0012-intake-pipeline-placement.md",
    "docs/adr/0013-scheduled-intake-sweep-and-empty-sweep-policy.md",
    "docs/adr/0014-manual-drop-inbox-for-unfetchable-sources.md",
    "docs/adr/0015-intake-front-door-drop-skill.md",
    "docs/adr/0016-interactive-sequential-disposition-scout.md",
    "docs/adr/0017-stack-neutral-baseline-with-stack-overlays.md",
    "docs/adr/0018-neutrality-pass-scope-tooling-and-enforcement.md",
    "docs/adr/0019-create-skill-authoring-front-door.md",
    "docs/adr/0020-right-size-plan-revisable-direction.md",
    "docs/adr/0021-voice-watchlist-front-door.md",
    "docs/adr/0022-instruction-file-line-allowance.md",
    "docs/adr/0023-tool-roster-facts-tracker-sibling-to-intake.md",
    "docs/adr/0024-harness-model-naming-convention.md",
    "docs/adr/0025-human-gate-policy-is-a-project-config-value.md",
    # Standards
    "docs/standards/development-lifecycle.md",
    # Out-of-band research (the per-tool discovery re-verification AGENTS.md cites) and Stack Overlays
    "docs/research/tool-config-discovery.md",
    "docs/overlays/ai-config-rails.md",
    # Guides
    "docs/guides/authoring-the-bundle.md",
    "docs/guides/branch-protection.md",
    "docs/guides/detaching-the-intake-pipeline.md",
    "docs/guides/intake-sweep-scheduling.md",
    "docs/guides/tool-roster-refresh-scheduling.md",
    "docs/guides/usage.md",
    # Tier-2 Deferred Deep Docs (ADR 0004)
    "docs/rules/README.md",
    "docs/rules/scripting-postmortems.md",
    "docs/rules/skills-postmortems.md",
    # Tier-1 Lean Core (ADR 0004)
    "rules/backend.md",
    "rules/frontend.md",
    "rules/scripting.md",
    "rules/security.md",
    "rules/self-review.md",
    "rules/skills.md",
    "rules/testing.md",
    # Skill canonical bodies + their bundled files (ADR 0003 / ADR 0010)
    "skills/assess/SKILL.md",
    "skills/clip/SKILL.md",
    "skills/create-skill/SKILL.md",
    "skills/devise/SKILL.md",
    "skills/distill/ADR-FORMAT.md",
    "skills/distill/CONTEXT-FORMAT.md",
    "skills/distill/SKILL.md",
    "skills/final/SKILL.md",
    "skills/follow/SKILL.md",
    "skills/invoke/SKILL.md",
    "skills/listen/SKILL.md",
    "skills/restock/SKILL.md",
    "skills/scout/SKILL.md",
    "skills/ship/SKILL.md",
    "skills/verify/SKILL.md",
    # Reference seed: the Voices Watchlist prose doc, the intake inbox, and the Learnings Log
    "docs/reference/README.md",
    "docs/reference/ai-engineering-voices.md",
    "docs/reference/intake-inbox/README.md",
    "docs/reference/intake-inbox/TEMPLATE.md",
    "docs/reference/learnings/README.md",
    "docs/reference/learnings/index.md",
    "docs/reference/learnings/entries/2026-07-06-building-effective-agents-simplicity.md",
    "docs/reference/learnings/entries/2026-07-06-hamel-evals-first-class-tests.md",
    "docs/reference/learnings/entries/2026-07-07-andrew-ng-coding-agent-domain-acceleration.md",
    "docs/reference/learnings/entries/2026-07-07-andrew-ng-loop-engineering.md",
    "docs/reference/learnings/entries/2026-07-07-anthropic-steering-claude-code.md",
    "docs/reference/learnings/entries/2026-07-07-eugene-yan-compound-with-ai.md",
    "docs/reference/learnings/entries/2026-07-07-eugene-yan-eval-design-pattern.md",
    "docs/reference/learnings/entries/2026-07-07-eugene-yan-llm-secure-source-code.md",
    "docs/reference/learnings/entries/2026-07-07-google-io-antigravity-cli-gemini-adapter.md",
    "docs/reference/learnings/entries/2026-07-07-hamel-hard-to-eval-product-smell.md",
    "docs/reference/learnings/entries/2026-07-07-jason-liu-scheduled-work-kinds.md",
    "docs/reference/learnings/entries/2026-07-07-karpathy-software-3-agent-native.md",
    "docs/reference/learnings/entries/2026-07-07-latent-space-against-one-shot-design.md",
    "docs/reference/learnings/entries/2026-07-07-lilian-weng-harness-engineering.md",
    "docs/reference/learnings/entries/2026-07-07-openai-cookbook-agent-improvement-loop.md",
    "docs/reference/learnings/entries/2026-07-07-openai-cookbook-iterative-repair-loops.md",
    "docs/reference/learnings/entries/2026-07-07-pocock-agent-read-authoring.md",
    "docs/reference/learnings/entries/2026-07-07-pocock-grill-with-docs-anti-patterns.md",
    "docs/reference/learnings/entries/2026-07-07-pocock-grill-with-docs.md",
    "docs/reference/learnings/entries/2026-07-07-pocock-kill-context-bloat.md",
    "docs/reference/learnings/entries/2026-07-07-pocock-progressive-disclosure-skills.md",
    "docs/reference/learnings/entries/2026-07-07-pocock-skills-as-markdown-catalog.md",
    "docs/reference/learnings/entries/2026-07-07-thorsten-ball-agents-in-orbs.md",
    "docs/reference/learnings/entries/2026-07-07-thorsten-ball-building-software-is-learning.md",
    "docs/reference/learnings/entries/2026-07-07-willison-ai-review-caught-bugs.md",
    "docs/reference/learnings/entries/2026-07-07-willison-better-models-worse-tools.md",
    "docs/reference/learnings/entries/2026-07-07-willison-dspy-agent-prompt-evals.md",
    "docs/reference/learnings/entries/2026-07-07-willison-fable-judgement-delegation.md",
    "docs/reference/learnings/entries/2026-07-07-willison-vibe-coding-agentic-converging.md",
    "docs/reference/learnings/entries/2026-07-08-pocock-code-review-fowler-smells.md",
    "docs/reference/learnings/entries/2026-07-08-pocock-grilling-fixes-backport.md",
    "docs/reference/learnings/entries/2026-07-08-pocock-wayfinder-blocking-tickets.md",
  ].freeze

  # Usage guides (ADR 0008 surface finalization, issue #11). Checked only for a bundle that ships a
  # docs/guides/ tree (the GUIDES_DIR gate) so a minimal fixture bundle is unaffected — the same "only
  # for a bundle that ships them" stance as check_rules / check_skills / check_guardrails. The floor is
  # existence: each required guide must be shipped, so a future manifest change can't silently drop the
  # vendor/customize/run walkthrough. Reachability is deliberately NOT anchored to README.md — README
  # is not vendored (ai-config-sync skips it) and a Host App owns its own, so a "referenced by README"
  # rule would fail in-host, breaking the vendored-copy parity invariant the guide itself documents.
  # In-host the guide is discoverable under docs/guides/; in this repo README links it (guarded by
  # check_links, since README is in LINK_CHECKED).
  GUIDES_DIR = "docs/guides"
  REQUIRED_GUIDES = ["docs/guides/usage.md"].freeze

  # Tier-1 Lean Core rule files (ADR 0004). Each must exist, be referenced by AGENTS.md so every tool
  # can reach the Lean Core, and declare its Patterns + Anti-Patterns sections. Checked only for a
  # bundle that ships a rules/ tree (the RULES_DIR gate) so a minimal fixture bundle is unaffected —
  # the same "only for a bundle that ships them" stance as check_guardrails.
  RULES_DIR = "rules"
  REQUIRED_RULES = [
    "rules/backend.md", "rules/frontend.md", "rules/testing.md",
    "rules/security.md", "rules/self-review.md", "rules/scripting.md", "rules/skills.md"
  ].freeze
  # Section presence is asserted (the heading line), not content — so a host freely extends the body.
  RULE_REQUIRED_SECTIONS = ["## Patterns", "## Anti-Patterns"].freeze

  # Skills (ADR 0003 / ADR 0010). Each Skill is a canonical body at skills/<name>/SKILL.md reached
  # through a thin Invocation Shim. Checked only for a bundle that ships a skills/ tree (the
  # SKILLS_DIR gate) so a minimal fixture bundle is unaffected — the same "only for a bundle that
  # ships them" stance as check_rules / check_guardrails. REQUIRED_SKILLS is a floor (the baseline
  # ships all 13 today); it grows as later issues add skills. The per-present-skill invariants apply
  # to EVERY skills/<name>/ dir, so those later skills are covered by construction — no rewrite.
  SKILLS_DIR = "skills"
  CLAUDE_COMMANDS_DIR = ".claude/commands"
  # The six lifecycle Skills (ADR 0006). Each MUST route host values through PROJECT.md, so each body
  # is asserted to reference the Project Config (the content-neutrality positive check in check_skills).
  LIFECYCLE_SKILLS = %w[assess devise invoke verify listen final].freeze
  # Floor: the skills the baseline is expected to ship. Grows as later issues add skills; the shape
  # check applies to every *present* skill regardless, so additions are covered by construction.
  # `ship` is the orchestrator (ADR 0005/0006), `scout` is the intake-pipeline sweep (ADR 0012),
  # `clip` is the intake pipeline's push front door (ADR 0015), and `create-skill` is the authoring
  # front door (ADR 0019): all belong in the floor but NOT in LIFECYCLE_SKILLS — none is a lifecycle
  # stage, so none is forced through the PROJECT.md-reference check (each body references PROJECT.md by
  # choice, not by that mandate).
  REQUIRED_SKILLS = (["distill"] + LIFECYCLE_SKILLS + ["ship", "scout", "clip", "create-skill", "follow", "restock"]).freeze

  # Content-neutrality (ADR 0003): a generic Skill body reads host values from PROJECT.md, so a
  # stack/domain proper noun in a body is leftover coupling the purely-structural checks cannot see.
  # This denylist is deliberately tight and unambiguous to avoid false positives on generic prose, and
  # is scoped to skills/<name>/SKILL.md only (docs/ may legitimately illustrate). Pure-alphabetic
  # tokens match on ASCII-letter word boundaries (so `rspec` matches the standalone word but not
  # "underspecified"); tokens with punctuation match as plain substrings (no benign word contains them).
  HOST_SPECIFIC_TOKENS = [
    "Searchkick", "Elasticsearch", "Pundit", "Devise", "Kamal", "SimpleCov",
    "strong_migrations", "Ransack", "Markaz", "admin_root_path", "SKIP_TITLE_REINDEX",
    "rubocop", "rspec", "brakeman", "bundler-audit", ".claude/rules/", "docs/rules/"
  ].freeze

  # Required PROJECT.md H2 sections (verbatim). This is the parity contract with PROJECT.md.
  # Deliberately a FLOOR, not an inventory: PROJECT.md ships more sections than these (Human Gates,
  # Intake Pipeline, Tool Roster). Those stay out so an already-vendored Host App whose PROJECT.md
  # predates one of them is not reddened by an additive change — each has a shipped default instead.
  REQUIRED_PROJECT_SECTIONS = [
    "## Quality Checks",
    "## Attribution & Model Declaration",
    "## Branch & PR Policy",
    "## Review Severity Framework",
    "## Lifecycle Host",
  ].freeze

  # Human-gate policy (ADR 0025). The settings are a Project Config value read through HumanGates,
  # which returns the shipped strict defaults when `## Human Gates` is absent (see the note above).
  # These Skill bodies act on a gate, so each must NAME the host value — the resident-default rule:
  # a body states the shipped default inline AND points at the override, so it can never hardcode a
  # policy a host overrode, and Copilot (which does not follow links) still receives the instruction.
  GATE_AWARE_SKILLS = %w[assess devise invoke ship final].freeze
  GATE_REFERENCE = "Human Gates"
  # The one merge value that literally expresses self-merge, and so the only one that earns the
  # policy-boundary message. Every other out-of-set value - `Required`, `optional`, a typo - is a
  # mistake, not a claim, and gets the generic allowed-values message instead of an accusation.
  SELF_MERGE_VALUE = "auto"

  # Branch-protection guardrails (ADR 0009). Checked only for a bundle that ships them — signalled by
  # the derived sidecar's presence — so minimal fixture bundles are unaffected.
  SIDECAR = ".githooks/protected-branches"
  GUARDRAIL_FILES = [
    ".githooks/pre-commit", ".githooks/pre-push", ".githooks/pre-merge-commit", ".githooks/pre-rebase",
    "bin/guard-protected-branch", "bin/install-git-hooks", "bin/protected-branches",
    ".claude/hooks/enforce-branch-creation.sh", ".claude/settings.json"
  ].freeze

  IMPORT_TOKEN = /(?:^|\s)@AGENTS\.md(?:\s|$)/.freeze
  # Markers are only recognized when alone on their own line — so prose that *describes* a marker
  # (e.g. inside a backtick span in documentation) is never mistaken for a real one.
  NATIVE_MARKER = /\A<!--\s*parity:native\s+source=AGENTS\.md\s*-->\z/.freeze
  RENDER_OPEN = /\A<!--\s*parity:render\s+source=AGENTS\.md\s*-->\z/.freeze
  RENDER_CLOSE = /\A<!--\s*parity:endrender\s*-->\z/.freeze
  # A markdown code fence: three or more backticks or tildes, plus an optional info string (```md).
  # Matched against the STRIPPED line, so a fence indented inside a list item is still recognized.
  FENCE_LINE = /\A(`{3,}|~{3,})(.*)\z/.freeze

  def initialize(root)
    @root = root
    @errors = []
  end

  def run
    check_canonical_exists
    check_import_adapters
    check_copilot_adapter
    check_rendered_regions
    check_project_sections
    check_human_gates
    check_rules
    check_skills
    check_guardrails
    check_guides
    check_links
    report
    @errors.empty? ? 0 : 1
  end

  private

  def path(rel) = File.join(@root, rel)
  def exist?(rel) = File.file?(path(rel))
  def read(rel) = File.read(path(rel), encoding: "UTF-8")
  def err(msg) = @errors << msg

  def check_canonical_exists
    if !exist?(CANONICAL)
      err("Canonical Source missing: #{CANONICAL} not found")
    elsif read(CANONICAL).strip.empty?
      err("Canonical Source empty: #{CANONICAL} has no content")
    end
  end

  def check_import_adapters
    IMPORT_ADAPTERS.each do |adapter|
      unless exist?(adapter)
        err("Import Adapter missing: #{adapter} not found")
        next
      end
      body = read(adapter)
      next if body.match?(IMPORT_TOKEN)

      # No `@AGENTS.md` import: allowed only for a native-capable adapter that declares native discovery
      # (a `parity:native source=AGENTS.md` marker) — the context.fileName / Antigravity-native path.
      if NATIVE_CAPABLE_ADAPTERS.include?(adapter)
        next if body.lines.any? { |l| l.strip.match?(NATIVE_MARKER) }

        err("Adapter #{adapter} neither imports the Canonical Source (`@#{CANONICAL}`) nor declares " \
            "native discovery (expected an `@#{CANONICAL}` line or a `parity:native source=#{CANONICAL}` marker)")
      else
        err("Import Adapter #{adapter} does not import the Canonical Source (expected an `@#{CANONICAL}` line)")
      end
    end
    # The import target itself must exist (a dangling `@AGENTS.md` is drift).
    err("Import target missing: adapters reference @#{CANONICAL} but #{CANONICAL} not found") unless exist?(CANONICAL)
  end

  def check_copilot_adapter
    unless exist?(COPILOT_ADAPTER)
      err("Copilot Adapter missing: #{COPILOT_ADAPTER} not found")
      return
    end
    marker_lines = read(COPILOT_ADAPTER).lines.map(&:strip)
    native = marker_lines.any? { |l| l.match?(NATIVE_MARKER) }
    render = marker_lines.any? { |l| l.match?(RENDER_OPEN) }
    unless native || render
      err("Copilot Adapter #{COPILOT_ADAPTER} has neither a `parity:native` marker nor a `parity:render` block")
    end
    # If it declares a render block, check_rendered_regions verifies the byte-match.
  end

  # Any file carrying a parity:render block must reproduce AGENTS.md byte-for-byte in that region.
  def check_rendered_regions
    return unless exist?(CANONICAL)

    canonical = read(CANONICAL)
    LINK_CHECKED.each do |rel|
      next unless exist?(rel)

      body = read(rel)
      lines = body.lines
      # DETECT markers on code-stripped lines, but CAPTURE from the original ones. Widening
      # LINK_CHECKED widened this scan too, so a doc that legitimately SHOWS a `parity:render` block
      # inside a fenced example would otherwise fail with a confusing "no endrender close". The
      # existing "alone on its own line" rule only defeats an inline backtick mention, not a fence.
      # strip_code preserves line count (a stripped fence line becomes a bare newline), so the indices
      # below address the same lines in both arrays.
      scan = strip_code(body).lines
      open_i = scan.index { |l| l.strip.match?(RENDER_OPEN) }
      next unless open_i

      close_i = scan[(open_i + 1)..].index { |l| l.strip.match?(RENDER_CLOSE) }
      if close_i.nil?
        err("Rendered region in #{rel} opens with `parity:render` but has no `parity:endrender` close")
        next
      end
      close_i += open_i + 1
      captured = lines[(open_i + 1)...close_i].join
      if captured != canonical
        err("Rendered region in #{rel} does not match #{CANONICAL} byte-for-byte (drift)")
      end
    end
  end

  def check_project_sections
    unless exist?(PROJECT_CONFIG)
      err("Project Config missing: #{PROJECT_CONFIG} not found")
      return
    end
    headings = read(PROJECT_CONFIG).lines.map(&:rstrip)
    REQUIRED_PROJECT_SECTIONS.each do |section|
      err("Project Config #{PROJECT_CONFIG} missing required section: `#{section}`") unless headings.include?(section)
    end
  end

  # Human-gate policy (ADR 0025). PROJECT.md declares which lifecycle pauses require a human; the
  # generic Skill bodies read it instead of hardcoding a policy. Two invariants, both value-level (the
  # per-body "does it NAME the value" invariant lives in check_skills, behind the skills/ gate):
  #   (1) MERGE IS NOT CONFIGURABLE - `required` is its only legal value, so no Host App can express
  #       self-merge. Declaring `auto` gets its own message because it is a policy boundary, not a
  #       typo. Any OTHER bad merge value - including a case slip like `Required` - is a typo, so it
  #       takes the generic message below: a capitalization mistake must never be reported as if the
  #       host had claimed the right to self-merge.
  #   (2) Any other out-of-set value is reported with the allowed set, never coerced to a default.
  # A PROJECT.md with no `## Human Gates` section parses to the shipped strict defaults and passes.
  def check_human_gates
    return unless exist?(PROJECT_CONFIG)

    gates = HumanGates.extract(read(PROJECT_CONFIG))
    self_merge = gates[:merge] == SELF_MERGE_VALUE

    if self_merge
      err("Human-gate policy: the merge gate is NOT configurable - #{PROJECT_CONFIG} declares " \
          "`merge: #{gates[:merge]}` but `#{HumanGates::DEFAULTS[:merge]}` is its only allowed value " \
          "(no Host App may express self-merge; a human always merges)")
    end

    HumanGates.invalid(gates).each do |key, value|
      next if key == :merge && self_merge # already reported above, with the specific message

      allowed = HumanGates::ALLOWED[key].map { |v| "`#{v}`" }.join(", ")
      err("Human-gate policy: #{PROJECT_CONFIG} declares an unknown value `#{value}` for " \
          "`#{key.to_s.tr('_', '-')}` - allowed values are #{allowed}")
    end
  end

  # Tier-1 Rules Layer (ADR 0004). Runs only when the bundle ships a rules/ tree, so a minimal bundle
  # without the Rules Layer is unaffected (the same gate stance as check_guardrails). Three invariants
  # per rule file: (1) it exists, (2) AGENTS.md references it (the Lean Core must be reachable from the
  # Canonical Source so every tool receives it), and (3) it declares each required section — presence
  # of the heading, not its content, so a host freely extends the body.
  def check_rules
    return unless Dir.exist?(path(RULES_DIR))

    agents = exist?(CANONICAL) ? read(CANONICAL) : ""
    REQUIRED_RULES.each do |rel|
      unless exist?(rel)
        err("Tier-1 rule missing: #{rel} not found")
        next
      end
      unless agents.include?(rel)
        err("Tier-1 rule #{rel} is not referenced by #{CANONICAL} (the Lean Core must be reachable from the Canonical Source)")
      end
      headings = read(rel).lines.map(&:rstrip)
      RULE_REQUIRED_SECTIONS.each do |section|
        err("Tier-1 rule #{rel} missing required section: `#{section}`") unless headings.include?(section)
      end
    end
  end

  # Skills Layer (ADR 0003 / ADR 0010). Runs only when the bundle ships a skills/ tree, so a minimal
  # bundle is unaffected (the same gate stance as check_rules). Two tiers:
  #   (1) Floor  — every REQUIRED_SKILLS entry has skills/<name>/SKILL.md (the expected skill ships).
  #   (2) Shape  — EVERY present skills/<name>/ dir must have: a SKILL.md, that SKILL.md carrying YAML
  #                frontmatter with a `name:` key, a paired Claude shim .claude/commands/<name>.md,
  #                that shim referencing the canonical body (so a hollow stub can't pass), and a
  #                reference to skills/<name>/SKILL.md in AGENTS.md (the documented invocation the
  #                native-discovery tools reach). Applying the shape to every present dir is what makes
  #                the check cover skills a later issue adds without editing this list.
  #   (3) Neutrality — no HOST_SPECIFIC_TOKENS in any present body, and every LIFECYCLE_SKILLS body
  #                references PROJECT.md. This is the one content check (ADR 0003): the structural
  #                invariants can't see a leftover stack/domain token or a hardcoded quality check.
  def check_skills
    return unless Dir.exist?(path(SKILLS_DIR))

    agents = exist?(CANONICAL) ? read(CANONICAL) : ""

    REQUIRED_SKILLS.each do |name|
      err("Required skill missing: #{SKILLS_DIR}/#{name}/SKILL.md not found") unless exist?("#{SKILLS_DIR}/#{name}/SKILL.md")
    end

    present_skills.each do |name|
      body_rel = "#{SKILLS_DIR}/#{name}/SKILL.md"
      unless exist?(body_rel)
        err("Skill #{name} missing its canonical body: #{body_rel} not found")
        next
      end
      body = read(body_rel)
      err("Skill #{name}: #{body_rel} lacks YAML frontmatter with a `name:` key") unless frontmatter_name?(body)

      shim_rel = "#{CLAUDE_COMMANDS_DIR}/#{name}.md"
      if !exist?(shim_rel)
        err("Skill #{name} missing its Claude Invocation Shim: #{shim_rel} not found")
      elsif !read(shim_rel).include?(body_rel)
        err("Claude Invocation Shim #{shim_rel} does not reference its canonical body (expected `#{body_rel}`)")
      end

      unless agents.include?(body_rel)
        err("Skill #{name} is not referenced by #{CANONICAL} (the documented invocation must be reachable from the Canonical Source)")
      end

      # Content-neutrality: no host-specific token in ANY Skill body (structural checks can't see it) …
      HOST_SPECIFIC_TOKENS.each do |token|
        next unless host_token?(body, token)

        err("Skill #{name}: #{body_rel} contains host-specific token `#{token}` (a generic Skill body " \
            "must read host values from #{PROJECT_CONFIG}, not name a stack/domain)")
      end

      # … and every lifecycle Skill must route its host values through the Project Config.
      if LIFECYCLE_SKILLS.include?(name) && !body.include?(PROJECT_CONFIG)
        err("Lifecycle Skill #{name}: #{body_rel} does not reference #{PROJECT_CONFIG} (it must read " \
            "quality checks / attribution / severities / lifecycle host from Project Config, not hardcode them)")
      end

      # … and every gate-aware Skill must NAME the Human Gates host value (ADR 0025). This verifies
      # the REFERENCE, not the prose's semantic agreement with the setting - see the ADR's limits.
      if GATE_AWARE_SKILLS.include?(name) && !body.include?(GATE_REFERENCE)
        err("Gate-aware Skill #{name}: #{body_rel} does not name the `#{GATE_REFERENCE}` host value " \
            "(a body that acts on a human gate must state the shipped default inline AND read the " \
            "override from #{PROJECT_CONFIG} -> #{GATE_REFERENCE}, never hardcode a gate policy)")
      end
    end
  end

  # True when `token` appears in `body` as a host-specific mention. Pure-alphabetic tokens require
  # ASCII-letter word boundaries (so `rspec` matches the standalone word but not "underspecified");
  # tokens carrying punctuation (paths, `bundler-audit`, `admin_root_path`) match as plain substrings.
  def host_token?(body, token)
    if token.match?(/\A[A-Za-z]+\z/)
      body.match?(/(?<![A-Za-z])#{Regexp.escape(token)}(?![A-Za-z])/)
    else
      body.include?(token)
    end
  end

  # Names of every skills/<name>/ subdirectory that actually ships a body dir (ignores stray files).
  def present_skills
    Dir.children(path(SKILLS_DIR))
       .select { |c| Dir.exist?(File.join(path(SKILLS_DIR), c)) }
       .sort
  end

  # True when `content` opens with a YAML frontmatter block (--- … ---) carrying a non-empty `name:`.
  def frontmatter_name?(content)
    lines = content.lines
    first = lines.index { |l| !l.strip.empty? }
    return false if first.nil? || lines[first].strip != "---"

    close = lines[(first + 1)..].index { |l| l.strip == "---" }
    return false if close.nil?

    lines[(first + 1)...(first + 1 + close)].any? { |l| l.match?(/\Aname:\s*\S/) }
  end

  # Branch-protection guardrails (ADR 0009). Runs only when the derived sidecar is present, so a
  # minimal bundle without guardrails is unaffected. Two invariants: (1) the guardrail files exist,
  # and (2) the committed sidecar equals the list derived from PROJECT.md — closing the staleness
  # hole that a generated-then-committed artifact would otherwise open.
  def check_guardrails
    return unless exist?(SIDECAR)

    GUARDRAIL_FILES.each do |f|
      err("Guardrail file missing: #{f} not found") unless exist?(f)
    end

    unless exist?(PROJECT_CONFIG)
      err("Guardrails present but #{PROJECT_CONFIG} is missing (cannot verify the protected-branch list)")
      return
    end

    derived = ProtectedBranches.from_file(path(PROJECT_CONFIG))
    # Read the sidecar the same way the guards do (skip blank + `#` comment lines) so a hand-added
    # comment never reads as drift — the machine-generated sidecar has none, but the three readers
    # must stay consistent.
    committed = read(SIDECAR).lines.map(&:strip).reject { |l| l.empty? || l.start_with?("#") }
    if derived != committed
      err("Protected-branch sidecar drift: #{SIDECAR} has #{committed.inspect} but PROJECT.md derives " \
          "#{derived.inspect} - run bin/install-git-hooks to regenerate it")
    end
  end

  # Usage guides (issue #11). Runs only when the bundle ships a docs/guides/ tree, so a minimal bundle
  # is unaffected (the same gate stance as check_rules / check_skills). One host-safe invariant per
  # required guide: it exists (is shipped). Its internal links are resolved by check_links (each guide
  # is in LINK_CHECKED). Reachability is intentionally not asserted against README (see REQUIRED_GUIDES).
  def check_guides
    return unless Dir.exist?(path(GUIDES_DIR))

    REQUIRED_GUIDES.each do |rel|
      err("Required guide missing: #{rel} not found") unless exist?(rel)
    end
  end

  # Every repo-relative markdown link in the checked files must resolve to an existing path.
  # Skips external (http/https/mailto) and bare-anchor (#...) links, and — via strip_code — any link
  # that is an ILLUSTRATION rather than a reference (inside a fenced block or an inline-code span).
  def check_links
    link_re = /\[[^\]]*\]\(([^)]+)\)/
    LINK_CHECKED.each do |rel|
      next unless exist?(rel)

      dir = File.dirname(path(rel))
      strip_code(read(rel)).scan(link_re).each do |(target)|
        target = target.strip
        next if target.empty?
        next if target.start_with?("http://", "https://", "mailto:", "#")

        target = target.split("#", 2).first # drop any #anchor fragment
        next if target.nil? || target.empty?

        resolved = File.expand_path(target, dir)
        unless File.exist?(resolved)
          err("Dead link in #{rel}: `#{target}` does not resolve")
        end
      end
    end
  end

  # Returns `content` with every fenced code block and inline-code span blanked out, so a markdown
  # link that exists only as an ILLUSTRATION is never reported dead. A fenced Context Map naming
  # `./src/ordering/CONTEXT.md`, or prose documenting the `[text](path)` convention itself, points at
  # a hypothetical host repo — not this one. Without this, widening LINK_CHECKED (issue #96) would
  # redden real files and teach every author that examples are forbidden.
  #
  # Line-based, no regex lookbehind (stdlib-only, rules/scripting.md). Two passes:
  #   (1) Fences — ``` or ~~~, three or more, with an optional info string (```md). A fence is
  #       stripped ONLY when a matching closer is found. An UNTERMINATED fence is deliberately NOT
  #       treated as a fence: swallowing the rest of the file (the renderer's semantics) would
  #       silently switch link checking off from that point on — a false green, the worst outcome for
  #       a checker. The stray delimiter line is dropped and every later link is still resolved.
  #   (2) Inline spans — a backtick run of length N opens a span closed by the next run of EXACTLY N
  #       (so a double-backtick span may hold a literal backtick). Only the span is blanked, never the
  #       whole line, so `[t](p)` and [real](./x.md) sharing a line still resolves the real link.
  def strip_code(content)
    lines = content.lines
    out = Array.new(lines.length)
    i = 0
    while i < lines.length
      opener = fence_delimiter(lines[i])
      if opener.nil?
        out[i] = strip_inline_code(lines[i])
        i += 1
      elsif (close = closing_fence_index(lines, i + 1, opener))
        (i..close).each { |n| out[n] = "\n" }
        i = close + 1
      else
        out[i] = "\n" # unterminated: a stray delimiter, not a block — keep checking what follows
        i += 1
      end
    end
    out.join
  end

  # The delimiter run of a fence line (``` / ~~~~ / ```md), or nil when the line is not a fence.
  def fence_delimiter(line)
    m = FENCE_LINE.match(line.strip)
    m && m[1]
  end

  # Index of the line that closes the fence opened by `opener`, or nil. A closer uses the SAME fence
  # character, is at least as long, and carries no info string (CommonMark) — so a ~~~ inside a ```
  # block, or a nested longer fence, does not close it early.
  def closing_fence_index(lines, from, opener)
    (from...lines.length).find do |n|
      m = FENCE_LINE.match(lines[n].strip)
      m && m[1][0] == opener[0] && m[1].length >= opener.length && m[2].strip.empty?
    end
  end

  # Blanks each inline-code span in `line`, preserving everything outside it (see strip_code note 2).
  def strip_inline_code(line)
    out = +""
    i = 0
    while i < line.length
      if line[i] != "`"
        out << line[i]
        i += 1
        next
      end

      run = backtick_run(line, i)
      close = closing_backtick_index(line, i + run, run)
      if close.nil?
        out << line[i, run] # an unpaired run is literal text, not a span opener
        i += run
      else
        out << " " * (close + run - i) # blank the span, delimiters included; keep the line's shape
        i = close + run
      end
    end
    out
  end

  # Length of the unbroken backtick run starting at `from`.
  def backtick_run(line, from)
    n = 0
    n += 1 while line[from + n] == "`"
    n
  end

  # Index where the next backtick run of EXACTLY `run` backticks begins at or after `from`, or nil.
  def closing_backtick_index(line, from, run)
    i = from
    while i < line.length
      if line[i] == "`"
        len = backtick_run(line, i)
        return i if len == run

        i += len
      else
        i += 1
      end
    end
    nil
  end

  def report
    if @errors.empty?
      skills = Dir.exist?(path(SKILLS_DIR)) ? present_skills.length : 0
      puts "parity_check: OK - Canonical Source, #{IMPORT_ADAPTERS.length + 1} Adapters, Project Config, " \
           "#{skills} Skill#{'s' if skills != 1}, and links all resolve."
    else
      puts "parity_check: FAILED (#{@errors.length} problem#{'s' if @errors.length != 1})"
      @errors.each { |e| puts "  - #{e}" }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = "."
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby scripts/parity_check.rb [--root DIR]"
    opts.on("--root DIR", "Directory to check (default: .)") { |v| root = v }
  end.parse!(ARGV)

  exit ParityCheck.new(root).run
end
