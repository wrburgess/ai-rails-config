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

class ParityCheck
  CANONICAL = "AGENTS.md"

  # Import Adapters: files that must carry a resolvable `@AGENTS.md` import.
  IMPORT_ADAPTERS = ["CLAUDE.md", "GEMINI.md"].freeze

  COPILOT_ADAPTER = ".github/copilot-instructions.md"
  PROJECT_CONFIG = "PROJECT.md"

  # Files whose relative markdown links must resolve.
  LINK_CHECKED = [
    "AGENTS.md",
    "CLAUDE.md",
    "GEMINI.md",
    "PROJECT.md",
    ".github/copilot-instructions.md",
  ].freeze

  # Required PROJECT.md H2 sections (verbatim). This is the parity contract with PROJECT.md.
  REQUIRED_PROJECT_SECTIONS = [
    "## Quality Checks",
    "## Attribution & Model Declaration",
    "## Branch & PR Policy",
    "## Review Severity Framework",
    "## Lifecycle Host",
  ].freeze

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
    check_guardrails
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
      unless read(adapter).match?(IMPORT_TOKEN)
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

      lines = read(rel).lines
      open_i = lines.index { |l| l.strip.match?(RENDER_OPEN) }
      next unless open_i

      close_i = lines[(open_i + 1)..].index { |l| l.strip.match?(RENDER_CLOSE) }
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
          "#{derived.inspect} — run bin/install-git-hooks to regenerate it")
    end
  end

  # Every repo-relative markdown link in the checked files must resolve to an existing path.
  # Skips external (http/https/mailto) and bare-anchor (#...) links.
  def check_links
    link_re = /\[[^\]]*\]\(([^)]+)\)/
    LINK_CHECKED.each do |rel|
      next unless exist?(rel)

      dir = File.dirname(path(rel))
      read(rel).scan(link_re).each do |(target)|
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

  def report
    if @errors.empty?
      puts "parity_check: OK — Canonical Source, #{IMPORT_ADAPTERS.length + 1} Adapters, Project Config, and links all resolve."
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
