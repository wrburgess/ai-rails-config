# frozen_string_literal: true

# Self-test for scripts/reviewer.rb. The extractor is the single seam that derives the Reviewer
# declaration from PROJECT.md (issue #114 / ADR 0026), so it must be exact: parity_check.rb gates on
# what it returns, and one of those fields (the degradation floor) is a safety invariant on the same
# footing as the merge gate. Stdlib only (minitest), mirroring test/human_gates_test.rb.
#
# Most cases below are sad paths and edge cases on purpose: a fail-SAFE reader's real job is degrading
# correctly on input nobody authored carefully.
#
# Run: ruby test/reviewer_test.rb

require "minitest/autorun"
require_relative "../scripts/reviewer"

class ReviewerTest < Minitest::Test
  # A PROJECT.md whose Reviewer section carries `rows`, followed by a real next-H2 so the
  # section-boundary behavior is exercised by every happy-path fixture.
  def project_md(rows)
    <<~MD
      # Project Config
      ## Lifecycle Host
      - **Host platform:** `GitHub`
      ## Reviewer

      | Field | Setting | Allowed values |
      |-------|---------|----------------|
      #{rows}

      - Prose about the reviewer chain.
      ## Human Gates
      | Gate | Setting | Allowed values |
      |------|---------|----------------|
      | **Plan approval** — the pick | `required` | `required` · `auto` |
    MD
  end

  def all_rows(primary: "Codex", fallback: "Copilot", window: "30m", floor: "stop-and-ask")
    "| **Primary** — summoned first | `#{primary}` | any harness |\n" \
      "| **Fallback order** — tried in turn | `#{fallback}` | comma-separated, or `none` |\n" \
      "| **Bounded window** — wait before falling back | `#{window}` | `<integer><unit>` |\n" \
      "| **Degradation floor** — chain exhausted | `#{floor}` | `stop-and-ask` (not configurable) |"
  end

  # --- happy paths -------------------------------------------------------------------------------

  def test_well_formed_section_parses_every_field
    fields = Reviewer.extract(project_md(all_rows))
    assert_equal({ primary: "Codex", fallback_order: "Copilot",
                   bounded_window: "30m", degradation_floor: "stop-and-ask" }, fields)
    assert_empty Reviewer.invalid(fields)
  end

  def test_host_named_primary_and_fallback_are_unconstrained
    # The baseline cannot know a host's harness roster, so these are read verbatim and never rejected.
    fields = Reviewer.extract(project_md(all_rows(primary: "Antigravity", fallback: "Grok Build, Copilot")))
    assert_equal "Antigravity", fields[:primary]
    assert_equal "Grok Build, Copilot", fields[:fallback_order]
    assert_empty Reviewer.invalid(fields)
  end

  # --- vendored-host compatibility guarantee -----------------------------------------------------

  def test_missing_section_returns_shipped_defaults
    # THE compatibility contract: `## Reviewer` is additive and deliberately NOT in the parity check's
    # REQUIRED_PROJECT_SECTIONS, so an already-vendored PROJECT.md that predates it must parse to the
    # shipped defaults and stay green - never nil, never a crash.
    md = "# Project Config\n## Lifecycle Host\n- **Host platform:** `GitHub`\n"
    assert_equal Reviewer::DEFAULTS, Reviewer.extract(md)
  end

  def test_missing_row_defaults_only_that_field
    rows = "| **Primary** — summoned first | `Copilot` | any harness |\n" \
           "| **Degradation floor** — chain exhausted | `stop-and-ask` | `stop-and-ask` |"
    fields = Reviewer.extract(project_md(rows))
    assert_equal "Copilot", fields[:primary]
    assert_equal Reviewer::DEFAULTS[:fallback_order], fields[:fallback_order]
    assert_equal Reviewer::DEFAULTS[:bounded_window], fields[:bounded_window]
    assert_equal "stop-and-ask", fields[:degradation_floor]
  end

  def test_empty_section_returns_defaults
    md = "# Project Config\n## Reviewer\n\nProse only, no table.\n\n## Human Gates\n"
    assert_equal Reviewer::DEFAULTS, Reviewer.extract(md)
  end

  # --- table contract ----------------------------------------------------------------------------

  def test_header_binds_the_setting_column
    fields = Reviewer.extract(project_md(all_rows))
    assert_equal "30m", fields[:bounded_window] # read from the Setting column, not "Allowed values"
  end

  def test_reordered_columns_follow_the_header_not_the_position
    # A host may reorder the table's columns; the `Setting` header is what binds the value column, so
    # the parse must follow it rather than assuming index 1.
    md = <<~MD
      # Project Config
      ## Reviewer

      | Field | Allowed values | Setting |
      |-------|----------------|---------|
      | **Primary** | any harness | `Copilot` |
      | **Bounded window** | `<integer><unit>` | `15m` |
      | **Degradation floor** | `stop-and-ask` | `stop-and-ask` |
      ## Human Gates
    MD
    fields = Reviewer.extract(md)
    assert_equal "Copilot", fields[:primary]
    assert_equal "15m", fields[:bounded_window]
  end

  def test_falls_back_to_second_column_when_no_header_names_setting
    md = <<~MD
      # Project Config
      ## Reviewer

      | Field | Value |
      |-------|-------|
      | **Primary** | `Codex` |
      | **Bounded window** | `45s` |
      | **Degradation floor** | `stop-and-ask` |
      ## Human Gates
    MD
    fields = Reviewer.extract(md)
    assert_equal "Codex", fields[:primary]
    assert_equal "45s", fields[:bounded_window]
  end

  def test_first_matching_row_wins
    # Fail-SAFE: a second field-shaped row later in the section (an illustrative example, a copy/paste
    # leftover) must never override the authored one.
    #
    # The duplicate MUST sit before the field set is complete, and this fixture must NOT author all
    # four fields. `extract` breaks out of the loop once every field is authored, so a duplicate
    # appended after a complete table is never even read — the test would then pass because of the
    # `break`, not because of the first-match-wins guard. A mutation run proved exactly that: deleting
    # the guard left the original version of this test green.
    rows = "| **Primary** — the authored row | `Codex` | any harness |\n" \
           "| **Primary** — a stray duplicate | `Impostor` | any harness |\n" \
           "| **Bounded window** — wait | `30m` | shape |"
    fields = Reviewer.extract(project_md(rows))
    assert_equal "Codex", fields[:primary],
                 "a later duplicate row must never override the authored one"
  end

  def test_first_match_wins_even_when_the_duplicate_would_be_invalid
    # The safety-relevant direction of the same guard: a stray later row must not be able to downgrade
    # the floor. Deliberately leaves one field unauthored so the completion `break` cannot mask this.
    rows = "| **Degradation floor** — authored | `stop-and-ask` | fixed |\n" \
           "| **Degradation floor** — stray | `deliver-anyway` | fixed |\n" \
           "| **Primary** — summoned first | `Codex` | any harness |"
    fields = Reviewer.extract(project_md(rows))
    assert_equal "stop-and-ask", fields[:degradation_floor]
    assert_empty Reviewer.invalid(fields)
  end

  def test_row_labels_match_through_emphasis_and_backticks
    rows = "| `Primary` | `Copilot` | any |\n" \
           "| **BOUNDED WINDOW** | `2h` | shape |\n" \
           "| *degradation floor* | `stop-and-ask` | fixed |"
    fields = Reviewer.extract(project_md(rows))
    assert_equal "Copilot", fields[:primary]
    assert_equal "2h", fields[:bounded_window]
    assert_equal "stop-and-ask", fields[:degradation_floor]
  end

  def test_a_row_whose_first_cell_merely_STARTS_WITH_a_label_is_a_known_collision
    # Pins a REAL hazard rather than leaving it to be discovered. `labelled?` uses `start_with?`, so
    # ANY row whose first cell begins with a field label is claimed as that field - including a row in
    # the `### Invocation paths` sub-table if a host named a harness that way, or reordered the
    # sub-table above the settings table. Here the collision row wins (first-match-wins) and, carrying
    # no backticked value, silently yields the shipped default.
    #
    # Two things contain the blast radius in the shipped file: the settings table comes FIRST, and
    # `extract` breaks once all four fields are authored, so the sub-table is never reached. That is
    # ordering luck, not a guarantee.
    #
    # NOT fixed here because scripts/human_gates.rb:119 uses the identical `start_with?` rule and the
    # two readers are deliberately kept byte-identical in their table contract - tightening it belongs
    # in both at once, with its own issue. Recorded so the behavior is known rather than surprising.
    md = <<~MD
      # Project Config
      ## Reviewer

      | Harness | Summons |
      |---------|---------|
      | Primary reviewer app | mention it on the PR |

      | Field | Setting |
      |-------|---------|
      | **Primary** | `Codex` |
      ## Human Gates
    MD
    assert_equal Reviewer::DEFAULTS[:primary], Reviewer.extract(md)[:primary],
                 "a row merely STARTING WITH a label is claimed as that field today - if this starts " \
                 "failing, the matching rule was tightened; do it in human_gates.rb too"
  end

  def test_underscore_emphasis_is_a_known_gap_shared_with_human_gates
    # Pins a REAL limitation rather than leaving it as a silent surprise: `labelled?` strips `*` and
    # backticks but NOT underscores, so `__Primary__` does not match and the field silently defaults.
    # scripts/human_gates.rb has the identical gap, and the two readers are deliberately kept
    # byte-identical in their table contract - so this is fixed in BOTH or in neither, never here
    # alone. Recorded so a future fix has a test to flip rather than a behavior to discover.
    rows = "| __Primary__ | `Copilot` | any |"
    assert_equal Reviewer::DEFAULTS[:primary], Reviewer.extract(project_md(rows))[:primary],
                 "underscore emphasis is not matched today - if this starts passing, fix human_gates.rb too"
  end

  def test_section_ends_at_the_next_h2
    # A reviewer-shaped row in a LATER section must be invisible, or an unrelated table could silently
    # rewrite the policy.
    md = <<~MD
      # Project Config
      ## Reviewer

      | Field | Setting |
      |-------|---------|
      | **Primary** | `Codex` |
      ## Some Other Section

      | Field | Setting |
      |-------|---------|
      | **Primary** | `Impostor` |
      | **Degradation floor** | `deliver-anyway` |
    MD
    fields = Reviewer.extract(md)
    assert_equal "Codex", fields[:primary]
    assert_equal Reviewer::DEFAULTS[:degradation_floor], fields[:degradation_floor]
    assert_empty Reviewer.invalid(fields), "a later section must not be able to downgrade the floor"
  end

  def test_h3_subsection_does_not_end_the_section
    # The shipped PROJECT.md puts an `### Invocation paths` sub-table INSIDE this section. An H3 does
    # not terminate the scan, so this pins that the sub-table cannot corrupt the parse: its header
    # names no `Setting` column, and its first cells are harness names that match no field label.
    #
    # The asserted field rows MUST sit BELOW the H3. An earlier version put them above it, which made
    # the test vacuous: neither assertion could observe whether the scan stopped at the H3, and
    # mutating `break if l.start_with?("## ")` to `"#"` left the entire suite green (Reviewer finding,
    # PR #117). Placed below, the assertions fail outright if an H3 ever ends the section.
    md = <<~MD
      # Project Config
      ## Reviewer

      ### Invocation paths

      | Harness | Summons | Precondition | Check |
      |---------|---------|--------------|-------|
      | Codex | mention on the PR | app installed | list installed apps |
      | Copilot | request via API | review enabled | request succeeds |

      ### The settings

      | Field | Setting |
      |-------|---------|
      | **Primary** | `Codex` |
      | **Degradation floor** | `stop-and-ask` |
      ## Human Gates
    MD
    fields = Reviewer.extract(md)
    assert_equal "Codex", fields[:primary],
                 "an H3 must not end the section - these rows sit below one"
    assert_equal "stop-and-ask", fields[:degradation_floor]
  end

  # --- the label column can never be the value column --------------------------------------------

  def test_a_setting_headed_label_column_is_not_bound_as_the_value_column
    # A host table headed `| Setting | Value |` puts the word "Setting" at index 0 - the LABEL column.
    # Binding it would make every field read its own label instead of its value, silently discarding
    # ALL host settings and handing the checker the shipped defaults, so a plainly visible floor
    # downgrade could not be hard-failed (Reviewer finding, PR #117).
    md = <<~MD
      # Project Config
      ## Reviewer

      | Setting | Value |
      |---------|-------|
      | **Primary** | `Gemini 3 Pro` |
      | **Degradation floor** | `deliver-anyway` |
      ## Human Gates
    MD
    fields = Reviewer.extract(md)
    assert_equal "Gemini 3 Pro", fields[:primary],
                 "the value must be read from the VALUE column, not the label column"
    assert_equal "deliver-anyway", fields[:degradation_floor]
    assert_equal({ degradation_floor: "deliver-anyway" }, Reviewer.invalid(fields),
                 "a downgrade authored under a `Setting`-headed label column must still be reported")
  end

  # --- authored-but-unreadable is REPORTED, not silently defaulted -------------------------------

  def test_unbackticked_authored_value_is_reported_as_unreadable
    # THE bare-prose hole. `extract` fail-safes to the shipped default (correct - never adopt an
    # unreadable value), but that alone let a PROJECT.md visibly declaring "deliver-unreviewed" read
    # back as `stop-and-ask` with nothing reported: green, while the table the AC actually follows
    # said the opposite. Bare prose is exactly the authoring form that closed PR #109.
    rows = "| **Degradation floor** — chain exhausted | deliver-unreviewed with a footnote | fixed |\n" \
           "| **Bounded window** — wait | never, just deliver | shape |"
    text = project_md(rows)

    assert_equal "stop-and-ask", Reviewer.extract(text)[:degradation_floor],
                 "an unreadable value must never be ADOPTED"
    unreadable = Reviewer.unreadable(text)
    assert_equal "deliver-unreviewed with a footnote", unreadable[:degradation_floor]
    assert_equal "never, just deliver", unreadable[:bounded_window]
  end

  def test_empty_cell_is_unauthored_not_unreadable
    # The fail-safe boundary: an EMPTY setting cell is an unauthored field, not a mistake, so it must
    # NOT be reported. Only a non-empty cell with no backticked token is a mistake.
    rows = "| **Primary** — summoned first |  | any harness |"
    assert_empty Reviewer.unreadable(project_md(rows))
  end

  def test_backticked_values_are_never_reported_as_unreadable
    assert_empty Reviewer.unreadable(project_md(all_rows))
    assert_empty Reviewer.unreadable(project_md(all_rows(floor: "flag-in-sow"))),
                 "a backticked-but-invalid value is `invalid`, not `unreadable` - they are different faults"
  end

  def test_unreadable_mirrors_extracts_first_match_wins
    # BOTH rows must be unreadable, and they must differ. If the stray row were backticked, dropping
    # the first-match-wins guard would merely fail to overwrite an already-set entry, and the test
    # could not observe the difference — a mutation run caught exactly that (Reviewer finding,
    # PR #117). With two distinct unreadable values, the guard is the only thing choosing which wins.
    rows = "| **Degradation floor** — authored | the authored prose | fixed |\n" \
           "| **Degradation floor** — stray later row | a different prose | fixed |\n" \
           "| **Primary** — summoned first | `Codex` | any |"
    assert_equal "the authored prose", Reviewer.unreadable(project_md(rows))[:degradation_floor],
                 "unreadable must resolve the SAME row extract does, or the two disagree about which " \
                 "row is authoritative and the error message names a value the parser never read"
  end

  def test_unreadable_returns_empty_when_the_section_is_absent
    assert_empty Reviewer.unreadable("# Project Config\n## Lifecycle Host\n- x\n")
  end

  def test_section_as_last_in_file_parses_to_eof
    md = <<~MD
      # Project Config
      ## Reviewer

      | Field | Setting |
      |-------|---------|
      | **Primary** | `Copilot` |
      | **Degradation floor** | `stop-and-ask` |
    MD
    assert_equal "Copilot", Reviewer.extract(md)[:primary]
  end

  def test_unbackticked_value_leaves_the_shipped_default
    # A malformed cell must not blank the field - the default stays in place rather than becoming nil.
    rows = "| **Primary** | Codex without backticks | any |\n" \
           "| **Degradation floor** | `stop-and-ask` | fixed |"
    fields = Reviewer.extract(project_md(rows))
    assert_equal Reviewer::DEFAULTS[:primary], fields[:primary]
    refute_nil fields[:primary]
  end

  # --- invalid values are REPORTED, never coerced ------------------------------------------------

  def test_downgraded_degradation_floor_is_reported_not_coerced
    # The safety invariant. If this silently read as `stop-and-ask`, a host that wrote "deliver
    # anyway" would get the strict behavior with no error - and, worse, the reverse slip would ship a
    # self-certifying run. It must surface as invalid.
    fields = Reviewer.extract(project_md(all_rows(floor: "flag-in-sow")))
    assert_equal "flag-in-sow", fields[:degradation_floor], "the value must be returned verbatim"
    assert_equal({ degradation_floor: "flag-in-sow" }, Reviewer.invalid(fields))
  end

  def test_valid_bounded_windows_parse
    %w[30m 1h 45s 90m 2h].each do |w|
      fields = Reviewer.extract(project_md(all_rows(window: w)))
      assert_equal w, fields[:bounded_window]
      assert_empty Reviewer.invalid(fields), "#{w} should be a valid window"
    end
  end

  def test_unparseable_bounded_window_is_reported
    # PR #109 was closed partly for specifying a window as prose ("for example, 30 minutes") that no
    # AC could execute. A window the parser cannot read is not a bounded wait.
    ["30 minutes", "soon", "m30", "30", "-5m", "0m", "30d"].each do |w|
      fields = Reviewer.extract(project_md(all_rows(window: w)))
      assert_includes Reviewer.invalid(fields).keys, :bounded_window,
                      "#{w.inspect} must be reported as an unparseable window"
    end
  end

  def test_empty_window_cell_falls_back_to_the_default_rather_than_reporting
    # An EMPTY backtick pair is not an invalid value - it is an unauthored cell, so the fail-SAFE path
    # applies and the shipped default stands. Distinguishing this from `30 minutes` (authored but
    # unreadable, and therefore reported) is the whole point of separating extract from invalid.
    fields = Reviewer.extract(project_md(all_rows(window: "")))
    assert_equal Reviewer::DEFAULTS[:bounded_window], fields[:bounded_window]
    assert_empty Reviewer.invalid(fields)
  end

  def test_zero_window_is_rejected
    # A zero window would fire the fallback before any reviewer could answer, silently disabling the
    # primary - the failure looks identical to "the primary never responds".
    fields = Reviewer.extract(project_md(all_rows(window: "0m")))
    assert_includes Reviewer.invalid(fields).keys, :bounded_window
  end

  def test_defaults_are_themselves_valid
    # A shipped default that its own validator rejects would redden every vendored host on arrival.
    assert_empty Reviewer.invalid(Reviewer::DEFAULTS.dup)
  end

  # --- data contract: the REAL shipped PROJECT.md ------------------------------------------------

  def project_md_path
    File.join(File.expand_path("..", __dir__), "PROJECT.md")
  end

  def test_real_project_md_actually_contains_the_section
    # THE PRECONDITION FOR EVERY DRIFT GUARD BELOW. `from_file` fail-safes to DEFAULTS when the
    # section is absent, so deleting the whole `## Reviewer` section - or merely renaming its heading
    # - made all three data-contract tests below pass on the defaults while the shipped bundle
    # declared nothing at all (Reviewer finding, PR #117). Asserting the heading is present is what
    # turns those from vacuous into real, and it is why this test comes first.
    assert_includes File.read(project_md_path), "\n#{Reviewer::SECTION}\n",
                    "the shipped PROJECT.md must actually declare the `#{Reviewer::SECTION}` section - " \
                    "without it every assertion below passes vacuously on the shipped defaults"
  end

  def test_real_project_md_authors_every_field
    # The other half of the same hole: the heading can be present while the TABLE is gone, and the
    # value assertions would again be reading defaults rather than what the file declares.
    text = File.read(project_md_path)
    Reviewer::ROW_LABELS.each_key do |key|
      refute_nil Reviewer.unreadable(text), "unreadable must not blow up on the shipped file"
      assert_match(/^\|\s*\*{0,2}#{Regexp.escape(Reviewer::ROW_LABELS[key])}/i, text,
                   "the shipped PROJECT.md must author a `#{key}` row, not rely on the parser default")
    end
  end

  def test_real_project_md_has_no_unreadable_cells
    assert_empty Reviewer.unreadable(File.read(project_md_path)),
                 "every shipped Reviewer value must be authored in backticks"
  end

  def test_real_project_md_ships_a_valid_declaration
    fields = Reviewer.from_file(project_md_path)
    assert_empty Reviewer.invalid(fields),
                 "the shipped PROJECT.md must declare a valid reviewer chain"
  end

  def test_shipped_defaults_match_what_the_real_project_md_declares
    # DEFAULTS is what a host gets when the section is ABSENT; PROJECT.md is what this bundle SHIPS.
    # If the two drift, vendoring changes behavior for no stated reason — a host that deletes the
    # section would silently get a different reviewer chain than the one it was handed. Nothing else
    # pins this, and neither value is validated against the other by the parity check.
    assert_equal Reviewer::DEFAULTS, Reviewer.from_file(project_md_path),
                 "scripts/reviewer.rb DEFAULTS and the shipped PROJECT.md must declare the same chain"
  end

  def test_shipped_default_values_are_ascii
    # The one data value here that reaches a string a checker could print. scripts/parity_check.rb
    # interpolates author-controlled reviewer values into err() (the open #113 class), so a non-ASCII
    # DEFAULT would be a latent non-ASCII stdout path even with no host involved. Comments may use
    # any glyph; VALUES stay ASCII.
    Reviewer::DEFAULTS.each do |key, value|
      non_ascii = value.chars.reject { |c| c.ord < 128 }
      assert_empty non_ascii, "DEFAULTS[#{key.inspect}] carries non-ASCII #{non_ascii.uniq.inspect}"
    end
  end

  def test_real_project_md_ships_the_non_configurable_floor
    # The drift guard (mirrors human_gates_test's strict-defaults guard): the Generic Baseline must
    # ship the floor that keeps a run from certifying itself. If someone downgrades this, every
    # vendoring host silently loses its faithfulness backstop.
    fields = Reviewer.from_file(project_md_path)
    assert_equal Reviewer::FLOOR_VALUE, fields[:degradation_floor],
                 "the shipped PROJECT.md must declare the non-configurable degradation floor"
  end
end
