# frozen_string_literal: true

# reviewer.rb — the ONE place that derives the Reviewer declaration from PROJECT.md (issue #114 /
# ADR 0026). PROJECT.md is the single authored source; `scripts/parity_check.rb` validates what this
# returns. Parsing lives here so it is unit-tested once and reused, mirroring `scripts/human_gates.rb`
# (the human-gate policy, ADR 0025) and `scripts/protected_branches.rb` (ADR 0009).
#
# Dependency-free: Ruby standard library only, mirroring scripts/parity_check.rb (ADR 0008).
#
# Contract with PROJECT.md -> "## Reviewer" — DELIBERATELY IDENTICAL to human_gates.rb's, so the two
# readers cannot drift into disagreeing about what a PROJECT.md table row means:
#   - the fields are authored as a markdown table between that H2 and the next line starting `## `
#   - a row is identified by its FIRST cell starting with the field's label ("Primary", "Fallback
#     order", "Bounded window", "Degradation floor"), ignoring markdown emphasis
#   - the FIRST row matching a field is that field's authored setting; later matching rows are ignored,
#     which is what makes the parse fail-SAFE: a second field-shaped row later in the section (an
#     illustrative example, a copy/paste leftover) can never override the authored one
#   - the value is the first `backticked` token in that row's SETTING cell, located by the header cell
#     named "Setting" and falling back to the SECOND cell when no header names it. Only that one cell
#     is read, so the "Allowed values" cell can never be mistaken for the setting, and reordering the
#     table's columns does not silently change the parse.
#
# NOTE on the sub-table: the "### Invocation paths" table lives inside this section and its rows are
# NOT field rows (their first cells are harness names). They are ignored by construction — ROW_LABELS
# matches no harness name — and its `| Harness | Summons | ... |` header does not name a "Setting"
# column, so it cannot rebind the column either. The `break` on a complete field set makes that
# doubly true in the shipped file.
#
# Fail-SAFE, not fail-closed: when the section (or a row) is absent, the SHIPPED DEFAULT is returned
# rather than [] or nil. The section is additive — an already-vendored Host App whose PROJECT.md
# predates it must keep parsing to the shipped defaults and stay green, which is exactly why the
# heading is deliberately NOT in the parity check's REQUIRED_PROJECT_SECTIONS.
#
# Values are returned VERBATIM: an unknown value is never coerced to a default, so a typo surfaces as
# an invalid value (see `invalid`) instead of silently reading as the shipped policy.

