# frozen_string_literal: true

# Self-test for bin/ai-config-sync. An installer with no test is a false green: these fixtures prove
# it produces a clean, owned copy (acceptance criterion #1), excludes repo-meta and tool-local
# settings, preserves the Host App's PROJECT.md on re-sync, tolerates a partial/growing bundle, and
# that a vendored copy's OWN parity check still passes. Stdlib only (minitest, tmpdir, fileutils,
# rbconfig) — no bundler, mirroring test/parity_check_test.rb and ADR 0008.
#
# Run: ruby test/ai_config_sync_test.rb

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "rbconfig"

class AiConfigSyncTest < Minitest::Test
  SCRIPT = File.expand_path("../bin/ai-config-sync", __dir__)
  PARITY = File.expand_path("../scripts/parity_check.rb", __dir__)
  REPO_ROOT = File.expand_path("..", __dir__)
  RUBY = RbConfig.ruby

  # Writes a minimal, parity-valid Generic-Baseline-shaped source bundle into `dir`, plus the
  # repo-meta and tool-local files that must NOT be vendored.
  def build_source(dir)
    File.write(File.join(dir, "AGENTS.md"),
               "# Canonical\n\nSee [config](PROJECT.md) and [adr](docs/adr/0001.md).\n")
    File.write(File.join(dir, "CLAUDE.md"), "@AGENTS.md\n")
    File.write(File.join(dir, "GEMINI.md"), "@AGENTS.md\n")
    File.write(File.join(dir, "CONTEXT.md"), "# Glossary\n")
    File.write(File.join(dir, "PROJECT.md"), project_md)
    FileUtils.mkdir_p(File.join(dir, ".github/workflows"))
    File.write(File.join(dir, ".github/copilot-instructions.md"),
               "<!-- parity:native source=AGENTS.md -->\n\n[canonical](../AGENTS.md)\n")
    File.write(File.join(dir, ".github/workflows/parity.yml"), "name: parity\n")
    FileUtils.mkdir_p(File.join(dir, "docs/adr"))
    File.write(File.join(dir, "docs/adr/0001.md"), "# ADR 0001\n")
    FileUtils.mkdir_p(File.join(dir, "scripts"))
    File.write(File.join(dir, "scripts/parity_check.rb"), "puts 'ok'\n")
    # Tool-local + repo-meta that MUST be excluded:
    FileUtils.mkdir_p(File.join(dir, ".claude"))
    File.write(File.join(dir, ".claude/settings.json"), "{}\n")
    File.write(File.join(dir, ".claude/settings.local.json"), "{\"local\":true}\n")
    FileUtils.mkdir_p(File.join(dir, "bin"))
    File.write(File.join(dir, "bin/ai-config-sync"), "#!/usr/bin/env ruby\n")
    File.write(File.join(dir, "README.md"), "# config repo readme\n")
    File.write(File.join(dir, "LICENSE"), "MIT\n")
    File.write(File.join(dir, ".gitignore"), "*.local\n")
    FileUtils.mkdir_p(File.join(dir, "test"))
    File.write(File.join(dir, "test/ai_config_sync_test.rb"), "# self\n")
    dir
  end

  def project_md
    <<~MD
      # Project Config
      ## Quality Checks
      ## Attribution & Model Declaration
      ## Branch & PR Policy
      ## Review Severity Framework
      ## Lifecycle Host
    MD
  end

  # Runs the installer as a real subprocess (stderr merged into stdout). Returns [output, exit_status].
  def sync(target, *args, from:)
    out = IO.popen([RUBY, SCRIPT, "--from", from, *args, target], err: [:child, :out], &:read)
    [out, $?.exitstatus]
  end

  # ---- acceptance criterion #1: a clean, owned copy ----
  def test_produces_clean_owned_copy
    Dir.mktmpdir do |src|
      Dir.mktmpdir do |dst|
        build_source(src)
        out, status = sync(dst, from: src)
        assert_equal 0, status, out
        %w[AGENTS.md CLAUDE.md GEMINI.md CONTEXT.md PROJECT.md
           .github/copilot-instructions.md .github/workflows/parity.yml
           docs/adr/0001.md scripts/parity_check.rb .claude/settings.json].each do |rel|
          path = File.join(dst, rel)
          assert File.file?(path), "expected #{rel} to be vendored"
          refute File.symlink?(path), "#{rel} must be a real file, not a symlink"
        end
      end
    end
  end

  # ---- exclusions: repo-meta and tool-local settings are never vendored ----
  def test_excludes_repo_meta_and_local_settings
    Dir.mktmpdir do |src|
      Dir.mktmpdir do |dst|
        build_source(src)
        sync(dst, from: src)
        %w[README.md LICENSE .gitignore bin/ai-config-sync bin
           .claude/settings.local.json test/ai_config_sync_test.rb test].each do |rel|
          refute File.exist?(File.join(dst, rel)), "#{rel} must NOT be vendored"
        end
      end
    end
  end

  # ---- PROJECT.md is the Customization surface: preserved once it exists ----
  def test_preserves_existing_project_md
    Dir.mktmpdir do |src|
      Dir.mktmpdir do |dst|
        build_source(src)
        custom = "# HOST CUSTOMIZED\n"
        File.write(File.join(dst, "PROJECT.md"), custom)
        out, status = sync(dst, from: src)
        assert_equal 0, status, out
        assert_equal custom, File.read(File.join(dst, "PROJECT.md"))
        assert_match(/preserved/i, out)
      end
    end
  end

  def test_first_vendor_copies_project_md
    Dir.mktmpdir do |src|
      Dir.mktmpdir do |dst|
        build_source(src)
        sync(dst, from: src)
        assert_equal project_md, File.read(File.join(dst, "PROJECT.md"))
      end
    end
  end

  def test_force_overwrites_project_md
    Dir.mktmpdir do |src|
      Dir.mktmpdir do |dst|
        build_source(src)
        File.write(File.join(dst, "PROJECT.md"), "# HOST\n")
        out, status = sync(dst, "--force", from: src)
        assert_equal 0, status, out
        assert_equal project_md, File.read(File.join(dst, "PROJECT.md"))
      end
    end
  end

  # ---- default behavior: baseline files are overwritten (update = re-run + manual merge) ----
  def test_overwrites_baseline_file
    Dir.mktmpdir do |src|
      Dir.mktmpdir do |dst|
        build_source(src)
        File.write(File.join(dst, "AGENTS.md"), "# STALE\n")
        sync(dst, from: src)
        assert_equal File.read(File.join(src, "AGENTS.md")), File.read(File.join(dst, "AGENTS.md"))
      end
    end
  end

  # ---- dry-run previews without writing ----
  def test_dry_run_writes_nothing
    Dir.mktmpdir do |src|
      Dir.mktmpdir do |dst|
        build_source(src)
        out, status = sync(dst, "--dry-run", from: src)
        assert_equal 0, status, out
        assert_empty Dir.children(dst), "dry-run must not write to the target"
        assert_match(/dry-run/i, out)
      end
    end
  end

  # ---- partial/growing bundle: a missing source surface is skipped, not an error ----
  def test_skips_missing_sources
    Dir.mktmpdir do |src|
      Dir.mktmpdir do |dst|
        build_source(src) # no skills/ or rules/ — those land in later baseline issues
        out, status = sync(dst, from: src)
        assert_equal 0, status, out
        refute File.exist?(File.join(dst, "skills"))
        refute File.exist?(File.join(dst, "rules"))
      end
    end
  end

  # ---- link integrity: a copy of the REAL bundle passes its own parity check in-host ----
  def test_vendored_copy_passes_parity_check
    Dir.mktmpdir do |dst|
      out, status = sync(dst, from: REPO_ROOT)
      assert_equal 0, status, out
      parity = IO.popen([RUBY, PARITY, "--root", dst], err: [:child, :out], &:read)
      assert_equal 0, $?.exitstatus, "vendored copy failed parity_check:\n#{parity}"
    end
  end

  # ---- edge cases / guards ----
  def test_missing_target_errors
    Dir.mktmpdir do |src|
      build_source(src)
      out = IO.popen([RUBY, SCRIPT, "--from", src], err: [:child, :out], &:read)
      refute_equal 0, $?.exitstatus
      assert_match(/target/i, out)
    end
  end

  def test_non_directory_target_errors
    Dir.mktmpdir do |src|
      build_source(src)
      out, status = sync(File.join(src, "AGENTS.md"), from: src)
      refute_equal 0, status
      assert_match(/not a directory/i, out)
    end
  end

  def test_refuses_target_equal_source
    Dir.mktmpdir do |src|
      build_source(src)
      out, status = sync(src, from: src)
      refute_equal 0, status
      assert_match(/onto itself/i, out)
    end
  end
end
