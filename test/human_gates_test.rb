# frozen_string_literal: true

# Self-test for scripts/human_gates.rb. The extractor is the single seam that derives the human-gate
# policy from PROJECT.md (issue #94 / ADR 0025), so it must be exact: parity_check.rb gates on what it
# returns, and one of those gates (merge) is a safety invariant. Stdlib only (minitest), mirroring
# test/protected_branches_test.rb.
#
# Run: ruby test/human_gates_test.rb

require "minitest/autorun"
require_relative "../scripts/human_gates"

class HumanGatesTest < Minitest::Test
  # A PROJECT.md whose Human Gates section carries `rows`, followed by a real next-H2 so the
  # section-boundary behavior is exercised by every happy-path fixture.
  def project_md(rows)
    <<~MD
      # Project Config
      ## Lifecycle Host
      - **Host platform:** `GitHub`
      ## Human Gates

      | Gate | Setting | Allowed values |
      |------|---------|----------------|
      #{rows}

      - Prose about the gates.
      ## Intake Pipeline
      | Artifact | Location |
      |----------|----------|
      | **Watchlist** | `docs/reference/voices.yml` |
    MD
  end

  def both_rows(plan: "required", merge: "required")
    "| **Plan approval** — the option pick and the plan | `#{plan}` | `required` · `auto` |\n" \
      "| **Merge** — the HC merges the delivered PR | `#{merge}` | `required` (not configurable) |"
  end

  # --- happy paths -------------------------------------------------------------------------------

  def test_well_formed_section_parses_both_rows
    gates = HumanGates.extract(project_md(both_rows))
    assert_equal({ plan_approval: "required", merge: "required" }, gates)
    assert_empty HumanGates.invalid(gates)
  end

  def test_plan_approval_auto_parses
    # The one host override the policy allows. If this silently read as `required`, a host that opted
    # into `auto` would get the strict behavior with no error - a false green.
    gates = HumanGates.extract(project_md(both_rows(plan: "auto")))
    assert_equal "auto", gates[:plan_approval]
    assert_equal "required", gates[:merge]
    assert_empty HumanGates.invalid(gates)
  end

  # --- vendored-host compatibility guarantee -----------------------------------------------------

  def test_missing_section_returns_strict_defaults
    # THE compatibility contract: `## Human Gates` is additive and deliberately NOT in the parity
    # check's REQUIRED_PROJECT_SECTIONS, so an already-vendored Host App whose PROJECT.md predates the
    # section must parse to the shipped strict policy and stay green. Fail-SAFE, not fail-closed.
    md = <<~MD
      # Project Config
      ## Quality Checks
      ## Lifecycle Host
      ## Intake Pipeline
    MD
    assert_equal({ plan_approval: "required", merge: "required" }, HumanGates.extract(md))
  end

  # --- section boundary --------------------------------------------------------------------------

  def test_stops_at_next_h2
    # A gate-shaped row AFTER the section ends must not be picked up - otherwise a table row in a
    # later section (or a host's added section) could silently rewrite the policy.
    md = <<~MD
      # Project Config
      ## Human Gates

      | Gate | Setting | Allowed values |
      |------|---------|----------------|
      | **Merge** — the HC merges | `required` | `required` |

      ## Intake Pipeline
      | Gate | Setting |
      |------|---------|
      | **Plan approval** — sneaky | `auto` |
      | **Merge** — sneakier | `auto` |
    MD
    gates = HumanGates.extract(md)
    assert_equal "required", gates[:plan_approval], "bled past the next H2 into ## Intake Pipeline"
    assert_equal "required", gates[:merge], "bled past the next H2 into ## Intake Pipeline"
  end

  # --- the trap protected_branches_test records: stray backticks are not the value ----------------

  def test_backticks_in_other_cells_and_trailing_prose_are_not_the_value
    # `protected_branches.rb` had to stop collecting backticked tokens at the em dash because prose
    # after it carried backticked paths. Same trap here in a different shape: the "Allowed values"
    # cell and the prose bullets below the table are full of backticks, and only the SECOND cell of a
    # labelled row is the setting. `auto` appearing in the allowed-values cell must not win.
    md = <<~MD
      # Project Config
      ## Human Gates

      | Gate | Setting | Allowed values |
      |------|---------|----------------|
      | **Plan approval** — the pick | `required` | `auto` · `required` · `whatever` |
      | **Merge** — the merge | `required` | `required` only |

      - **`auto`** — a host may set plan approval to `auto`; see `PROJECT.md`.
      - Merge is `required` and never `auto`.
      ## Intake Pipeline
    MD
    assert_equal({ plan_approval: "required", merge: "required" }, HumanGates.extract(md))
  end

  # --- invalid values are reported, never coerced ------------------------------------------------

  def test_unknown_value_is_reported_invalid_not_coerced
    # A typo must surface as an error, not silently read as the strict default - otherwise a host
    # believing it set `auto` would get `required` with no signal, and vice versa.
    gates = HumanGates.extract(project_md(both_rows(plan: "sometimes")))
    assert_equal "sometimes", gates[:plan_approval], "coerced an unknown value instead of reporting it"
    assert_equal({ plan_approval: "sometimes" }, HumanGates.invalid(gates))
  end

  def test_merge_auto_is_reported_invalid
    # merge has exactly one legal value: no Host App may express self-merge (ADR 0025).
    gates = HumanGates.extract(project_md(both_rows(merge: "auto")))
    assert_equal "auto", gates[:merge]
    assert_equal({ merge: "auto" }, HumanGates.invalid(gates))
  end

  # --- partial section ---------------------------------------------------------------------------

  def test_present_section_with_a_missing_row_falls_back_to_that_rows_default
    # A host that authored only the row it cares about must not crash the parser or lose the other
    # gate - the absent row reads as its shipped default.
    rows = "| **Plan approval** — the pick | `auto` | `required` · `auto` |"
    gates = HumanGates.extract(project_md(rows))
    assert_equal "auto", gates[:plan_approval]
    assert_equal "required", gates[:merge], "a missing row must fall back to its default"
    assert_empty HumanGates.invalid(gates)
  end

  # --- row precedence: the FIRST authored row wins ------------------------------------------------

  def test_first_matching_row_wins_for_a_gate
    # THE fail-safe invariant. The extractor must mirror `protected_branches.rb`, which breaks on the
    # FIRST matching line. If a later row could reassign, any second gate-shaped row in the section -
    # an illustrative example, a copy/paste leftover, a malicious edit - would silently override the
    # authored setting, and it would fail in the UNSAFE direction (`required` quietly becoming `auto`).
    rows = "| **Plan approval** — the authored row | `required` | `required` · `auto` |\n" \
           "| **Merge** — the authored row | `required` | `required` |\n" \
           "| **Plan approval** — a later row | `auto` | `required` · `auto` |"
    gates = HumanGates.extract(project_md(rows))
    assert_equal "required", gates[:plan_approval], "a later row overrode the first authored row"
    assert_equal "required", gates[:merge]
  end

  def test_second_illustrative_table_cannot_override_the_authored_one
    # The realistic shape of the bug: prose in the section documents what a different host WOULD
    # declare, in a second table. The authored first table must still be the policy.
    md = <<~MD
      # Project Config
      ## Human Gates

      | Gate | Setting | Allowed values |
      |------|---------|----------------|
      | **Plan approval** — the pick | `required` | `required` · `auto` |
      | **Merge** — the merge | `required` | `required` (not configurable) |

      An overnight autonomous track would instead declare:

      | Gate | Setting | Allowed values |
      |------|---------|----------------|
      | **Plan approval** — the pick | `auto` | `required` · `auto` |
      | **Merge** — the merge | `required` | `required` (not configurable) |
      ## Intake Pipeline
    MD
    assert_equal({ plan_approval: "required", merge: "required" }, HumanGates.extract(md),
                 "an illustrative second table overrode the authored first table")
  end

  def test_value_cell_without_backticks_falls_back_to_that_rows_default
    # An unbackticked cell is malformed, not an authored value. It reads as the shipped default (the
    # safe direction) rather than picking up the bare word or bleeding to a later row.
    rows = "| **Plan approval** — the pick | auto | `required` · `auto` |\n" \
           "| **Merge** — the merge | `required` | `required` |"
    gates = HumanGates.extract(project_md(rows))
    assert_equal "required", gates[:plan_approval], "a bare, unbackticked cell was read as a value"
    assert_empty HumanGates.invalid(gates)
  end

  # --- the Setting column is located by its header, not by position ------------------------------

  def test_setting_column_is_located_by_its_header
    # A host that reorders the table's columns must not silently get the wrong value. The column is
    # keyed off the header cell named "Setting"; here that is the THIRD column, and the second column
    # (allowed values) leads with `required` - which is exactly what a positional read would return.
    md = <<~MD
      # Project Config
      ## Human Gates

      | Gate | Allowed values | Setting |
      |------|----------------|---------|
      | **Plan approval** — the pick | `required` · `auto` | `auto` |
      | **Merge** — the merge | `required` (not configurable) | `required` |
      ## Intake Pipeline
    MD
    gates = HumanGates.extract(md)
    assert_equal "auto", gates[:plan_approval], "read the wrong column when the host reordered them"
    assert_equal "required", gates[:merge]
    assert_empty HumanGates.invalid(gates)
  end

  def test_column_falls_back_to_the_second_when_no_header_names_setting
    # Fail-safe for a host that renamed the header: the documented default position still applies, so
    # a renamed header degrades to the old behavior instead of losing the value entirely.
    md = <<~MD
      # Project Config
      ## Human Gates

      | Gate | Value |
      |------|-------|
      | **Plan approval** — the pick | `auto` |
      | **Merge** — the merge | `required` |
      ## Intake Pipeline
    MD
    assert_equal({ plan_approval: "auto", merge: "required" }, HumanGates.extract(md))
  end

  # --- data contract: the REAL shipped PROJECT.md ------------------------------------------------

  def test_real_project_md_ships_the_strict_defaults
    # The neutral-default guarantee (mirrors protected_branches_test's committed-sidecar drift guard):
    # the Generic Baseline must ship the STRICT policy, so vendoring it changes no host's behavior.
    # If someone flips the shipped default to `auto`, every vendoring host silently loses its gate.
    root = File.expand_path("..", __dir__)
    gates = HumanGates.from_file(File.join(root, "PROJECT.md"))
    assert_equal({ plan_approval: "required", merge: "required" }, gates,
                 "the shipped PROJECT.md must declare the strict baseline policy")
  end
end
