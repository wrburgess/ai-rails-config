# frozen_string_literal: true

# Cross-file parity self-test: the human-readable roster prose (docs/reference/ai-engineering-voices.md,
# issue #27) vs the machine-readable Watchlist (docs/reference/voices.yml, issue #30). The two describe
# the same roster and are kept in sync by the maintenance convention documented in the prose doc;
# nothing else catches the prose silently dropping a voice the Watchlist still lists.
#
# Business-neutral, the same stance as voices_watchlist_test.rb: this asserts a STRUCTURAL relationship,
# never a hardcoded identity. The names are read from voices.yml at runtime, so a Host App that replaces
# BOTH files keeps the invariant — the test source names no one. Gated on both artifacts being present,
# so a bundle shipping only one (or neither) is unaffected — the same "only when present" stance as the
# parity check's rules/skills/guardrails gates. Stdlib only (minitest, yaml, date), per ADR 0008.
#
# Direction is deliberately one-way (Watchlist -> prose): voices.yml is the sweep's source of truth and
# has a strict schema (voices_watchlist_test.rb), so its names are the reliable key set. The reverse
# (every prose entry appears in the Watchlist) would require parsing the prose's mixed heading/bold
# structure — brittle, and out of scope here.
#
# Run: ruby test/voices_roster_parity_test.rb

require "minitest/autorun"
require "yaml"
require "date"

class VoicesRosterParityTest < Minitest::Test
  ROOT      = File.expand_path("..", __dir__)
  WATCHLIST = File.join(ROOT, "docs/reference/voices.yml")
  PROSE     = File.join(ROOT, "docs/reference/ai-engineering-voices.md")

  def both_present?
    File.file?(WATCHLIST) && File.file?(PROSE)
  end

  # The display key for a Watchlist name: the name with a trailing parenthetical stripped. This lets a
  # narrative prose heading ("Latent Space — The AI Engineer Podcast (swyx / Shawn Wang + …)") satisfy
  # the Watchlist name ("Latent Space (swyx + Alessio Fanelli)") without forcing the prose to reproduce
  # the parenthetical verbatim — the prose stays narrative, the invariant stays checkable. No identity
  # is embedded: the key is derived from whatever voices.yml carries at runtime.
  def display_key(name)
    name.sub(/\s*\([^)]*\)\s*\z/, "").strip
  end

  def test_every_watchlist_voice_appears_in_the_prose_roster
    skip "voices.yml and/or ai-engineering-voices.md not present" unless both_present?

    doc   = YAML.safe_load(File.read(WATCHLIST), permitted_classes: [Date])
    prose = File.read(PROSE)

    doc.fetch("voices").each do |entry|
      name = entry["name"]
      # voices_watchlist_test.rb owns the "every entry has a name" invariant; skip blanks here so a
      # missing name fails there (its job), not here (a confusing double-failure).
      next if name.nil? || name.strip.empty?

      key = display_key(name)
      assert prose.include?(key),
             "roster drift: voices.yml lists #{name.inspect} but the prose roster " \
             "(docs/reference/ai-engineering-voices.md) has no entry for #{key.inspect} — " \
             "add it to the prose, or remove it from the Watchlist, so the two stay in sync"
    end
  end
end
