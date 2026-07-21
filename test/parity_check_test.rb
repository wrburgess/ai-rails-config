# frozen_string_literal: true

# Self-test for scripts/parity_check.rb. A checker with no test is a false green: these fixtures
# prove it passes a valid bundle AND fails correctly on each kind of drift. Stdlib only (minitest,
# tmpdir, fileutils, stringio ship with Ruby) — no bundler, mirroring ADR 0008.
#
# Run: ruby test/parity_check_test.rb

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
require_relative "../scripts/parity_check"

class ParityCheckTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/parity_check.rb", __dir__)

  # Writes a valid Generic-Baseline-shaped bundle into `dir`. `agents:` lets a test supply
  # link-free canonical content (needed by the render fixture, whose copy lands in .github/).
  def build_baseline(dir, agents: "# Canonical\n\nSee [config](PROJECT.md).\n")
    File.write(File.join(dir, "AGENTS.md"), agents)
    File.write(File.join(dir, "CLAUDE.md"), "@AGENTS.md\n\nClaude-only notes.\n")
    File.write(File.join(dir, "GEMINI.md"), "@AGENTS.md\n")
    FileUtils.mkdir_p(File.join(dir, ".github"))
    File.write(
      File.join(dir, ".github/copilot-instructions.md"),
      "<!-- parity:native source=AGENTS.md -->\n\n[canonical](../AGENTS.md)\n"
    )
    File.write(File.join(dir, "PROJECT.md"), <<~MD)
      # Project Config
      ## Quality Checks
      ## Attribution & Model Declaration
      ## Branch & PR Policy
      ## Review Severity Framework
      ## Lifecycle Host
    MD
  end

  # Runs the checker in-process and returns [exit_code, stdout].
  def run_check(dir)
    out = StringIO.new
    orig = $stdout
    $stdout = out
    code = ParityCheck.new(dir).run
    [code, out.string]
  ensure
    $stdout = orig
  end

  def with_bundle
    Dir.mktmpdir do |dir|
      build_baseline(dir)
      yield dir
    end
  end

  # Adds the branch-protection guardrails (ADR 0009) to a baseline `dir`: the derived sidecar (whose
  # presence activates check_guardrails), the guardrail files, and a PROJECT.md whose Branch & PR
  # Policy section authors `branches`. `sidecar` defaults to matching PROJECT.md (no drift).
  def add_guardrails(dir, branches: %w[main master develop], sidecar: nil)
    sidecar ||= branches
    FileUtils.mkdir_p(File.join(dir, ".githooks"))
    FileUtils.mkdir_p(File.join(dir, "bin"))
    FileUtils.mkdir_p(File.join(dir, ".claude/hooks"))
    ParityCheck::GUARDRAIL_FILES.each do |f|
      FileUtils.mkdir_p(File.join(dir, File.dirname(f)))
      File.write(File.join(dir, f), "stub\n")
    end
    File.write(File.join(dir, ParityCheck::SIDECAR), sidecar.map { |b| "#{b}\n" }.join)
    File.write(File.join(dir, "PROJECT.md"), <<~MD)
      # Project Config
      ## Quality Checks
      ## Attribution & Model Declaration
      ## Branch & PR Policy
      - **Protected branches:** #{branches.map { |b| "`#{b}`" }.join(', ')} — authored source.
      ## Review Severity Framework
      ## Lifecycle Host
    MD
  end

  # Writes the six Tier-1 Lean Core rule files (each with the required sections) into `dir` and adds
  # their references to AGENTS.md so check_rules' "referenced by AGENTS.md" invariant holds. Mirrors
  # how add_guardrails augments a baseline. Individual failure tests mutate one file / AGENTS.md
  # afterward.
  def add_rules(dir)
    FileUtils.mkdir_p(File.join(dir, "rules"))
    ParityCheck::REQUIRED_RULES.each do |rel|
      File.write(File.join(dir, rel), <<~MD)
        # Rule

        ## Patterns

        - Prefer the framework's built-ins.

        ## Anti-Patterns

        - **Never** do the bad thing - because it breaks.
      MD
    end
    # Make the Lean Core reachable from the Canonical Source (backticked paths, not markdown links,
    # so the link check is unaffected while check_rules' substring reference still matches).
    agents = File.read(File.join(dir, "AGENTS.md"))
    refs = ParityCheck::REQUIRED_RULES.map { |r| "`#{r}`" }.join(" ")
    File.write(File.join(dir, "AGENTS.md"), "#{agents}\n## Rules Layer\n\n#{refs}\n")
  end

  # Writes a valid Skills Layer into `dir`: EVERY REQUIRED_SKILLS skill (so the floor passes) as a
  # neutral, PROJECT.md-referencing canonical body + paired Claude shim + AGENTS.md reference, so the
  # floor, the per-skill shape, AND the content-neutrality checks all pass. `extra:` writes one more
  # (non-required) named skill on top. Individual failure tests mutate one skill's files afterward.
  def add_skills(dir, extra: nil)
    (ParityCheck::REQUIRED_SKILLS + [extra]).compact.each { |name| write_skill(dir, name) }
  end

  # Writes one skill: body + shim + AGENTS.md reference. The default body carries `name:` frontmatter,
  # references PROJECT.md (satisfying the lifecycle-Skill positive check), names the `Human Gates` host
  # value (satisfying the gate-aware check for assess/devise/invoke/ship/final — ADR 0025), names the
  # `*Reviewer*` host value (satisfying the reviewer-aware check for verify/listen/final/ship —
  # ADR 0026), and names no host-specific token. `body:` overrides it (used by the neutrality failure tests); `shim:`
  # overrides the shim the same way (used by the shim-frontmatter tests). The default shim is
  # deliberately fence-less, so every pre-existing test also stands as a standing assertion that
  # absent shim frontmatter stays permitted.
  def write_skill(dir, name, body: nil, shim: nil)
    body_rel = "skills/#{name}/SKILL.md"
    shim_rel = ".claude/commands/#{name}.md"
    FileUtils.mkdir_p(File.join(dir, "skills/#{name}"))
    FileUtils.mkdir_p(File.join(dir, ".claude/commands"))
    File.write(File.join(dir, body_rel), body || <<~MD)
      ---
      name: #{name}
      description: A portable skill.
      ---

      Skill body. Reads host values from PROJECT.md, including the Human Gates policy
      and the *Reviewer* declaration.
    MD
    # The shim's relative link contains body_rel as a substring, satisfying the reference invariant.
    File.write(File.join(dir, shim_rel), shim || "Read and follow [`#{body_rel}`](../../#{body_rel}).\n")
    agents = File.read(File.join(dir, "AGENTS.md"))
    File.write(File.join(dir, "AGENTS.md"), "#{agents}\n`#{body_rel}`\n")
  end

  # Writes a valid Usage-guides surface into `dir`: every REQUIRED_GUIDES file (with a resolving link,
  # so check_links stays green). The guide lands under docs/guides/, whose presence activates
  # check_guides. A README.md that links each guide is written too — not required by check_guides
  # (reachability is not anchored to README; see the REQUIRED_GUIDES note) but it exercises check_links
  # on README (which is in LINK_CHECKED). Individual failure tests mutate one file afterward. Mirrors
  # add_rules / add_skills.
  def add_guides(dir)
    FileUtils.mkdir_p(File.join(dir, "docs/guides"))
    ParityCheck::REQUIRED_GUIDES.each do |rel|
      FileUtils.mkdir_p(File.join(dir, File.dirname(rel)))
      # A resolving relative link back to the Canonical Source (../../AGENTS.md from docs/guides/).
      File.write(File.join(dir, rel), "# Guide\n\nSee [canonical](../../AGENTS.md).\n")
    end
    refs = ParityCheck::REQUIRED_GUIDES.map { |g| "[guide](#{g})" }.join(" ")
    File.write(File.join(dir, "README.md"), "# Host\n\n#{refs}\n")
  end

  # --- happy paths -------------------------------------------------------------------------------

  def test_valid_bundle_passes
    with_bundle do |dir|
      code, out = run_check(dir)
      assert_equal 0, code, out
      assert_match(/OK/, out)
    end
  end

  def test_matching_render_adapter_passes
    Dir.mktmpdir do |dir|
      agents = "# Canonical\n\nNo markdown links here.\n"
      build_baseline(dir, agents: agents)
      File.write(
        File.join(dir, ".github/copilot-instructions.md"),
        "<!-- parity:render source=AGENTS.md -->\n#{agents}<!-- parity:endrender -->\n"
      )
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_valid_guardrails_pass
    with_bundle do |dir|
      add_guardrails(dir)
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_guardrails_absent_are_not_checked
    # No sidecar → check_guardrails is a no-op, so a bundle without guardrails still passes.
    with_bundle do |dir|
      refute File.exist?(File.join(dir, ParityCheck::SIDECAR))
      code, = run_check(dir)
      assert_equal 0, code
    end
  end

  def test_sidecar_comment_and_blank_lines_are_not_drift
    with_bundle do |dir|
      add_guardrails(dir, branches: %w[main master develop])
      # A hand-added comment / blank line must be tolerated (read the same way the guards do).
      File.write(File.join(dir, ParityCheck::SIDECAR), "# protected branches\n\nmain\nmaster\ndevelop\n")
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  # --- failure paths -----------------------------------------------------------------------------

  def test_sidecar_drift_fails
    with_bundle do |dir|
      add_guardrails(dir, branches: %w[main master develop], sidecar: %w[main master]) # stale sidecar
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/sidecar drift/i, out)
    end
  end

  def test_missing_guardrail_file_fails
    with_bundle do |dir|
      add_guardrails(dir)
      File.delete(File.join(dir, "bin/guard-protected-branch"))
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/Guardrail file missing/, out)
    end
  end

  def test_missing_import_fails
    with_bundle do |dir|
      File.write(File.join(dir, "CLAUDE.md"), "no import token here\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/CLAUDE\.md does not import/, out)
    end
  end

  def test_gemini_native_discovery_marker_passes
    # Issue #56: Antigravity CLI reads AGENTS.md natively (v1.20.3) and a host may set
    # context.fileName -> AGENTS.md, so a Gemini adapter may resolve via a `parity:native` marker
    # INSTEAD of an @import. That must pass parity (the check would previously false-fail it).
    with_bundle do |dir|
      File.write(File.join(dir, "GEMINI.md"), "<!-- parity:native source=AGENTS.md -->\n\nGemini-only notes.\n")
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_gemini_neither_import_nor_native_fails
    # A Gemini adapter with neither an @import nor a native-discovery marker resolves to nothing.
    with_bundle do |dir|
      File.write(File.join(dir, "GEMINI.md"), "just prose, no import and no marker\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/neither imports the Canonical Source .* nor declares native discovery/, out)
    end
  end

  def test_claude_native_marker_does_not_satisfy_import
    # CLAUDE.md is NOT native-capable (Claude Code has no native AGENTS.md discovery): a parity:native
    # marker must NOT rescue it — only the @import resolves. Guards the native path as Gemini-only.
    with_bundle do |dir|
      File.write(File.join(dir, "CLAUDE.md"), "<!-- parity:native source=AGENTS.md -->\n\nClaude-only notes.\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/CLAUDE\.md does not import/, out)
    end
  end

  def test_dangling_import_target_fails
    with_bundle do |dir|
      File.delete(File.join(dir, "AGENTS.md"))
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/AGENTS\.md/, out)
      assert_match(/not found/, out)
    end
  end

  def test_missing_project_section_fails
    with_bundle do |dir|
      project = File.read(File.join(dir, "PROJECT.md")).sub("## Review Severity Framework\n", "")
      File.write(File.join(dir, "PROJECT.md"), project)
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/Review Severity Framework/, out)
    end
  end

  def test_dead_link_fails
    with_bundle do |dir|
      File.write(File.join(dir, "AGENTS.md"), "# Canonical\n\n[gone](docs/nope.md)\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/Dead link/, out)
    end
  end

  def test_render_drift_fails
    Dir.mktmpdir do |dir|
      agents = "# Canonical\n\nNo links.\n"
      build_baseline(dir, agents: agents)
      File.write(
        File.join(dir, ".github/copilot-instructions.md"),
        "<!-- parity:render source=AGENTS.md -->\n# Canonical\n\nDRIFTED.\n<!-- parity:endrender -->\n"
      )
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/byte-for-byte/, out)
    end
  end

  def test_render_marker_inside_a_fenced_example_is_not_a_real_marker
    # Widening LINK_CHECKED (issue #96) widened check_rendered_regions to the same ~96 files, so a doc
    # that legitimately DOCUMENTS the render mode by showing the marker pair inside a fence would be
    # read as a real, unterminated render block. The "alone on its own line" rule defeats an inline
    # backtick mention but not a fence. Here the fenced example shows only the OPEN marker: under the
    # old behavior that is a `parity:render` with no close, and the bundle fails on its own docs.
    with_bundle do |dir|
      FileUtils.mkdir_p(File.join(dir, "docs/guides"))
      File.write(File.join(dir, "docs/guides/usage.md"), <<~MD)
        # Guide

        Set the adapter to render mode by opening the block with:

        ```md
        <!-- parity:render source=AGENTS.md -->
        ```

        See [canonical](../../AGENTS.md).
      MD
      code, out = run_check(dir)
      assert_equal 0, code, out
      refute_match(/endrender/, out, "a fenced example was mistaken for a real render block")
    end
  end

  def test_matching_render_block_whose_canonical_contains_a_fence_passes
    # THE distinguishing test for "detect on stripped lines, CAPTURE from the original ones".
    # A drifted fixture cannot prove it — that mismatches under either implementation. Only a MATCHING
    # block whose canonical contains code can: if the region were captured from the stripped lines, the
    # fence and the inline span would come back blanked, the comparison would fail, and the bundle
    # would report drift against a byte-identical copy. This is reachable, not hypothetical — the real
    # AGENTS.md ships a fenced block (the quality-gate command), so any render-mode host hits it.
    Dir.mktmpdir do |dir|
      agents = <<~MD
        # Canonical

        Run the gate, and note the `inline span` here:

        ```sh
        ruby scripts/parity_check.rb
        ```

        Trailing prose.
      MD
      build_baseline(dir, agents: agents)
      File.write(
        File.join(dir, ".github/copilot-instructions.md"),
        "<!-- parity:render source=AGENTS.md -->\n#{agents}<!-- parity:endrender -->\n"
      )
      code, out = run_check(dir)
      assert_equal 0, code, out
      refute_match(/byte-for-byte/, out, "a byte-identical render block was reported as drift")
    end
  end

  def test_real_render_block_still_compared_byte_for_byte_when_the_file_also_has_a_fenced_example
    # The other half: detection is code-aware, but the CAPTURE must still read the file's real bytes.
    # A file carrying BOTH a fenced illustration and a genuine drifted render block must still fail —
    # proving the fence skip did not shift the captured region or disable the comparison.
    Dir.mktmpdir do |dir|
      agents = "# Canonical\n\nNo links.\n"
      build_baseline(dir, agents: agents)
      File.write(File.join(dir, ".github/copilot-instructions.md"), <<~MD)
        ```md
        <!-- parity:render source=AGENTS.md -->
        ```

        <!-- parity:render source=AGENTS.md -->
        # Canonical

        DRIFTED.
        <!-- parity:endrender -->
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/byte-for-byte/, out)
    end
  end

  def test_copilot_adapter_without_marker_fails
    with_bundle do |dir|
      File.write(File.join(dir, ".github/copilot-instructions.md"), "just prose, no marker\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/neither a `parity:native` marker nor a `parity:render`/, out)
    end
  end

  def test_missing_copilot_adapter_fails
    with_bundle do |dir|
      File.delete(File.join(dir, ".github/copilot-instructions.md"))
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/Copilot Adapter missing/, out)
    end
  end

  # --- Rules Layer (ADR 0004) --------------------------------------------------------------------

  def test_valid_rules_pass
    with_bundle do |dir|
      add_rules(dir)
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_rules_absent_are_not_checked
    # No rules/ dir -> check_rules is a no-op, so a bundle without the Rules Layer still passes.
    with_bundle do |dir|
      refute Dir.exist?(File.join(dir, "rules"))
      code, = run_check(dir)
      assert_equal 0, code
    end
  end

  def test_rule_missing_anti_patterns_section_fails
    # The acceptance-criterion guard: a Tier-1 rule without its Anti-Patterns section reddens.
    with_bundle do |dir|
      add_rules(dir)
      File.write(File.join(dir, "rules/testing.md"), "# Rule\n\n## Patterns\n\n- only patterns\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/Anti-Patterns/, out)
    end
  end

  def test_rule_missing_patterns_section_fails
    with_bundle do |dir|
      add_rules(dir)
      File.write(File.join(dir, "rules/testing.md"), "# Rule\n\n## Anti-Patterns\n\n- **Never** X.\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/missing required section: `## Patterns`/, out)
    end
  end

  def test_missing_required_rule_file_fails
    with_bundle do |dir|
      add_rules(dir)
      File.delete(File.join(dir, "rules/security.md")) # rules/ present, one required file gone
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Tier-1 rule missing: rules/security\.md}, out)
    end
  end

  def test_missing_skills_rule_file_fails
    # `rules/skills.md` is part of the REQUIRED_RULES floor (issue #25): dropping it reddens too. This
    # pins the skill-authoring rule into the floor so a future edit can't silently drop it.
    with_bundle do |dir|
      add_rules(dir)
      File.delete(File.join(dir, "rules/skills.md"))
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Tier-1 rule missing: rules/skills\.md}, out)
    end
  end

  def test_rule_not_referenced_by_agents_fails
    with_bundle do |dir|
      add_rules(dir)
      # Rewrite AGENTS.md to a valid, link-resolving body that references none of the rules.
      File.write(File.join(dir, "AGENTS.md"), "# Canonical\n\nSee [config](PROJECT.md).\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/not referenced by AGENTS\.md/, out)
    end
  end

  # --- Skills Layer (ADR 0003 / ADR 0010) --------------------------------------------------------

  def test_valid_skills_pass
    with_bundle do |dir|
      add_skills(dir)
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_skills_absent_are_not_checked
    # No skills/ dir -> check_skills is a no-op, so a bundle without any Skill still passes.
    with_bundle do |dir|
      refute Dir.exist?(File.join(dir, "skills"))
      code, = run_check(dir)
      assert_equal 0, code
    end
  end

  def test_skill_missing_body_fails
    with_bundle do |dir|
      add_skills(dir)
      File.delete(File.join(dir, "skills/distill/SKILL.md")) # dir present, body gone
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{missing its canonical body: skills/distill/SKILL\.md}, out)
    end
  end

  def test_skill_missing_claude_shim_fails
    with_bundle do |dir|
      add_skills(dir)
      File.delete(File.join(dir, ".claude/commands/distill.md"))
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/missing its Claude Invocation Shim/, out)
    end
  end

  def test_skill_shim_not_referencing_body_fails
    # A shim that exists but doesn't point at the canonical body is a hollow stub — must redden.
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, ".claude/commands/distill.md"), "No pointer here.\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/does not reference its canonical body/, out)
    end
  end

  def test_skill_body_missing_frontmatter_name_fails
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, "skills/distill/SKILL.md"), "# No frontmatter\n\nBody.\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/lacks YAML frontmatter with a `name:` key/, out)
    end
  end

  # --- Frontmatter validity (issue #103) -------------------------------------------------------
  # The checker PARSES both frontmattered surfaces rather than regexing them. A regex proves the text
  # looks parseable while every consuming tool needs it to be parseable, and that gap ships green.
  # False red is the live risk here (a too-strict rule blocks every PR in this repo and in any
  # vendoring Host App), so the permissive boundary is pinned first and explicitly.

  def test_skill_frontmatter_with_quoted_colon_passes
    # The case authors will legitimately write. A check that reddens a QUOTED colon would be worse
    # than no check at all, so this happy path is the guard on the whole feature's usefulness.
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, "skills/distill/SKILL.md"), <<~MD)
        ---
        name: distill
        description: "Stage 3: grill a plan, one question at a time."
        ---

        Body.
      MD
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_shim_without_frontmatter_passes
    # The shim rule is deliberately SOFTER than the body rule: genuinely absent frontmatter stays
    # allowed, because the bundle never required it and reddening a Host App for a style it was never
    # asked to adopt is a false red. This pins that boundary after the :unterminated tightening below.
    with_bundle do |dir|
      add_skills(dir)
      File.write(
        File.join(dir, ".claude/commands/distill.md"),
        "Read and follow [`skills/distill/SKILL.md`](../../skills/distill/SKILL.md).\n"
      )
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_skill_frontmatter_unparseable_yaml_fails
    # The exact defect that shipped green on PR #102: an unquoted `": "` inside a prose description.
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, "skills/distill/SKILL.md"), <<~MD)
        ---
        name: distill
        description: Stage 3: grill a plan, one question at a time.
        ---

        Body.
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/unparseable YAML frontmatter/, out)
    end
  end

  def test_skill_frontmatter_error_reports_the_file_line
    # Regression guard for the off-by-fence trap. Psych numbers lines within the string it is handed,
    # so parsing the fence-stripped block alone reports line 2 for what is file line 3 — sending the
    # author to the wrong line. Without this test the padding could regress silently while every other
    # frontmatter test stayed green, since they assert only the message text.
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, "skills/distill/SKILL.md"), <<~MD)
        ---
        name: distill
        description: Stage 3: grill a plan.
        ---

        Body.
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      # The break is on file line 3. Line 2 would mean the padding was dropped.
      assert_match(/line 3/, out)
      refute_match(/line 2/, out)
    end
  end

  def test_skill_body_unclosed_frontmatter_fails
    # An opened-but-never-closed block. This is not a false green on the body path (it already exits
    # 1), but the OLD message told the author their `name:` key was missing while it sat on line 2.
    # The refute is the point of this test: without it, it would pass against that misleading string.
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, "skills/distill/SKILL.md"), <<~MD)
        ---
        name: distill
        description: A portable skill.

        Body with no closing fence.
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/opens a frontmatter block with `---` but never closes it/, out)
      refute_match(/lacks YAML frontmatter with a `name:` key/, out)
    end
  end

  def test_skill_frontmatter_non_mapping_root_fails
    # A list root parses CLEANLY — no exception — so only the explicit Hash assertion catches it.
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, "skills/distill/SKILL.md"), "---\n- one\n- two\n---\n\nBody.\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/not a key.value mapping \(parsed as a YAML Array\)/, out)
    end
  end

  def test_skill_frontmatter_empty_block_fails
    # `---\n---` parses to nil, which would read as "parsed as NilClass" if the message passed the
    # class name straight through. Assert it names an empty block instead.
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, "skills/distill/SKILL.md"), "---\n---\n\nBody.\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/not a key.value mapping \(parsed as an empty block\)/, out)
      refute_match(/NilClass/, out)
    end
  end

  def test_skill_frontmatter_missing_description_fails
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, "skills/distill/SKILL.md"), "---\nname: distill\n---\n\nBody.\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/lacks a non-empty `description:` in its frontmatter/, out)
    end
  end

  def test_skill_frontmatter_whitespace_only_description_fails
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, "skills/distill/SKILL.md"), <<~MD)
        ---
        name: distill
        description: "   "
        ---

        Body.
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/lacks a non-empty `description:` in its frontmatter/, out)
    end
  end

  def test_skill_frontmatter_whitespace_only_name_fails
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, "skills/distill/SKILL.md"), <<~MD)
        ---
        name: "   "
        description: A portable skill.
        ---

        Body.
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/lacks YAML frontmatter with a `name:` key/, out)
    end
  end

  def test_skill_frontmatter_non_string_name_fails
    # `name: 123` parses to an Integer, so a truthiness check would let it through.
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, "skills/distill/SKILL.md"), <<~MD)
        ---
        name: 123
        description: A portable skill.
        ---

        Body.
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/lacks YAML frontmatter with a `name:` key/, out)
    end
  end

  def test_skill_name_mismatching_directory_fails
    # The identity assertion, free once the parse has happened: a body whose frontmatter name
    # disagrees with its directory no longer describes the same Skill as its shim. The rename work
    # (#73) leaned on this agreement with no gate behind it.
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, "skills/distill/SKILL.md"), <<~MD)
        ---
        name: wrong
        description: A portable skill.
        ---

        Body.
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{declares `name: wrong` but lives in skills/distill/}, out)
    end
  end

  def test_shim_unparseable_frontmatter_fails
    # For Claude Code the shim IS the invocation path, so a broken one is a dead slash command —
    # the surface with more consequence and, until now, no frontmatter assertion at all.
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, ".claude/commands/distill.md"), <<~MD)
        ---
        description: Stage 3: grill a plan.
        ---

        Read and follow [`skills/distill/SKILL.md`](../../skills/distill/SKILL.md).
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Claude Invocation Shim \.claude/commands/distill\.md has unparseable YAML frontmatter}, out)
    end
  end

  def test_shim_unclosed_frontmatter_fails
    # The false green a Reviewer caught in this check's own plan: an unterminated block was being
    # treated as "genuinely absent", which the shim rule permits. Absent and malformed must stay
    # distinct states, or "allow absent" silently becomes "allow broken".
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, ".claude/commands/distill.md"), <<~MD)
        ---
        description: Grill a plan.

        Read and follow [`skills/distill/SKILL.md`](../../skills/distill/SKILL.md).
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Claude Invocation Shim \.claude/commands/distill\.md opens a frontmatter block}, out)
    end
  end

  def test_shim_non_mapping_frontmatter_fails
    # An empty block parses cleanly to nil, so it reaches the shim's permissive path without ever
    # raising. Found by mutating the shim's :non_mapping branch away and watching every test stay
    # green — the same shape of hole as the :unterminated false green, on the same surface.
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, ".claude/commands/distill.md"), <<~MD)
        ---
        ---

        Read and follow [`skills/distill/SKILL.md`](../../skills/distill/SKILL.md).
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Claude Invocation Shim \.claude/commands/distill\.md frontmatter is not a key.value mapping}, out)
      assert_match(/parsed as an empty block/, out)
    end
  end

  def test_shim_frontmatter_without_description_fails
    # A shim that opens a block at all must say what it invokes; omitting the block entirely is the
    # supported way to say nothing (test_shim_without_frontmatter_passes).
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, ".claude/commands/distill.md"), <<~MD)
        ---
        name: distill
        ---

        Read and follow [`skills/distill/SKILL.md`](../../skills/distill/SKILL.md).
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/carries frontmatter but no non-empty `description:`/, out)
    end
  end

  def test_skill_indented_fence_in_block_scalar_does_not_truncate_validation
    # Reviewer finding (PR #111). An indented `---` is legal content inside a YAML block scalar. When
    # the fence matcher stripped indentation, that line closed the block early, the remainder was
    # never handed to the parser, and malformed YAML *after* it passed the gate — the exact false
    # green this whole change exists to close, in a new disguise. `broken:` below carries an unquoted
    # colon-space and MUST be reached.
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, "skills/distill/SKILL.md"), <<~MD)
        ---
        name: distill
        description: Valid description.
        extra: |
          ---
        broken: Stage 3: this is invalid YAML
        ---

        Body.
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/unparseable YAML frontmatter/, out)
    end
  end

  def test_shim_indented_fence_in_block_scalar_does_not_truncate_validation
    # The same helper serves both surfaces, so the truncation hid malformed shim frontmatter too —
    # not just the body case the review demonstrated.
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, ".claude/commands/distill.md"), <<~MD)
        ---
        description: Valid description.
        extra: |
          ---
        broken: Stage 3: this is invalid YAML
        ---

        Read and follow [`skills/distill/SKILL.md`](../../skills/distill/SKILL.md).
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Claude Invocation Shim \.claude/commands/distill\.md has unparseable YAML frontmatter}, out)
    end
  end

  def test_skill_valid_block_scalar_containing_fence_passes
    # The companion boundary test the review asked for: tightening the fence rule must not redden a
    # legitimate block scalar whose *content* is `---`. Under the old matcher this file was a false
    # RED — the block truncated, `description:` came back empty, and the check errored on a valid file.
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, "skills/distill/SKILL.md"), <<~MD)
        ---
        name: distill
        description: |
          ---
        ---

        Body.
      MD
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_skill_indented_opening_fence_is_not_frontmatter
    # Same root cause on the opening fence: an indented `---` is not a frontmatter delimiter, so the
    # file genuinely has no frontmatter and must route to the existing missing-frontmatter error
    # rather than being parsed as though it were fenced.
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, "skills/distill/SKILL.md"), "  ---\n  name: distill\n  ---\n\nBody.\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/lacks YAML frontmatter with a `name:` key/, out)
    end
  end

  def test_name_mismatch_error_with_non_ascii_name_stays_ascii
    # The name-mismatch message is the one place this check interpolates AUTHOR-CONTROLLED frontmatter
    # into stdout, and a `name:` may legitimately carry non-ASCII. Without escaping, the checker's own
    # output breaks the ASCII rule (ADR 0011) that this same change added the first test for. The
    # parse-failure fixture below cannot catch this: Psych reports line/column and never echoes source,
    # so only a value we interpolate ourselves can leak.
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, "skills/distill/SKILL.md"), <<~MD)
        ---
        name: café-skill
        description: A portable skill.
        ---

        Body.
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{but lives in skills/distill/}, out)
      assert out.ascii_only?, "parity_check stdout must stay ASCII (ADR 0011); got: #{out.inspect}"
      # Still diagnostic: the escaped form names the offending value rather than hiding it.
      assert_match(/caf/, out)
    end
  end

  def test_frontmatter_errors_are_ascii_only
    # ADR 0011 makes the ASCII-stdout rule author-owned rather than machine-enforced, and
    # rules/scripting.md names "a test that asserts a script's captured output" as its natural catch
    # point — which did not exist anywhere in test/ until now. It matters most here, because the
    # values being reported on are prose descriptions that legitimately carry em dashes and arrows:
    # the fixture below is broken YAML whose offending line is non-ASCII, so any message that echoed
    # the source instead of reporting line/column would fail this assertion.
    with_bundle do |dir|
      add_skills(dir)
      File.write(File.join(dir, "skills/distill/SKILL.md"), <<~MD)
        ---
        name: distill
        description: Grill a plan — one question at a time → sharpen it: relentlessly.
        ---

        Body.
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/unparseable YAML frontmatter/, out)
      assert out.ascii_only?, "parity_check stdout must stay ASCII (ADR 0011); got: #{out.inspect}"
    end
  end

  def test_required_skill_absent_fails
    # A valid skills tree missing one required skill -> the floor reddens.
    with_bundle do |dir|
      add_skills(dir)
      FileUtils.rm_rf(File.join(dir, "skills/distill")) # required skill dir removed
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Required skill missing: skills/distill/SKILL\.md}, out)
    end
  end

  def test_required_lifecycle_skill_absent_fails
    # Dropping a lifecycle skill (e.g. invoke) also reddens the floor.
    with_bundle do |dir|
      add_skills(dir)
      FileUtils.rm_rf(File.join(dir, "skills/invoke"))
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Required skill missing: skills/invoke/SKILL\.md}, out)
    end
  end

  def test_required_ship_skill_absent_fails
    # `ship` is the orchestrator (ADR 0005/0006) and part of the floor: dropping it reddens too. This
    # pins ship into REQUIRED_SKILLS so a future edit can't silently drop the eighth baseline skill.
    with_bundle do |dir|
      add_skills(dir)
      FileUtils.rm_rf(File.join(dir, "skills/ship"))
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Required skill missing: skills/ship/SKILL\.md}, out)
    end
  end

  def test_required_create_skill_absent_fails
    # `create-skill` is the authoring front door (ADR 0019) and part of the floor: dropping it reddens
    # too. This pins create-skill into REQUIRED_SKILLS so a future edit can't silently drop it.
    with_bundle do |dir|
      add_skills(dir)
      FileUtils.rm_rf(File.join(dir, "skills/create-skill"))
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Required skill missing: skills/create-skill/SKILL\.md}, out)
    end
  end

  def test_required_follow_skill_absent_fails
    # `follow` is the intake-pipeline roster front door (ADR 0021) and part of the floor: dropping it
    # reddens too. This pins follow into REQUIRED_SKILLS so a future edit can't silently drop it.
    with_bundle do |dir|
      add_skills(dir)
      FileUtils.rm_rf(File.join(dir, "skills/follow"))
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Required skill missing: skills/follow/SKILL\.md}, out)
    end
  end

  def test_required_restock_skill_absent_fails
    # `restock` is the Tool Roster refresh (ADR 0023), a baseline member of the floor: dropping it
    # reddens too. This pins restock into REQUIRED_SKILLS so a future edit can't silently drop it.
    with_bundle do |dir|
      add_skills(dir)
      FileUtils.rm_rf(File.join(dir, "skills/restock"))
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Required skill missing: skills/restock/SKILL\.md}, out)
    end
  end

  def test_required_scout_skill_absent_fails
    # `scout` is the intake-pipeline sweep (ADR 0012) and part of the floor: dropping it reddens too.
    # Until issue #96 this pin was MISSING, so a trim could silently delete the intake sweep from
    # REQUIRED_SKILLS with the whole suite still green — the invisible-trim bug class this issue exists
    # to close. Pinning it makes any future detachment an explicit, reviewed edit to the floor.
    with_bundle do |dir|
      add_skills(dir)
      FileUtils.rm_rf(File.join(dir, "skills/scout"))
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Required skill missing: skills/scout/SKILL\.md}, out)
    end
  end

  def test_required_clip_skill_absent_fails
    # `clip` is the intake pipeline's push front door (ADR 0015) and part of the floor. Same missing
    # pin as scout above (issue #96): dropping it must redden, not pass silently.
    with_bundle do |dir|
      add_skills(dir)
      FileUtils.rm_rf(File.join(dir, "skills/clip"))
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Required skill missing: skills/clip/SKILL\.md}, out)
    end
  end

  # --- Skills content-neutrality (ADR 0003) ------------------------------------------------------

  def test_lifecycle_skill_without_project_reference_fails
    # A lifecycle body with valid frontmatter but no PROJECT.md reference must redden (it would be
    # hardcoding host values instead of reading them from the Project Config).
    with_bundle do |dir|
      add_skills(dir)
      write_skill(dir, "assess", body: "---\nname: assess\ndescription: x\n---\n\nHardcoded body, no config reference.\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/does not reference PROJECT\.md/, out)
    end
  end

  def test_skill_with_host_specific_token_fails
    # A body that still references PROJECT.md but names a host stack -> the denylist reddens.
    with_bundle do |dir|
      add_skills(dir)
      write_skill(dir, "invoke", body: "---\nname: invoke\ndescription: x\n---\n\nRun the checks from PROJECT.md. Reindex with Searchkick.\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/contains host-specific token `Searchkick`/, out)
    end
  end

  def test_skill_with_punctuation_token_fails
    # The substring branch of the matcher: a punctuation-bearing token (a path) must also redden,
    # not only the ASCII-letter-boundary branch that `Searchkick` exercises.
    with_bundle do |dir|
      add_skills(dir)
      write_skill(dir, "verify", body: "---\nname: verify\ndescription: x\n---\n\nRead PROJECT.md and the rules under .claude/rules/testing.md.\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{contains host-specific token `\.claude/rules/`}, out)
    end
  end

  def test_generic_word_containing_token_substring_passes
    # `underspecified` contains "rspec" as a substring but is not the standalone word -> must NOT trip
    # the denylist (guards the ASCII-letter word-boundary matcher against a false positive).
    with_bundle do |dir|
      add_skills(dir)
      # `assess` is gate-aware, so the body must also name Human Gates to isolate the token check.
      write_skill(dir, "assess", body: "---\nname: assess\ndescription: x\n---\n\nFlag anything underspecified in the issue; read PROJECT.md -> Human Gates.\n")
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_skill_not_referenced_by_agents_fails
    with_bundle do |dir|
      add_skills(dir)
      # Rewrite AGENTS.md to a valid, link-resolving body that references no skill.
      File.write(File.join(dir, "AGENTS.md"), "# Canonical\n\nSee [config](PROJECT.md).\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/not referenced by AGENTS\.md/, out)
    end
  end

  # --- Usage guides (issue #11) ------------------------------------------------------------------

  def test_valid_guides_pass
    with_bundle do |dir|
      add_guides(dir)
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_guides_absent_are_not_checked
    # No docs/guides/ dir -> check_guides is a no-op, so a bundle without any guide still passes.
    with_bundle do |dir|
      refute Dir.exist?(File.join(dir, "docs/guides"))
      code, = run_check(dir)
      assert_equal 0, code
    end
  end

  def test_missing_required_guide_fails
    # docs/guides/ present (gate active) but the required guide gone -> the floor reddens.
    with_bundle do |dir|
      add_guides(dir)
      File.delete(File.join(dir, "docs/guides/usage.md"))
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Required guide missing: docs/guides/usage\.md}, out)
    end
  end

  def test_guide_without_readme_passes
    # The vendored-copy invariant: ai-config-sync does NOT ship README.md, so a bundle with the guide
    # but no README must still pass. Reachability is not anchored to README (see REQUIRED_GUIDES) — a
    # rule that required a README reference would break every vendored copy. Pins that fix.
    with_bundle do |dir|
      add_guides(dir)
      File.delete(File.join(dir, "README.md"))
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_dead_link_in_guide_fails
    # Proves the widened LINK_CHECKED actually guards the guide: a dead link in it reddens.
    with_bundle do |dir|
      add_guides(dir)
      File.write(File.join(dir, "docs/guides/usage.md"), "# Guide\n\n[gone](nope.md)\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/Dead link/, out)
    end
  end

  # --- Link checking: code spans are not links (issue #96) ---------------------------------------
  #
  # check_links must resolve REAL links only. A markdown link that exists as an ILLUSTRATION — inside
  # a fenced code block or an inline-code span — names a path in someone else's repo (or documents the
  # link syntax itself), so reporting it dead is a false positive. Before issue #96 the check had no
  # such notion, which is why LINK_CHECKED could not be widened: doing so reddened three real files
  # (`skills/distill/CONTEXT-FORMAT.md`'s illustrative Context Map, `docs/rules/README.md`'s prose
  # documenting the `[text](path)` convention) and would have taught every author that examples are
  # forbidden. These tests pin the stripping in both directions: illustrations pass, real links fail.

  def test_dead_link_inside_fenced_block_passes
    # Regression guard for skills/distill/CONTEXT-FORMAT.md: an illustrative Context Map inside a
    # ```md fence (note the info string) names paths in a hypothetical host repo, not this one.
    with_bundle do |dir|
      File.write(File.join(dir, "AGENTS.md"), <<~MD)
        # Canonical

        ```md
        - [Ordering](./src/ordering/CONTEXT.md) - an example for a host repo, not a real target
        ```
      MD
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_dead_link_inside_tilde_fenced_block_passes
    # ~~~ is an equally valid CommonMark fence; the checker must not recognize only backticks.
    with_bundle do |dir|
      File.write(File.join(dir, "AGENTS.md"), <<~MD)
        # Canonical

        ~~~
        [example](./src/ordering/CONTEXT.md)
        ~~~
      MD
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_dead_link_inside_inline_code_span_passes
    # Regression guard for docs/rules/README.md, whose prose documents this very convention by
    # quoting the literal string `[text](path)` inside an inline-code span.
    with_bundle do |dir|
      File.write(
        File.join(dir, "AGENTS.md"),
        "# Canonical\n\nA backticked path, not a `[text](path)` markdown link.\n"
      )
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_dead_link_inside_double_backtick_span_passes
    # A double-backtick span exists to hold a literal backtick. The closer must be a run of EXACTLY
    # the opening length, so the lone ` inside must not end the span early (which would leak the
    # illustrative link back into the scan and false-fail).
    with_bundle do |dir|
      File.write(
        File.join(dir, "AGENTS.md"),
        "# Canonical\n\nSpan: ``[t](./illustrative.md) and a ` tick`` done.\n"
      )
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_dead_link_outside_code_spans_still_fails
    # The sad path the stripping must NOT swallow: an ordinary dead link still reddens, named by file.
    with_bundle do |dir|
      File.write(File.join(dir, "AGENTS.md"), "# Canonical\n\n[gone](docs/nope.md)\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Dead link in AGENTS\.md: `docs/nope\.md`}, out)
    end
  end

  def test_unterminated_fence_does_not_disable_link_checking
    # The false-green guard. If an unterminated fence were treated as running to end-of-file (the
    # renderer's semantics), one stray delimiter would silently switch link checking OFF for every
    # remaining line — a checker's worst failure mode. A fence is stripped only when its closer is
    # found; an unterminated one is a stray delimiter, and links on BOTH sides of it still resolve.
    with_bundle do |dir|
      File.write(File.join(dir, "AGENTS.md"), <<~MD)
        # Canonical

        [before](./gone-before.md)

        ```md
        an opening fence that is never closed

        [after](./gone-after.md)
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Dead link in AGENTS\.md: `\./gone-before\.md`}, out)
      assert_match(
        %r{Dead link in AGENTS\.md: `\./gone-after\.md`}, out,
        "an unterminated fence swallowed the rest of the file and disabled link checking"
      )
    end
  end

  def test_real_link_on_same_line_as_inline_code_span_still_fails
    # The over-stripping guard: blanking must remove the SPAN, never the whole line. A line that
    # quotes the link syntax and then uses a real link must still resolve the real one.
    with_bundle do |dir|
      File.write(
        File.join(dir, "AGENTS.md"),
        "# Canonical\n\nSyntax is `[t](./illustrative.md)`, and here is [real](./missing.md).\n"
      )
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Dead link in AGENTS\.md: `\./missing\.md`}, out)
      refute_match(/illustrative/, out, "the inline-code span leaked into the link scan")
    end
  end

  # --- Link checking: the widened bundle-owned surface (issue #96) --------------------------------
  #
  # Before issue #96 LINK_CHECKED covered nine files, so a dead link anywhere in docs/adr/,
  # docs/reference/, skills/, rules/ or CONTEXT.md shipped green. LINK_CHECKED is now an EXPLICIT
  # enumeration of every bundle-owned markdown file (never a glob — a glob would sweep a Host App's
  # OWN docs after vendoring and redden their parity on day one for links the bundle never shipped).

  # Writes `body` to the first LINK_CHECKED entry under `prefix` and returns that relative path.
  # Selecting the path FROM the constant, rather than hardcoding one filename, keeps these tests
  # honest when an ADR or entry is added or renamed, while still proving the subtree is covered.
  def write_link_checked_under(dir, prefix, body)
    rel = ParityCheck::LINK_CHECKED.find { |p| p.start_with?(prefix) }
    refute_nil rel, "LINK_CHECKED covers no file under #{prefix}"
    FileUtils.mkdir_p(File.join(dir, File.dirname(rel)))
    File.write(File.join(dir, rel), body)
    rel
  end

  def test_dead_link_in_adr_fails
    with_bundle do |dir|
      rel = write_link_checked_under(dir, "docs/adr/", "# ADR\n\n[gone](./nope.md)\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Dead link in #{Regexp.escape(rel)}: `\./nope\.md`}, out)
    end
  end

  def test_dead_link_in_reference_doc_fails
    # docs/reference/ holds the Learnings-Log entries — the subtree that actually carried the one
    # genuine dead link this issue found (a `../../adr/` that needed `../../../adr/`).
    with_bundle do |dir|
      rel = write_link_checked_under(dir, "docs/reference/", "# Entry\n\n[gone](./nope.md)\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Dead link in #{Regexp.escape(rel)}: `\./nope\.md`}, out)
    end
  end

  def test_dead_link_in_skill_body_fails
    # The literal case from the field report: a Skill body pointing at a path that no longer exists.
    with_bundle do |dir|
      add_skills(dir)
      write_skill(
        dir, "distill",
        body: "---\nname: distill\ndescription: x\n---\n\nSee [the format](./MISSING-FORMAT.md).\n"
      )
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Dead link in skills/distill/SKILL\.md: `\./MISSING-FORMAT\.md`}, out)
    end
  end

  def test_dead_link_in_rule_file_fails
    with_bundle do |dir|
      add_rules(dir)
      File.write(File.join(dir, "rules/testing.md"), <<~MD)
        # Rule

        See [the deep doc](../docs/rules/nope.md).

        ## Patterns

        - Prefer the framework's built-ins.

        ## Anti-Patterns

        - **Never** do the bad thing - because it breaks.
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Dead link in rules/testing\.md: `\.\./docs/rules/nope\.md`}, out)
    end
  end

  def test_dead_link_in_context_map_fails
    with_bundle do |dir|
      assert_includes ParityCheck::LINK_CHECKED, "CONTEXT.md"
      File.write(File.join(dir, "CONTEXT.md"), "# Context\n\n[gone](docs/nope.md)\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Dead link in CONTEXT\.md: `docs/nope\.md`}, out)
    end
  end

  def test_widened_link_surface_leaves_a_minimal_bundle_green
    # The boundary that keeps host blast radius at zero: every widened entry is presence-gated, so a
    # bundle that ships none of those files (the minimal fixture, and any partially-vendored host) is
    # unaffected by the widening. Asserted explicitly — this is the invariant the enumeration buys.
    with_bundle do |dir|
      # Everything build_baseline does NOT write — i.e. every entry the widening added.
      fixture_writes = ["AGENTS.md", "CLAUDE.md", "GEMINI.md", "PROJECT.md", ".github/copilot-instructions.md"]
      widened = ParityCheck::LINK_CHECKED - fixture_writes
      refute_empty widened
      widened.each { |rel| refute File.exist?(File.join(dir, rel)), "fixture unexpectedly ships #{rel}" }
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  # --- LINK_CHECKED enumeration drift guard (issue #96) -------------------------------------------

  # Markdown files that are vendored but deliberately NOT link-checked. Empty by design: if you add an
  # entry here, state WHY the file's links may rot in a Host App. An empty list is the strong form of
  # the invariant — every markdown file the bundle ships has its links resolved. Both properties are
  # asserted below, because an unguarded exemption list is just a quiet way to silence this guard.
  LINK_CHECK_EXEMPT = [].freeze

  def repo_root = File.expand_path("..", __dir__)

  def sync_installer
    load File.join(repo_root, "bin", "ai-config-sync") unless defined?(AiConfigSync)
    AiConfigSync
  end

  # Every markdown file this bundle VENDORS, derived by walking ai-config-sync's own ALLOW manifest and
  # mirroring its copy semantics exactly (FNM_DOTMATCH, the self-exclusion, the .local skip).
  #
  # Deriving from ALLOW rather than re-globbing the subtrees LINK_CHECKED enumerates is the whole point
  # of this guard: a glob list written next to the constant can only ever agree with it, so an omitted
  # *subtree* (docs/research/, docs/overlays/, .claude/commands/ were all missed exactly this way) is
  # invisible. For the same reason the walk must match the installer rather than approximate it — a
  # dotted directory like docs/.templates/ ships to hosts under FNM_DOTMATCH, and a plain **/*.md glob
  # would never see it.
  def vendored_markdown
    sync = sync_installer
    sync::ALLOW
      .flat_map do |entry|
        abs = File.join(repo_root, entry)
        if File.directory?(abs)
          Dir.glob("**/*.md", File::FNM_DOTMATCH, base: abs).map { |sub| File.join(entry, sub) }
        elsif File.file?(abs) && entry.end_with?(".md")
          [entry]
        else
          []
        end
      end
      .reject { |rel| rel == sync::SELF_REL || File.basename(rel).match?(sync::LOCAL_RE) }
      .uniq.sort
  end

  def test_link_check_exempt_entries_are_real_and_the_list_is_empty
    # An exemption list nobody checks is a silencing hole: a stale or misspelled entry exempts nothing
    # and reports nothing, and a "just quiet the failure" entry looks identical to a considered one.
    # Guard both ends — every entry must name a file that actually ships...
    stale = LINK_CHECK_EXEMPT - vendored_markdown
    assert_empty(
      stale,
      "these LINK_CHECK_EXEMPT entries are not vendored markdown files, so they exempt nothing:\n  " \
      "#{stale.join("\n  ")}"
    )
    # ...and the list ships EMPTY, so adding to it is a deliberate, reviewed act rather than a quiet
    # way to make this file's other guard go green. Adding an entry should require editing this test.
    assert_empty(
      LINK_CHECK_EXEMPT,
      "LINK_CHECK_EXEMPT is no longer empty. That may be correct - but it weakens the link-check " \
      "invariant, so state the justification here and update this assertion deliberately."
    )
  end

  def test_link_checked_enumerates_every_vendored_markdown_file
    # An explicit list rots the moment someone adds a doc. This is the guard that buys it its safety:
    # add an ADR, a Learnings entry, a guide, a Skill body or a shim — or a whole new docs/ subtree —
    # without listing it, and this reddens naming the files, so the fix is mechanical.
    shipped = vendored_markdown
    refute_empty shipped, "walking ai-config-sync's ALLOW manifest found no markdown - the walk is broken"
    unlisted = shipped - ParityCheck::LINK_CHECKED - LINK_CHECK_EXEMPT
    assert_empty(
      unlisted,
      "these vendored markdown files are not in ParityCheck::LINK_CHECKED, so their links are never " \
      "resolved - add each to the constant:\n  #{unlisted.join("\n  ")}"
    )
  end

  def test_vendored_markdown_walk_reaches_every_docs_subtree
    # Guards the guard. If the ALLOW walk ever stopped recursing (a `*.md` where `**/*.md` belongs),
    # the test above would pass vacuously while covering almost nothing. Pin that it reaches the
    # deepest shipped tree and every top-level docs/ subdirectory that exists.
    shipped = vendored_markdown
    assert_includes shipped, "docs/reference/learnings/entries/2026-07-06-hamel-evals-first-class-tests.md"
    Dir.children(File.join(repo_root, "docs"))
       .select { |c| Dir.exist?(File.join(repo_root, "docs", c)) }
       .each do |sub|
      next if Dir.glob(File.join(repo_root, "docs", sub, "**", "*.md")).empty?

      assert(
        shipped.any? { |rel| rel.start_with?("docs/#{sub}/") },
        "the ALLOW walk reached no markdown under docs/#{sub}/ - the walk is not recursing"
      )
    end
  end

  def test_link_checked_has_no_stale_entries
    # The other direction: a renamed or deleted doc leaves an entry that silently checks nothing
    # (check_links skips missing files by design, so the rot is invisible without this assertion).
    # Every LINK_CHECKED entry must exist in THIS repo — the presence-gate exists for partial HOSTS.
    stale = ParityCheck::LINK_CHECKED.reject { |rel| File.exist?(File.join(repo_root, rel)) }
    assert_empty(
      stale,
      "these ParityCheck::LINK_CHECKED entries no longer exist on disk, so they check nothing - " \
      "remove or rename each:\n  #{stale.join("\n  ")}"
    )
  end

  # --- Human-gate policy (ADR 0025) --------------------------------------------------------------

  # Appends a `## Human Gates` section to the baseline fixture's PROJECT.md. Deliberately an ADDITIVE
  # helper rather than an edit to build_baseline: test_baseline_without_human_gates_section_passes
  # depends on build_baseline staying free of the section, as the vendored-host regression guard.
  def add_human_gates(dir, plan: "required", merge: "required")
    project = File.read(File.join(dir, "PROJECT.md"))
    File.write(File.join(dir, "PROJECT.md"), <<~MD)
      #{project}
      ## Human Gates

      | Gate | Setting | Allowed values |
      |------|---------|----------------|
      | **Plan approval** — the option pick and the plan | `#{plan}` | `required` · `auto` |
      | **Merge** — the HC merges the delivered PR | `#{merge}` | `required` (not configurable) |
    MD
  end

  def test_baseline_without_human_gates_section_passes
    # The additive / non-breaking contract: `## Human Gates` is NOT in REQUIRED_PROJECT_SECTIONS, so a
    # PROJECT.md that predates it (exactly what build_baseline writes, and what every already-vendored
    # Host App has) must still pass — the parser supplies the strict defaults. This is why
    # build_baseline must stay untouched: it IS the regression fixture for the vendored-host case.
    with_bundle do |dir|
      refute_includes File.read(File.join(dir, "PROJECT.md")), "## Human Gates"
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_valid_human_gates_section_passes
    with_bundle do |dir|
      add_human_gates(dir)
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_auto_merge_gate_fails_as_non_configurable
    # The safety invariant: no Host App may express self-merge. This must fail with its OWN message
    # naming merge as non-configurable, not the generic bad-value message — it is a policy boundary.
    with_bundle do |dir|
      add_human_gates(dir, merge: "auto")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/merge gate is NOT configurable/, out)
      assert_match(/no Host App may express self-merge/, out)
    end
  end

  def test_case_variant_merge_value_fails_as_a_typo_not_as_self_merge
    # A capitalization slip is a typo, not a policy claim. `Required` is still invalid (values are
    # matched exactly, never coerced), but reporting it as "no Host App may express self-merge" accuses
    # the host of something it did not write and hides the real fix. The accusation is reserved for a
    # genuine `auto`; everything else gets the generic allowed-values message.
    with_bundle do |dir|
      add_human_gates(dir, merge: "Required")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/unknown value `Required` for `merge`/, out)
      assert_match(/allowed values are `required`/, out)
      refute_match(/self-merge/, out, "a capitalization typo was reported as a self-merge claim")
      refute_match(/NOT configurable/, out)
    end
  end

  def test_unknown_plan_approval_value_fails_with_allowed_values
    with_bundle do |dir|
      add_human_gates(dir, plan: "sometimes")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/unknown value `sometimes` for `plan-approval`/, out)
      assert_match(/allowed values are `required`, `auto`/, out)
    end
  end

  def test_gate_aware_skill_not_naming_human_gates_fails
    # The resident-default rule (ADR 0025): a body that acts on a gate must NAME the host value. A
    # body that references PROJECT.md but never names Human Gates would be hardcoding a gate policy.
    with_bundle do |dir|
      add_skills(dir)
      write_skill(dir, "ship", body: "---\nname: ship\ndescription: x\n---\n\nSequence the phases; read host values from PROJECT.md.\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/Gate-aware Skill ship: skills\/ship\/SKILL\.md does not name the `Human Gates`/, out)
    end
  end

  # --- Reviewer declaration (ADR 0026) -----------------------------------------------------------

  # Appends a `## Reviewer` section to the baseline fixture's PROJECT.md. Additive for the same reason
  # add_human_gates is: test_baseline_without_reviewer_section_passes depends on build_baseline
  # staying free of the section, as the vendored-host regression guard.
  #
  # `invocation:` emits a matching `### Invocation paths` sub-table. It defaults to TRUE and must stay
  # that way: under ADR 0027 a chain entry with no row there is unreachable and reported, so the
  # settings-table-only fixture this helper used to write is the authored-but-INCOMPLETE state, not
  # the valid one. Every caller asserting exit 0 depends on the sub-table being present; pass
  # `invocation: false` only to build the incomplete case deliberately.
  def add_reviewer(dir, floor: "stop-and-ask", window: "30m", primary: "Codex", fallback: "Copilot",
                   invocation: true)
    paths = if invocation
              <<~SUB
                ### Invocation paths

                | Harness | Summons | Precondition | Check |
                |---------|---------|--------------|-------|
                | Codex | mention it on the PR | app installed | *(host-supplied)* |
                | Copilot | request a review via the API | review enabled | *(host-supplied)* |
              SUB
            else
              ""
            end
    project = File.read(File.join(dir, "PROJECT.md"))
    File.write(File.join(dir, "PROJECT.md"), <<~MD)
      #{project}
      ## Reviewer

      | Field | Setting | Allowed values |
      |-------|---------|----------------|
      | **Primary** — summoned first | `#{primary}` | any harness |
      | **Fallback order** — tried in turn | `#{fallback}` | comma-separated, or `none` |
      | **Bounded window** — wait before falling back | `#{window}` | `<integer><unit>` |
      | **Degradation floor** — chain exhausted | `#{floor}` | `stop-and-ask` (not configurable) |

      #{paths}
    MD
  end

  def test_baseline_without_reviewer_section_passes
    # The additive / non-breaking contract, mirroring the Human Gates guard: `## Reviewer` is NOT in
    # REQUIRED_PROJECT_SECTIONS, so an already-vendored PROJECT.md that predates it must still pass —
    # the parser supplies the shipped defaults.
    with_bundle do |dir|
      refute_includes File.read(File.join(dir, "PROJECT.md")), "## Reviewer"
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_no_unsummonable_error_fires_without_a_reviewer_section
    # The compatibility invariant asserted a SECOND time, and specifically against the check most
    # likely to break it. test_baseline_without_reviewer_section_passes above asserts exit 0, which
    # any future error would also break — but this one names the mechanism: an absent section supplies
    # the shipped chain with NO invocation paths, so a check that forgot `Reviewer.section?` would
    # report every vendored host's whole chain unreachable on re-sync (ADR 0027 decision 5).
    with_bundle do |dir|
      refute_includes File.read(File.join(dir, "PROJECT.md")), "## Reviewer"
      code, out = run_check(dir)
      assert_equal 0, code, out
      refute_match(/no summons mechanism/, out)
    end
  end

  def test_valid_reviewer_section_passes
    # THE negative control for every chain test below: a fully authored section — settings table AND
    # the `### Invocation paths` sub-table naming both chain entries — must pass. Without the
    # sub-table this fixture is the authored-but-incomplete state (see the test immediately below),
    # so if `add_reviewer` ever loses it, this test is what catches it.
    with_bundle do |dir|
      add_reviewer(dir)
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_authored_section_without_invocation_paths_fails
    # Finding 1 of #118, at the parity layer. The section is AUTHORED — so this is a host claiming the
    # chain, not a vendored copy predating it — but nothing declares how to summon anyone. Every entry
    # is unreachable, and the run would resolve to the floor while parity said the config was fine.
    with_bundle do |dir|
      add_reviewer(dir, invocation: false)
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/names `Codex` in the reviewer chain but .*no summons mechanism/, out)
      assert_match(/names `Copilot` in the reviewer chain but .*no summons mechanism/, out)
    end
  end

  def test_primary_with_no_invocation_row_fails
    with_bundle do |dir|
      add_reviewer(dir, primary: "Not A Configured Harness")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/names `Not A Configured Harness` in the reviewer chain but .*no summons/, out)
      refute_match(/names `Copilot`/, out, "the fallback HAS a row and must not be reported")
    end
  end

  def test_fallback_with_no_invocation_row_fails
    with_bundle do |dir|
      add_reviewer(dir, fallback: "Nope")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/names `Nope` in the reviewer chain but .*no summons/, out)
      refute_match(/names `Codex`/, out, "the primary HAS a row and must not be reported")
    end
  end

  def test_blank_primary_fails
    # A backtick pair holding only whitespace parses as READABLE (it matches BACKTICKED) and yields an
    # empty primary, so neither the unreadable-cell check nor the allowed-values check sees anything.
    # The chain then has no first entry at all — nobody to summon at the PR gate — and before ADR 0027
    # that shipped green.
    with_bundle do |dir|
      add_reviewer(dir, primary: " ")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/declares an empty `primary`/, out)
      assert_match(/nobody to summon at the PR gate/, out)
      refute_match(/carries no backticked value/, out, "the cell IS readable; the value is the fault")
      refute_match(/fallback-order/, out)
    end
  end

  def test_blank_fallback_element_fails
    # `Copilot, , Grok` — the empty element from #118's repro, isolated. Grok has no invocation row, so
    # this fixture also reports it unreachable; the assertion below pins that the BLANK element is
    # reported under its own message, which is the fault this test exists for.
    with_bundle do |dir|
      add_reviewer(dir, fallback: "Copilot, , Grok")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/has an EMPTY element/, out)
      refute_match(/mixes `none`/, out, "a blank element is not a none-mixed fault")
    end
  end

  def test_a_wholly_blank_fallback_order_fails
    # The sibling shape of the test above, and the one that reported NOTHING before this fix. A
    # whitespace-only backtick pair is READABLE (it matches BACKTICKED), so the unreadable-cell check
    # stays quiet, `extract` yields "", and the fallback simply disappeared from the chain - while
    # `Copilot,`, which still yields a working one-entry chain, was flagged. It gets its own wording
    # because "has an EMPTY element" misdescribes a value that has no elements at all.
    with_bundle do |dir|
      add_reviewer(dir, fallback: " ")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/declares a `fallback-order` that is entirely BLANK/, out)
      assert_match(/the primary is the only reviewer that will ever be tried/, out)
      refute_match(/has an EMPTY element/, out, "a blank value has no elements to be empty")
      refute_match(/carries no backticked value/, out, "the cell IS readable; the value is the fault")
    end
  end

  def test_none_mixed_with_real_entries_fails
    with_bundle do |dir|
      add_reviewer(dir, fallback: "none, Copilot")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/mixes `none` with real entries/, out)
      refute_match(/has an EMPTY element/, out, "a none-mixed fallback has no blank element")
    end
  end

  def test_primary_repeated_in_its_own_fallback_fails
    with_bundle do |dir|
      add_reviewer(dir, primary: "Codex", fallback: "Codex")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/repeats the primary `Codex` in its own `fallback-order`/, out)
      assert_match(/cannot be its own independent backstop/, out)
      refute_match(/no summons mechanism/, out, "Codex HAS an invocation row - only the repeat is wrong")
    end
  end

  def test_a_setting_cell_carrying_two_backticked_values_fails
    # `Reviewer.extract` reads the FIRST backticked span and stops, so a list authored ONE CODE SPAN
    # PER ELEMENT loses everything after the first — and this file's own *Branch & PR Policy* authors
    # its protected-branch list exactly that way, so it is the convention a host will copy. The
    # `fallback` argument is written so the emitted cell is literally `` `Copilot`, `Codex` ``: the
    # helper supplies the outer pair of backticks.
    #
    # The refute is the whole point. `Copilot`, `Codex` under a `Codex` primary is a chain that
    # visibly falls back to itself, and the self-reference invariant PASSES on the truncated read —
    # so if the ambiguity were not reported, nothing here would be.
    with_bundle do |dir|
      add_reviewer(dir, primary: "Codex", fallback: "Copilot`, `Codex")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/carries MORE THAN ONE backticked value/, out)
      assert_match(/reads only the FIRST \(`Copilot`\)/, out)
      refute_match(/repeats the primary/, out,
                   "the precondition: the truncated read cannot see the repeat")
      refute_match(/carries no backticked value/, out, "the cell IS backticked - it is not unreadable")
    end
  end

  def test_a_decoy_invocation_heading_outside_the_reviewer_section_still_fails
    # #118's shape, at the parity layer. The host AUTHORED `## Reviewer` and declared no summons
    # mechanism inside it; an unrelated H2 elsewhere happens to carry an `### Invocation paths`
    # heading. A file-global search for that heading vouched for a chain the Reviewer section never
    # declared, and this shipped green — the exact false green this PR exists to close.
    with_bundle do |dir|
      add_reviewer(dir, invocation: false)
      path = File.join(dir, "PROJECT.md")
      File.write(path, "#{File.read(path)}\n#{<<~MD}")
        ## Some Other Section

        ### Invocation paths

        | Harness | Summons |
        |---------|---------|
        | Codex | mention it on the PR |
        | Copilot | request a review via the API |
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/names `Codex` in the reviewer chain but .*no summons mechanism/, out)
      assert_match(/names `Copilot` in the reviewer chain but .*no summons mechanism/, out)
    end
  end

  def test_new_reviewer_chain_messages_are_ascii_safe
    # ADR 0011: author-controlled values reach stdout through err(), so every interpolation in the new
    # messages goes through safe(). A harness name carrying a control character or a non-ASCII glyph
    # must be escaped, not printed verbatim.
    with_bundle do |dir|
      add_reviewer(dir, primary: "RogueéHarness")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/Rogue\\xE9\\x07Harness/, out)
      assert_empty out.chars.reject { |c| c.ord < 128 }, "no raw non-ASCII may reach stdout"
    end
  end

  def test_downgraded_degradation_floor_fails_as_non_configurable
    # The safety invariant, on the same footing as the merge gate: no Host App may declare that a run
    # with no reachable Reviewer delivers anyway. It must fail with its OWN policy-boundary message.
    #
    # The refutes are the point of this being a SINGLE-fault fixture: `add_reviewer` supplies a
    # complete, reachable chain, so a floor downgrade must be the ONLY reason this exits 1. A
    # composite failure would let this test pass on a bug in any of the checks it does not name.
    with_bundle do |dir|
      add_reviewer(dir, floor: "flag-in-sow")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/degradation floor is NOT configurable/, out)
      assert_match(/may not certify itself/, out)
      refute_match(/no summons mechanism/, out)
      refute_match(/unparseable bounded window/, out)
      refute_match(/fallback-order/, out)
    end
  end

  def test_unparseable_bounded_window_fails
    # PR #109 specified the window as prose ("for example, 30 minutes"), which no AC could execute.
    # A window that does not parse is not a bounded wait, so it must redden rather than ship.
    # Single-fault for the same reason as the test above — see its note.
    with_bundle do |dir|
      add_reviewer(dir, window: "30 minutes")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(/unparseable bounded window/, out)
      refute_match(/no summons mechanism/, out)
      refute_match(/degradation floor is NOT configurable/, out)
      refute_match(/fallback-order/, out)
    end
  end

  def test_reviewer_aware_skill_not_naming_the_host_value_fails
    # The resident-default rule (ADR 0026, mirroring ADR 0025): a body that summons, consumes or
    # reports the second-model review must NAME the host value rather than name a reviewer harness.
    with_bundle do |dir|
      add_skills(dir)
      write_skill(dir, "verify", body: "---\nname: verify\ndescription: x\n---\n\nSelf-review the PR; read host values from PROJECT.md and the Human Gates policy.\n")
      code, out = run_check(dir)
      assert_equal 1, code
      assert_match(%r{Reviewer-aware Skill verify: skills/verify/SKILL\.md does not name the}, out)
    end
  end

  def test_bare_word_reviewer_does_not_satisfy_the_reference
    # THE anti-false-green test, and the reason REVIEWER_REFERENCE is the emphasized pointer form.
    # "Reviewer" is ordinary prose throughout this repo — every one of the four reviewer-aware bodies
    # says it many times over. Had the check asserted the bare word, it would have passed on all four
    # the moment it was written: green on arrival, and blind to the reference ever being dropped.
    # This body mentions the Reviewer repeatedly and still must redden.
    with_bundle do |dir|
      add_skills(dir)
      write_skill(dir, "ship", body: <<~MD)
        ---
        name: ship
        description: x
        ---

        Sequence the phases. Reads host values from PROJECT.md and the Human Gates policy.
        The Reviewer gives an independent second-model review; when the Reviewer responds,
        fold the Reviewer's findings in. A Reviewer is not optional.
      MD
      code, out = run_check(dir)
      assert_equal 1, code, "a body naming the Reviewer only as prose must not satisfy the reference"
      assert_match(%r{Reviewer-aware Skill ship: skills/ship/SKILL\.md does not name the}, out)
    end
  end

  def test_reviewer_aware_skills_membership_is_pinned
    # Pins the list itself, the way the eight REQUIRED_SKILLS pins do. Without this, a later trim
    # could quietly drop `listen` or `final` from REVIEWER_AWARE_SKILLS with the whole suite still
    # green — the invisible-trim bug class (#96), and the green-but-blind class (#103). Each name is
    # asserted individually so a diff shows exactly which coverage a change removes.
    %w[verify listen final ship].each do |name|
      assert_includes ParityCheck::REVIEWER_AWARE_SKILLS, name,
                      "#{name} acts on the second-model review, so its body must be reference-checked"
    end
    assert_equal 4, ParityCheck::REVIEWER_AWARE_SKILLS.length,
                 "adding a reviewer-aware skill is fine — do it deliberately, and pin it here too"
  end

  def test_reviewer_reference_is_the_emphasized_pointer_form
    # Pins the CHOICE, not just the value: the bare word would make the check green-but-blind (see
    # test_bare_word_reviewer_does_not_satisfy_the_reference). If someone "simplifies" this constant
    # to "Reviewer", that test and this one both fail, naming the reason.
    assert_equal "*Reviewer*", ParityCheck::REVIEWER_REFERENCE
  end

  def test_bold_reviewer_does_not_satisfy_the_reference
    # THE SUBSTRING TRAP. `"**Reviewer**".include?("*Reviewer*")` is TRUE, so matching the constant
    # with `include?` was satisfied by ordinary bold prose — which docs/standards/development-lifecycle.md
    # already writes. A body could drop its pointer entirely, hardcode a reviewer harness and a literal
    # window, and still pass (Reviewer finding, PR #117). Hence REVIEWER_REFERENCE_RE, which rejects an
    # adjacent `*` on either side.
    with_bundle do |dir|
      add_skills(dir)
      write_skill(dir, "verify", body: <<~MD)
        ---
        name: verify
        description: x
        ---

        Self-review the PR; read host values from PROJECT.md and the Human Gates policy.
        The **Reviewer** is an independent second model. Summon the **Reviewer** by mentioning
        the review command on the PR, then wait 30 minutes for the **Reviewer** to answer.
      MD
      code, out = run_check(dir)
      assert_equal 1, code, "bold **Reviewer** prose must not satisfy the pointer reference"
      assert_match(%r{Reviewer-aware Skill verify: skills/verify/SKILL\.md does not name the}, out)
    end
  end

  def test_genuine_pointer_form_satisfies_the_reference
    # The negative control for the two tests above: the real pointer form must still PASS, or the
    # regex would just be a stricter way to be wrong.
    with_bundle do |dir|
      add_skills(dir)
      write_skill(dir, "verify", body: <<~MD)
        ---
        name: verify
        description: x
        ---

        Self-review the PR. Read the chain from PROJECT.md -> *Reviewer*, and the Human Gates policy.
      MD
      code, out = run_check(dir)
      assert_equal 0, code, out
    end
  end

  def test_unbackticked_reviewer_value_fails_as_unreadable
    # The bare-prose hole: `extract` fail-safes to the shipped default, so without a separate
    # unreadable check a PROJECT.md visibly declaring "deliver-unreviewed" read back as `stop-and-ask`
    # and passed green. Bare prose is the authoring form that closed PR #109.
    with_bundle do |dir|
      project = File.read(File.join(dir, "PROJECT.md"))
      File.write(File.join(dir, "PROJECT.md"), <<~MD)
        #{project}
        ## Reviewer

        | Field | Setting | Allowed values |
        |-------|---------|----------------|
        | **Degradation floor** — chain exhausted | deliver-unreviewed with a footnote | `stop-and-ask` |
      MD
      code, out = run_check(dir)
      assert_equal 1, code, "an authored-but-unreadable value must not pass green"
      assert_match(/carries no backticked value/, out)
      assert_match(/degradation-floor/, out)
    end
  end

  def test_setting_headed_label_column_does_not_hide_a_floor_downgrade
    # A host table headed `| Setting | Value |` bound column 0 — the LABEL column — so every field read
    # its own label, all four host values were discarded, and the floor hard-fail could not fire on a
    # downgrade plainly visible in the file (Reviewer finding, PR #117).
    with_bundle do |dir|
      project = File.read(File.join(dir, "PROJECT.md"))
      File.write(File.join(dir, "PROJECT.md"), <<~MD)
        #{project}
        ## Reviewer

        | Setting | Value |
        |---------|-------|
        | **Degradation floor** | `deliver-anyway` |
      MD
      code, out = run_check(dir)
      assert_equal 1, code, "a `Setting`-headed label column must not swallow the declared values"
      assert_match(/degradation floor is NOT configurable/, out)
    end
  end

  def test_reviewer_errors_stay_ascii_on_hostile_input
    # ADR 0011 / issue #113: author-controlled values reach err(). A control character, ANSI escape or
    # non-ASCII glyph in PROJECT.md must not reach the terminal verbatim through an error message.
    with_bundle do |dir|
      project = File.read(File.join(dir, "PROJECT.md"))
      File.write(File.join(dir, "PROJECT.md"), <<~MD)
        #{project}
        ## Reviewer

        | Field | Setting | Allowed values |
        |-------|---------|----------------|
        | **Bounded window** — wait | `30мин \e[31mRED\e[0m` | shape |
      MD
      code, out = run_check(dir)
      assert_equal 1, code
      assert out.ascii_only?, "parity_check stdout must stay ASCII even on hostile PROJECT.md values"
      refute_includes out, "\e", "an ANSI escape from PROJECT.md must not reach the terminal"
    end
  end

  # --- CLI wiring smoke (subprocess: proves the `exit` path, not just the class) -----------------

  def test_cli_exits_nonzero_on_broken_bundle
    Dir.mktmpdir do |dir|
      # Empty dir → everything missing → must exit non-zero.
      system("ruby", SCRIPT, "--root", dir, out: File::NULL, err: File::NULL)
      refute_equal 0, $?.exitstatus
    end
  end

  def test_cli_exits_zero_on_valid_bundle
    with_bundle do |dir|
      system("ruby", SCRIPT, "--root", dir, out: File::NULL, err: File::NULL)
      assert_equal 0, $?.exitstatus
    end
  end
end
