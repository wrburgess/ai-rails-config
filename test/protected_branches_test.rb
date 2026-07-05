# frozen_string_literal: true

# Self-test for scripts/protected_branches.rb + bin/protected-branches. The extractor is the single
# seam that derives the protected-branch list from PROJECT.md (Option A, issue #6 / ADR 0009), so it
# must be exact: it feeds the git hooks. Stdlib only (minitest, tmpdir), mirroring the other tests.
#
# Run: ruby test/protected_branches_test.rb

require "minitest/autorun"
require "tmpdir"
require "rbconfig"
require_relative "../scripts/protected_branches"

class ProtectedBranchesTest < Minitest::Test
  CLI = File.expand_path("../bin/protected-branches", __dir__)
  RUBY = RbConfig.ruby

  # A PROJECT.md with a Branch & PR Policy section whose protected-branches line carries `branches`.
  def project_md(branch_line)
    <<~MD
      # Project Config
      ## Quality Checks
      cmds
      ## Branch & PR Policy
      #{branch_line}
      - **Branch naming:** `feature/` prefixes.
      ## Review Severity Framework
      ## Lifecycle Host
    MD
  end

  # --- extract: happy paths ----------------------------------------------------------------------

  def test_default_three_branches
    md = project_md("- **Protected branches:** `main`, `master`, `develop` — authored source; prose here.")
    assert_equal %w[main master develop], ProtectedBranches.extract(md)
  end

  def test_ignores_backticks_after_the_em_dash_separator
    # `bin/install-git-hooks` and `.githooks/protected-branches` live in the prose AFTER the em dash
    # and must NOT be collected as branches.
    md = project_md(
      "- **Protected branches:** `main` — run `bin/install-git-hooks` to regenerate `.githooks/x`."
    )
    assert_equal %w[main], ProtectedBranches.extract(md)
  end

  def test_host_trimmed_list
    md = project_md("- **Protected branches:** `main` — a host trimmed the list.")
    assert_equal %w[main], ProtectedBranches.extract(md)
  end

  def test_host_extended_list
    md = project_md("- **Protected branches:** `main`, `master`, `develop`, `release` — extended.")
    assert_equal %w[main master develop release], ProtectedBranches.extract(md)
  end

  def test_deduplicates
    md = project_md("- **Protected branches:** `main`, `main`, `develop` — dupes collapse.")
    assert_equal %w[main develop], ProtectedBranches.extract(md)
  end

  def test_line_with_no_em_dash_collects_whole_line
    md = project_md("- **Protected branches:** `main`, `master`")
    assert_equal %w[main master], ProtectedBranches.extract(md)
  end

  # --- extract: degenerate inputs → [] (caller applies fail-closed default) ----------------------

  def test_missing_section_returns_empty
    md = <<~MD
      # Project Config
      ## Quality Checks
      ## Lifecycle Host
    MD
    assert_empty ProtectedBranches.extract(md)
  end

  def test_section_without_protected_line_returns_empty
    md = <<~MD
      # Project Config
      ## Branch & PR Policy
      - **Branch naming:** `feature/` prefixes.
      ## Lifecycle Host
    MD
    assert_empty ProtectedBranches.extract(md)
  end

  def test_stops_at_next_section
    # A protected-branches line that appears AFTER the section ends must not be picked up.
    md = <<~MD
      # Project Config
      ## Branch & PR Policy
      - **Branch naming:** `feature/`.
      ## Lifecycle Host
      - **Protected branches:** `sneaky`.
    MD
    assert_empty ProtectedBranches.extract(md)
  end

  # --- CLI (subprocess: proves the real bin/protected-branches artifact) --------------------------

  def test_cli_prints_one_branch_per_line
    Dir.mktmpdir do |dir|
      path = File.join(dir, "PROJECT.md")
      File.write(path, project_md("- **Protected branches:** `main`, `develop` — x."))
      out = IO.popen([RUBY, CLI, "--file", path], &:read)
      assert_equal 0, $?.exitstatus
      assert_equal "main\ndevelop\n", out
    end
  end

  def test_cli_errors_on_missing_file
    Dir.mktmpdir do |dir|
      out = IO.popen([RUBY, CLI, "--file", File.join(dir, "nope.md")], err: [:child, :out], &:read)
      refute_equal 0, $?.exitstatus
      assert_match(/no such file/i, out)
    end
  end

  # --- the REAL PROJECT.md resolves to the committed sidecar (drift guard, mirrors parity) --------

  def test_real_project_md_matches_committed_sidecar
    root = File.expand_path("..", __dir__)
    sidecar = File.join(root, ".githooks", "protected-branches")
    skip "no sidecar present" unless File.file?(sidecar)

    derived = ProtectedBranches.from_file(File.join(root, "PROJECT.md"))
    committed = File.read(sidecar).lines.map(&:strip).reject { |l| l.empty? || l.start_with?("#") }
    assert_equal derived, committed,
                 "`.githooks/protected-branches` is stale — run bin/install-git-hooks"
  end
end
