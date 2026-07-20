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
require "digest"

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

  # Stable digest of a directory tree (relative path + file content), for idempotency assertions.
  def tree_digest(dir)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: dir).sort.reduce(Digest::SHA256.new) do |acc, rel|
      path = File.join(dir, rel)
      next acc if File.directory?(path)

      acc.update(rel).update("\0").update(File.read(path)).update("\0")
    end.hexdigest
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

  # ---- idempotent: a second run leaves the same state (overwrites baseline, keeps PROJECT.md) ----
  def test_idempotent_on_rerun
    Dir.mktmpdir do |src|
      Dir.mktmpdir do |dst|
        build_source(src)
        sync(dst, from: src)
        custom = "# HOST CUSTOMIZED\n"
        File.write(File.join(dst, "PROJECT.md"), custom) # host customizes after first vendor
        after_first = tree_digest(dst)
        out, status = sync(dst, from: src)               # re-sync
        assert_equal 0, status, out
        assert_equal after_first, tree_digest(dst), "re-run must be idempotent"
        assert_equal custom, File.read(File.join(dst, "PROJECT.md")), "re-run must keep host PROJECT.md"
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

  # ---- host-owned test/ tree: vendoring must neither touch it nor imply bundle self-tests ----
  # Regression for the PR #101 Codex review finding: a Host App commonly owns an unrelated test/
  # tree (Rails, Minitest). Vendoring must leave it alone AND copy none of the bundle's self-tests
  # into it — the pair of facts the workflow's sentinel gating (below) relies on.
  def test_vendoring_into_host_with_own_test_tree_leaves_it_alone
    Dir.mktmpdir do |src|
      Dir.mktmpdir do |dst|
        build_source(src)
        FileUtils.mkdir_p(File.join(dst, "test"))
        host_test = "# host-owned test\n"
        File.write(File.join(dst, "test/host_app_test.rb"), host_test)

        out, status = sync(dst, from: src)
        assert_equal 0, status, out
        assert_equal host_test, File.read(File.join(dst, "test/host_app_test.rb")),
                     "host-owned test file must be untouched"
        refute File.exist?(File.join(dst, "test/ai_config_sync_test.rb")),
               "bundle self-tests must NOT be vendored into a host-owned test/ tree"
      end
    end
  end

  # The REAL workflow must gate every test/-running step on the EXACT file it runs (a repo-only
  # sentinel), never on `test/` existing — a host's own test/ directory would flip a directory
  # gate to true and send CI hunting for un-vendored bundle files (issue #95 reintroduced).
  def test_workflow_self_test_steps_are_sentinel_gated
    require "yaml"
    workflow = YAML.safe_load(File.read(File.join(REPO_ROOT, ".github/workflows/parity.yml")))
    steps = workflow.fetch("jobs").fetch("parity").fetch("steps")
    gated = steps.select { |s| s["run"]&.match?(%r{\btest/}) }
    refute_empty gated, "expected the workflow to carry test/ self-test steps"
    gated.each do |step|
      file = step["run"][%r{test/[\w.-]+}]
      cond = step["if"].to_s
      assert_includes cond, "hashFiles('#{file}')",
                      "step #{step['name'].inspect} must be gated on its exact sentinel #{file}, " \
                      "got if: #{cond.inspect}"
      refute_match(/\[\s*-d\s+test\s*\]/, cond, "directory-presence gates are forbidden")
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

  # ---- executable bit survives vendoring (the git hooks + guards must stay runnable) ----
  def test_preserves_executable_bit_on_vendored_scripts
    Dir.mktmpdir do |src|
      Dir.mktmpdir do |dst|
        build_source(src)
        FileUtils.mkdir_p(File.join(src, ".githooks"))
        hook = File.join(src, ".githooks/pre-commit")
        File.write(hook, "#!/usr/bin/env bash\n")
        File.chmod(0o755, hook)
        guard = File.join(src, "bin/guard-protected-branch")
        File.write(guard, "#!/usr/bin/env bash\n")
        File.chmod(0o755, guard)

        out, status = sync(dst, from: src)
        assert_equal 0, status, out
        assert File.executable?(File.join(dst, ".githooks/pre-commit")),
               "vendored git hook must stay executable"
        assert File.executable?(File.join(dst, "bin/guard-protected-branch")),
               "vendored guard must stay executable"
      end
    end
  end

  # ---- bin/setup is a preserved surface: a host's own setup is never clobbered on re-sync ----
  def test_preserves_existing_bin_setup
    Dir.mktmpdir do |src|
      Dir.mktmpdir do |dst|
        build_source(src)
        File.write(File.join(src, "bin/setup"), "#!/usr/bin/env ruby\n# baseline setup\n")
        FileUtils.mkdir_p(File.join(dst, "bin"))
        host = "#!/usr/bin/env ruby\n# HOST RAILS SETUP\n"
        File.write(File.join(dst, "bin/setup"), host)

        out, status = sync(dst, from: src)
        assert_equal 0, status, out
        assert_equal host, File.read(File.join(dst, "bin/setup")), "host bin/setup must be preserved"
        assert_match(/preserved/i, out)
      end
    end
  end

  def test_first_vendor_copies_bin_setup
    Dir.mktmpdir do |src|
      Dir.mktmpdir do |dst|
        build_source(src)
        baseline = "#!/usr/bin/env ruby\n# baseline setup\n"
        File.write(File.join(src, "bin/setup"), baseline)

        sync(dst, from: src)
        assert_equal baseline, File.read(File.join(dst, "bin/setup"))
      end
    end
  end

  def test_force_overwrites_bin_setup
    Dir.mktmpdir do |src|
      Dir.mktmpdir do |dst|
        build_source(src)
        baseline = "#!/usr/bin/env ruby\n# baseline setup\n"
        File.write(File.join(src, "bin/setup"), baseline)
        FileUtils.mkdir_p(File.join(dst, "bin"))
        File.write(File.join(dst, "bin/setup"), "# HOST\n")

        out, status = sync(dst, "--force", from: src)
        assert_equal 0, status, out
        assert_equal baseline, File.read(File.join(dst, "bin/setup"))
      end
    end
  end
end
