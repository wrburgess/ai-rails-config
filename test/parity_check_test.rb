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
  # value (satisfying the gate-aware check for assess/devise/invoke/ship/final — ADR 0025), and names
  # no host-specific token. `body:` overrides it (used by the neutrality failure tests).
  def write_skill(dir, name, body: nil)
    body_rel = "skills/#{name}/SKILL.md"
    shim_rel = ".claude/commands/#{name}.md"
    FileUtils.mkdir_p(File.join(dir, "skills/#{name}"))
    FileUtils.mkdir_p(File.join(dir, ".claude/commands"))
    File.write(File.join(dir, body_rel), body || <<~MD)
      ---
      name: #{name}
      description: A portable skill.
      ---

      Skill body. Reads host values from PROJECT.md, including the Human Gates policy.
    MD
    # The shim's relative link contains body_rel as a substring, satisfying the reference invariant.
    File.write(File.join(dir, shim_rel), "Read and follow [`#{body_rel}`](../../#{body_rel}).\n")
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
