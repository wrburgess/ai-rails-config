# frozen_string_literal: true

# Data-contract self-test for docs/reference/voices.yml — the intake-pipeline Watchlist (issue #30).
# voices.yml is the repo's first data YAML and nothing else lints it, so a malformed or under-filled
# entry would otherwise ship green. This test asserts the schema invariants documented in the file's
# own header (and in docs/reference/learnings/README.md), NOT *who* is listed — it stays business-
# neutral: structure only, never identity. Stdlib only (minitest, yaml, date), mirroring ADR 0008.
#
# Run: ruby test/voices_watchlist_test.rb

require "minitest/autorun"
require "yaml"
require "date"

class VoicesWatchlistTest < Minitest::Test
  WATCHLIST = File.expand_path("../docs/reference/voices.yml", __dir__)

  # `verified:` is an ISO date, so a plain safe_load would raise Psych::DisallowedClass — permit Date.
  TIERS     = %w[core trend frontier-lab balance org community].freeze
  STATUSES  = %w[active in-flux dormant].freeze
  CADENCES  = %w[high medium low].freeze
  HANDLE_KEYS = %w[site x youtube github].freeze

  def setup
    @doc = YAML.safe_load(File.read(WATCHLIST), permitted_classes: [Date])
  end

  def voices
    @doc.fetch("voices")
  end

  def test_parses_as_yaml_with_a_nonempty_voices_list
    assert_kind_of Hash, @doc, "voices.yml must parse to a mapping"
    assert_kind_of Array, voices, "top-level `voices:` must be a list"
    refute_empty voices, "the Watchlist must carry at least one entry"
  end

  def test_every_entry_is_a_mapping_with_a_name
    voices.each_with_index do |entry, i|
      assert_kind_of Hash, entry, "entry ##{i} must be a mapping"
      refute blank?(entry["name"]), "entry ##{i} is missing a `name`"
    end
  end

  # Acceptance criterion (#30): every entry has `verified:` and `status:`.
  def test_every_entry_has_verified_and_status
    voices.each do |entry|
      label = entry["name"] || "(unnamed)"
      refute blank?(entry["verified"]), "#{label}: missing `verified`"
      refute blank?(entry["status"]),   "#{label}: missing `status`"
    end
  end

  def test_status_tier_and_cadence_stay_within_the_documented_sets
    voices.each do |entry|
      label = entry["name"] || "(unnamed)"
      assert_includes STATUSES, entry["status"],  "#{label}: `status` out of set"
      assert_includes TIERS,    entry["tier"],    "#{label}: `tier` out of set"
      assert_includes CADENCES, entry["cadence"], "#{label}: `cadence` out of set"
    end
  end

  def test_verified_is_an_iso_date
    voices.each do |entry|
      label = entry["name"] || "(unnamed)"
      assert_kind_of Date, entry["verified"], "#{label}: `verified` must be a YYYY-MM-DD date"
    end
  end

  # No invented / no malformed feeds: an unresolved feed stays `[]`; any listed feed is a real URL.
  # A stray `TODO` or empty string leaking in as a feed *value* fails here.
  def test_every_listed_feed_is_a_url
    voices.each do |entry|
      label = entry["name"] || "(unnamed)"
      feeds = entry["feeds"]
      assert_kind_of Array, feeds, "#{label}: `feeds` must be a list (use `[]` when unresolved)"
      feeds.each do |feed|
        assert_match %r{\Ahttps?://\S+\z}, feed.to_s, "#{label}: feed #{feed.inspect} is not a URL"
      end
    end
  end

  # Every non-null handle is a real URL (the schema frames handles as URLs; `null` is the empty state).
  def test_every_present_handle_is_a_url
    voices.each do |entry|
      label = entry["name"] || "(unnamed)"
      handles = entry["handles"]
      assert_kind_of Hash, handles, "#{label}: `handles` must be a mapping"
      handles.each do |key, value|
        assert_includes HANDLE_KEYS, key, "#{label}: unexpected handle key #{key.inspect}"
        next if value.nil?
        assert_match %r{\Ahttps?://\S+\z}, value.to_s, "#{label}: handle #{key} #{value.inspect} is not a URL"
      end
    end
  end

  private

  def blank?(value)
    value.nil? || value.to_s.strip.empty?
  end
end
