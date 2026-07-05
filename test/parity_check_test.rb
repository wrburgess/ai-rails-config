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

  # --- failure paths -----------------------------------------------------------------------------

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