module Reviewer
  SECTION = "## Reviewer"

  # The Generic Baseline's shipped declaration, and the answer for any absent section/row. The floor
  # is the load-bearing one: absent everything, a run still stops rather than self-certifying.
  DEFAULTS = {
    primary: "Codex (GPT - host sets model)",
    fallback_order: "Copilot",
    bounded_window: "30m",
    degradation_floor: "stop-and-ask"
  }.freeze

  # `degradation_floor` allows exactly one value: a run that cannot obtain an independent review may
  # not certify itself, so no Host App can express "deliver unreviewed" (ADR 0026 decision 3). This is
  # the same class of hard-fail as `merge` in HumanGates::ALLOWED.
  #
  # `primary` and `fallback_order` are host-named identities, so they are unconstrained here — the
  # baseline cannot know a host's harness roster. `bounded_window` is shape-constrained instead of
  # value-constrained (see WINDOW).
  ALLOWED = { degradation_floor: %w[stop-and-ask].freeze }.freeze

  # The non-configurable floor, named so parity_check.rb can report a floor downgrade with its own
  # policy-boundary message rather than the generic allowed-values one.
  FLOOR_VALUE = "stop-and-ask"

  # A bounded window: a positive integer plus a unit. Zero is rejected — a zero window would make the
  # fallback fire before any reviewer could answer, silently disabling the primary.
  WINDOW = /\A[1-9]\d*[smh]\z/.freeze

  # First-cell labels that identify each field's row. Ordered longest-first within a shared prefix so
  # a `start_with?` match cannot mis-assign one label to another's row.
  ROW_LABELS = {
    primary: "Primary",
    fallback_order: "Fallback order",
    bounded_window: "Bounded window",
    degradation_floor: "Degradation floor"
  }.freeze

  # The header cell that names the value column, and the position assumed when no header names it.
  SETTING_HEADER = "setting"
  DEFAULT_SETTING_COLUMN = 1

  BACKTICKED = /`([^`]+)`/.freeze

  module_function

  # Parse the Reviewer declaration out of PROJECT.md text. Deterministic; always returns a hash with
  # every key, defaulting any field the file does not author.
  def extract(text)
    fields = DEFAULTS.dup
    lines = text.to_s.lines.map(&:chomp)
    start = lines.index { |l| l.strip == SECTION }
    return fields unless start

    column = DEFAULT_SETTING_COLUMN
    authored = {}

    lines[(start + 1)..].each do |l|
      break if l.start_with?("## ") # the next H2 ends the section

      cells = table_cells(l)
      next if cells.nil?

      header = setting_column(cells)
      if header
        column = header # this table names its value column; rows below are read from it
        next
      end

      key = ROW_LABELS.keys.find { |k| labelled?(cells[0], ROW_LABELS[k]) }
      next unless key
      next if authored[key] # FIRST match wins - a later row never overrides the authored one

      authored[key] = true
      value = cells[column] && cells[column][BACKTICKED, 1]
      fields[key] = value.strip if value # a malformed cell leaves the shipped default in place

      break if authored.length == ROW_LABELS.length
    end
    fields
  end

  # The fields whose row was AUTHORED but whose setting cell carries no backticked token, as
  # { key => the raw cell text }. Empty when every authored cell is readable.
  #
  # This exists because `extract` alone cannot express the difference between "the host did not author
  # this field" (fail-SAFE: keep the shipped default, say nothing) and "the host authored it in a form
  # the parser cannot read" (a MISTAKE: keep the shipped default so nothing unsafe is adopted, but say
  # so loudly). Both leave the same value behind, so the distinction has to be reported separately.
  #
  # Without it the checker is blind in exactly the direction that matters: a PROJECT.md declaring
  # `| **Degradation floor** | deliver-unreviewed with a footnote |` - no backticks, which is precisely
  # the prose-where-a-value-belongs form that closed PR #109 - reads back as `stop-and-ask`, reports
  # nothing, and passes green, while the human-readable table the AC actually follows says the
  # opposite.
  #
  # WHAT COUNTS AS UNAUTHORED IS ROW ABSENCE, NOT AN EMPTY CELL. A labelled row that is PRESENT is a
  # host stating "this field is mine to set"; leaving its Setting cell blank is an unfinished edit,
  # not a decision to inherit the default. Treating blank as unauthored reproduced the same
  # machine-vs-agent disagreement this method exists to close - parity green while the table an agent
  # reads has no primary at all (Reviewer finding, PR #117). Absent rows never reach this loop, so
  # they remain silently defaulted, which is the behavior the vendored-host contract needs.
  def unreadable(text)
    bad = {}
    lines = text.to_s.lines.map(&:chomp)
    start = lines.index { |l| l.strip == SECTION }
    return bad unless start

    column = DEFAULT_SETTING_COLUMN
    seen = {}

    lines[(start + 1)..].each do |l|
      break if l.start_with?("## ")

      cells = table_cells(l)
      next if cells.nil?

      header = setting_column(cells)
      if header
        column = header
        next
      end

      key = ROW_LABELS.keys.find { |k| labelled?(cells[0], ROW_LABELS[k]) }
      next unless key
      next if seen[key] # FIRST match wins, mirroring extract

      seen[key] = true
      cell = cells[column].to_s.strip
      bad[key] = cell unless cell.match?(BACKTICKED)

      break if seen.length == ROW_LABELS.length
    end
    bad
  end

  # The fields whose value is outside their allowed set (or malformed), as { key => value }. Empty
  # when all are valid. Separated from `extract` so an unknown value is REPORTED rather than coerced.
  def invalid(fields)
    bad = {}
    fields.each do |key, value|
      allowed = ALLOWED[key]
      bad[key] = value if allowed && !allowed.include?(value)
    end
    window = fields[:bounded_window]
    bad[:bounded_window] = window unless window.to_s.match?(WINDOW)
    bad
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

  # The index of this row's `Setting` header cell, or nil when the row is not a header naming it. A
  # header row is what binds the value column, so a host may reorder the table's columns freely.
  #
  # Column 0 is NEVER bindable: it is the LABEL column that `labelled?` matches rows on, so a value
  # can never live there. Without this guard a host table headed `| Setting | Value |` binds column 0
  # and every field then reads its own label instead of its setting - which silently discards all four
  # host values and hands the checker the shipped defaults, so the non-configurable floor's hard-fail
  # cannot fire on a downgrade that is plainly visible in the file (Reviewer finding, PR #117).
  def setting_column(cells)
    idx = cells.index { |c| c.gsub(/[*`]/, "").strip.downcase == SETTING_HEADER }
    idx&.positive? ? idx : nil
  end

  # True when a row's first cell names this field — emphasis/backticks stripped, case-insensitive.
  def labelled?(cell, label)
    cell.gsub(/[*`]/, "").strip.downcase.start_with?(label.downcase)
  end
end
