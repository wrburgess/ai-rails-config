# frozen_string_literal: true

# human_gates.rb — the ONE place that derives the human-gate policy from PROJECT.md (issue #94 /
# ADR 0025). PROJECT.md is the single authored source; `scripts/parity_check.rb` validates what this
# returns. Parsing lives here so it is unit-tested once and reused, mirroring
# `scripts/protected_branches.rb` (the protected-branch value, ADR 0009).
#
# Dependency-free: Ruby standard library only, mirroring scripts/parity_check.rb (ADR 0008).
#
# Contract with PROJECT.md -> "## Human Gates":
#   - the settings are authored as a markdown table between that H2 and the next line starting `## `
#   - a row is identified by its FIRST cell starting with the gate's label ("Plan approval", "Merge"),
#     ignoring markdown emphasis
#   - the value is the first `backticked` token in that row's SECOND cell. Only the second cell is
#     read, so the "Allowed values" cell and any backticked prose elsewhere in the section can never be
#     mistaken for the setting.
#
# Fail-SAFE, not fail-closed: when the section (or a row) is absent, the SHIPPED DEFAULT is returned
# rather than [] or nil. The section is additive — an already-vendored Host App whose PROJECT.md
# predates it must keep parsing to the strict baseline policy and stay green, which is exactly why the
# heading is deliberately NOT in the parity check's REQUIRED_PROJECT_SECTIONS.
#
# Values are returned VERBATIM: an unknown value is never coerced to a default, so a typo surfaces as
# an invalid value (see `invalid`) instead of silently reading as the strict policy.

module HumanGates
  SECTION = "## Human Gates"

  # The Generic Baseline's strict policy, and the answer for any absent section/row.
  DEFAULTS = { plan_approval: "required", merge: "required" }.freeze

  # `merge` allows exactly one value: no Host App may express self-merge (ADR 0025).
  ALLOWED = { plan_approval: %w[required auto].freeze, merge: %w[required].freeze }.freeze

  # First-cell labels that identify each gate's row.
  ROW_LABELS = { plan_approval: "Plan approval", merge: "Merge" }.freeze

  BACKTICKED = /`([^`]+)`/.freeze

  module_function

  # Parse the human-gate settings out of PROJECT.md text. Deterministic; always returns a hash with
  # both keys, defaulting any gate the file does not author.
  def extract(text)
    gates = DEFAULTS.dup
    lines = text.to_s.lines.map(&:chomp)
    start = lines.index { |l| l.strip == SECTION }
    return gates unless start

    lines[(start + 1)..].each do |l|
      break if l.start_with?("## ") # the next H2 ends the section

      cells = table_cells(l)
      next if cells.nil?

      key = ROW_LABELS.keys.find { |k| labelled?(cells[0], ROW_LABELS[k]) }
      next unless key

      value = cells[1][BACKTICKED, 1]
      gates[key] = value.strip if value
    end
    gates
  end

  # The gates whose value is outside their allowed set, as { key => value }. Empty when all are valid.
  # Separated from `extract` so an unknown value is REPORTED rather than coerced.
  def invalid(gates)
    gates.each_with_object({}) do |(key, value), bad|
      allowed = ALLOWED[key]
      bad[key] = value unless allowed.nil? || allowed.include?(value)
    end
  end

  def from_file(path)
    extract(File.read(path, encoding: "UTF-8"))
  end

  # Split a markdown table row into its trimmed cells, or nil when the line is not a data row (the
  # `|---|---|` separator has no letters in its first cell, so `labelled?` rejects it anyway).
  def table_cells(line)
    stripped = line.strip
    return nil unless stripped.start_with?("|")

    cells = stripped.sub(/\A\|/, "").sub(/\|\z/, "").split("|").map(&:strip)
    cells.length >= 2 ? cells : nil
  end

  # True when a row's first cell names this gate — emphasis/backticks stripped, case-insensitive.
  def labelled?(cell, label)
    cell.gsub(/[*`]/, "").strip.downcase.start_with?(label.downcase)
  end
end
