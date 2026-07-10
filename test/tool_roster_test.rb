# frozen_string_literal: true

# Data-contract self-test for docs/reference/tool-roster.yml — the Tool Roster (issue #83, ADR 0023).
# The Tool Roster is a structured YAML snapshot of AI coding harnesses & models; nothing else lints it, so a
# malformed or dishonestly-shaped entry would otherwise ship green. This test asserts the schema
# invariants documented in the file's own header — NOT *which* products are listed: it stays business-
# neutral (structure & provenance discipline only, never identity). Stdlib only (minitest, yaml, date),
# mirroring test/voices_watchlist_test.rb and ADR 0008.
#
# Run: ruby test/tool_roster_test.rb

require "minitest/autorun"
require "yaml"
require "date"

class ToolRosterTest < Minitest::Test
  TOOL_ROSTER = File.expand_path("../docs/reference/tool-roster.yml", __dir__)

  STATUSES        = %w[active in-flux dormant].freeze
  EFFORT_TIERS    = %w[low medium high xhigh max].freeze
  CONFIG_FEATURES = %w[hooks skill-shims mcp subagents plugins agents-md].freeze
  MATURITIES      = %w[ga preview].freeze
  URL_RE          = %r{\Ahttps?://\S+\z}.freeze

  def setup
    # `verified:`/`as_of:` are ISO dates, so a plain safe_load would raise Psych::DisallowedClass.
    @doc = YAML.safe_load(File.read(TOOL_ROSTER), permitted_classes: [Date])
  end

  def harnesses
    @doc.fetch("harnesses")
  end

  def models
    @doc.fetch("models")
  end

  def model_names
    models.map { |m| m["name"] }
  end

  # --- shape ---

  def test_parses_with_nonempty_harness_and_model_lists
    assert_kind_of Hash, @doc, "tool-roster.yml must parse to a mapping"
    assert_kind_of Array, harnesses, "top-level `harnesses:` must be a list"
    assert_kind_of Array, models, "top-level `models:` must be a list"
    refute_empty harnesses, "the Tool Roster must carry at least one harness"
    refute_empty models, "the Tool Roster must carry at least one model"
  end

  # --- the real seed obeys every invariant (happy path) ---

  def test_every_harness_entry_is_valid
    harnesses.each do |e|
      errs = entry_errors(e, kind: :harness)
      assert_empty errs, "harness #{e['name'].inspect}: #{errs.join('; ')}"
    end
  end

  def test_every_model_entry_is_valid
    models.each do |e|
      errs = entry_errors(e, kind: :model)
      assert_empty errs, "model #{e['name'].inspect}: #{errs.join('; ')}"
    end
  end

  def test_names_are_unique_within_each_category
    { harness: harnesses, model: models }.each do |kind, list|
      names = list.map { |e| e["name"] }
      assert_equal names.uniq, names, "duplicate #{kind} name in the Tool Roster"
    end
  end

  def test_every_house_model_resolves_or_is_varies
    harnesses.each do |h|
      hm = h["house_model"]
      next if hm == "varies"
      assert_includes model_names, hm, "#{h['name']}: house_model #{hm.inspect} has no models entry"
    end
  end

  # --- malformed entries are rejected (sad paths) ---

  def test_rejects_missing_required_field
    assert_includes entry_errors(valid_model.tap { |h| h.delete("vendor") }, kind: :model), "missing `vendor`"
  end

  def test_rejects_status_out_of_set
    errs = entry_errors(valid_model.merge("status" => "cooking"), kind: :model)
    assert(errs.any? { |m| m.include?("`status`") }, errs.inspect)
  end

  def test_rejects_non_date_verified
    errs = entry_errors(valid_model.merge("verified" => "recently"), kind: :model)
    assert(errs.any? { |m| m.include?("`verified`") }, errs.inspect)
  end

  def test_rejects_placeholder_source_url
    errs = entry_errors(valid_model.merge("sources" => ["TODO"]), kind: :model)
    assert(errs.any? { |m| m.include?("source") }, errs.inspect)
  end

  def test_rejects_empty_sources
    errs = entry_errors(valid_model.merge("sources" => []), kind: :model)
    assert(errs.any? { |m| m.include?("`sources`") }, errs.inspect)
  end

  def test_rejects_dangling_house_model
    errs = entry_errors(valid_harness.merge("house_model" => "Nonexistent Model"), kind: :harness)
    assert(errs.any? { |m| m.include?("house_model") }, errs.inspect)
  end

  def test_accepts_varies_house_model
    assert_empty entry_errors(valid_harness.merge("house_model" => "varies"), kind: :harness)
  end

  def test_rejects_unflagged_estimate
    errs = entry_errors(valid_model.merge("dumb_zone" => { "value" => "~60% ctx" }), kind: :model)
    assert(errs.any? { |m| m.include?("estimated") }, errs.inspect)
  end

  def test_rejects_benchmark_without_source_or_as_of
    errs = entry_errors(valid_model.merge("swe_bench_verified" => { "score" => 90.0 }), kind: :model)
    assert(errs.any? { |m| m.include?("swe_bench_verified") }, errs.inspect)
  end

  def test_rejects_api_cost_missing_output
    errs = entry_errors(valid_model.merge("api_cost" => { "input" => 5 }), kind: :model)
    assert(errs.any? { |m| m.include?("api_cost") }, errs.inspect)
  end

  def test_rejects_unknown_effort_tier
    errs = entry_errors(valid_model.merge("effort_tiers" => %w[low turbo]), kind: :model)
    assert(errs.any? { |m| m.include?("effort_tiers") }, errs.inspect)
  end

  def test_rejects_unknown_config_feature
    errs = entry_errors(valid_harness.merge("config_features" => %w[telepathy]), kind: :harness)
    assert(errs.any? { |m| m.include?("config_features") }, errs.inspect)
  end

  def test_rejects_unknown_maturity
    errs = entry_errors(valid_model.merge("maturity" => "beta"), kind: :model)
    assert(errs.any? { |m| m.include?("maturity") }, errs.inspect)
  end

  private

  # Returns the list of invariant violations for one entry (empty == valid).
  def entry_errors(entry, kind:)
    return ["entry is not a mapping"] unless entry.is_a?(Hash)

    errs = []
    %w[name vendor stable_version verified status sources].each do |f|
      errs << "missing `#{f}`" if blank?(entry[f])
    end
    errs << "`status` #{entry['status'].inspect} out of set" unless STATUSES.include?(entry["status"])
    errs << "`verified` must be a YYYY-MM-DD date" unless entry["verified"].is_a?(Date)

    sources = entry["sources"]
    if !sources.is_a?(Array) || sources.empty?
      errs << "`sources` must be a non-empty list of URLs"
    else
      sources.each { |s| errs << "source #{s.inspect} is not a URL" unless s.to_s.match?(URL_RE) }
    end

    if entry.key?("version_date") && !entry["version_date"].is_a?(Date)
      errs << "`version_date` must be a YYYY-MM-DD date when present"
    end
    if entry.key?("maturity") && !MATURITIES.include?(entry["maturity"])
      errs << "`maturity` #{entry['maturity'].inspect} out of set (ga | preview)"
    end

    kind == :harness ? harness_errors(entry, errs) : model_errors(entry, errs)
    errs
  end

  def harness_errors(entry, errs)
    hm = entry["house_model"]
    if blank?(hm)
      errs << "harness missing `house_model` (use `varies` for a picker)"
    elsif hm != "varies" && !model_names.include?(hm)
      errs << "`house_model` #{hm.inspect} does not resolve to a models entry"
    end
    return unless entry.key?("config_features")

    cf = entry["config_features"]
    if !cf.is_a?(Array)
      errs << "`config_features` must be a list"
    elsif !(bad = cf - CONFIG_FEATURES).empty?
      errs << "`config_features` has unknown #{bad.inspect}"
    end
  end

  def model_errors(entry, errs)
    if entry.key?("effort_tiers")
      et = entry["effort_tiers"]
      if !et.is_a?(Array)
        errs << "`effort_tiers` must be a list"
      elsif !(bad = et - EFFORT_TIERS).empty?
        errs << "`effort_tiers` has unknown #{bad.inspect}"
      end
    end
    if entry.key?("api_cost")
      ac = entry["api_cost"]
      unless ac.is_a?(Hash) && ac["input"].is_a?(Numeric) && ac["output"].is_a?(Numeric)
        errs << "`api_cost` must have numeric `input` and `output`"
      end
    end
    if entry.key?("swe_bench_verified")
      b = entry["swe_bench_verified"]
      ok = b.is_a?(Hash) && b["score"].is_a?(Numeric) && b["source"].to_s.match?(URL_RE) && b["as_of"].is_a?(Date)
      errs << "`swe_bench_verified` needs numeric `score`, URL `source`, and Date `as_of`" unless ok
    end
    return unless entry.key?("dumb_zone")

    dz = entry["dumb_zone"]
    unless dz.is_a?(Hash) && !blank?(dz["value"]) && dz["estimated"] == true
      errs << "`dumb_zone` must carry a `value` and `estimated: true` (a guess, always flagged)"
    end
  end

  def valid_model
    {
      "name" => "Fixture Model", "vendor" => "Acme", "stable_version" => "1.0",
      "verified" => Date.new(2026, 7, 10), "status" => "active",
      "sources" => ["https://example.com/pricing"]
    }
  end

  def valid_harness
    {
      "name" => "Fixture Harness", "vendor" => "Acme", "stable_version" => "1.0",
      "verified" => Date.new(2026, 7, 10), "status" => "active",
      "sources" => ["https://example.com/releases"], "house_model" => "varies"
    }
  end

  def blank?(value)
    value.nil? || value.to_s.strip.empty?
  end
end
