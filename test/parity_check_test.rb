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
