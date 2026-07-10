#!/usr/bin/env ruby
# frozen_string_literal: true

# Renders docs/reference/tool-roster.yml into the committed human-readable table at
# docs/reference/tool-roster.md.
#
# The .md is a GENERATED artifact — never hand-edit it. The `restock` skill runs this on every
# refresh; a human editing the YAML runs it too. A drift-guard test (test/tool_roster_test.rb)
# reddens if the committed .md is stale against the YAML, so the two can never silently diverge
# (this is what makes a committed table safe — ADR 0023).
#
# Deterministic: output is a pure function of the YAML (no timestamps/host state), so the drift test
# is stable across days. Business-neutral mechanism; stdlib only (yaml, date), mirroring ADR 0008.
#
# Run: ruby scripts/render_tool_roster.rb

require "yaml"
require "date"

module ToolRosterRender
  ROOT     = File.expand_path("..", __dir__)
  YAML_REL = "docs/reference/tool-roster.yml"
  MD_REL   = "docs/reference/tool-roster.md"

  module_function

  def load_doc(root = ROOT)
    YAML.safe_load(File.read(File.join(root, YAML_REL)), permitted_classes: [Date])
  end

  def render(doc)
    [header, harness_table(doc.fetch("harnesses")), model_table(doc.fetch("models")), footnote].join("\n") + "\n"
  end

  def header
    <<~MD
      # Tool Roster

      > **Generated file — do not edit by hand.** Rendered from [`tool-roster.yml`](tool-roster.yml)
      > by `scripts/render_tool_roster.rb`, which the [`restock`](../../skills/restock/SKILL.md) skill
      > runs on every refresh. Edit the YAML, not this. Illustrative reference, not the Generic Baseline
      > ([ADR 0023](../adr/0023-tool-roster-facts-tracker-sibling-to-intake.md)).
    MD
  end

  def harness_table(harnesses)
    rows = harnesses.map do |h|
      "| #{h['name']} | #{h['vendor']} | #{version(h)} | #{house_model(h)} | #{list(h['config_features'])} | #{h['status']} |"
    end
    (["## Harnesses", "",
      "| Harness | Vendor | Version (date) | House model | Config surface | Status |",
      "|---|---|---|---|---|---|"] + rows).join("\n") + "\n"
  end

  def model_table(models)
    rows = models.map do |m|
      "| #{m['name']} | #{m['vendor']} | #{version(m)} | #{list(m['effort_tiers'])} | " \
        "#{cost(m['api_cost'])} | #{bench(m['swe_bench_verified'])} | #{maturity(m)} | #{m['status']} |"
    end
    (["## Models", "",
      "| Model | Vendor | Version (date) | Effort tiers | $/Mtok (in·out) | SWE-bench Verified | Maturity | Status |",
      "|---|---|---|---|---|---|---|---|"] + rows).join("\n") + "\n"
  end

  def version(entry)
    entry["version_date"] ? "#{entry['stable_version']} (#{entry['version_date']})" : entry["stable_version"].to_s
  end

  def house_model(harness)
    harness["house_model"] == "varies" ? "*varies* (picker)" : harness["house_model"].to_s
  end

  def list(value)
    value.is_a?(Array) && !value.empty? ? value.join(" · ") : "—"
  end

  def cost(api_cost)
    api_cost ? "#{api_cost['input']} · #{api_cost['output']}" : "—"
  end

  def bench(swe)
    swe ? "#{swe['score']} (#{swe['as_of']})" : "—"
  end

  def maturity(model)
    (model["maturity"] || "ga").to_s == "preview" ? "**Preview**" : "GA"
  end

  def footnote
    "<sub>— = not tracked / not yet sourced (ages honestly; `restock` fills). Prices are per-vendor " \
      "list rates; see each entry's `sources:` in [`tool-roster.yml`](tool-roster.yml) for provenance and " \
      "any tier / introductory-price notes.</sub>\n"
  end
end

if __FILE__ == $PROGRAM_NAME
  doc = ToolRosterRender.load_doc
  File.write(File.join(ToolRosterRender::ROOT, ToolRosterRender::MD_REL), ToolRosterRender.render(doc))
  puts "Rendered #{ToolRosterRender::MD_REL}"
end
