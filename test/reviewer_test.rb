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

  def test_blank_cell_in_a_present_row_is_unreadable_not_unauthored
    # THE BOUNDARY, corrected. An earlier version treated a blank Setting cell as "unauthored" and
    # said nothing — so a PROJECT.md with a labelled **Primary** row and an empty cell passed parity
    # green while the table an agent reads declared no primary at all (Reviewer finding, PR #117).
    #
    # A PRESENT labelled row is the host claiming the field; a blank cell is an unfinished edit, not a
    # decision to inherit the default. Row ABSENCE is what means unauthored.
    rows = "| **Primary** — summoned first |  | any harness |"
    text = project_md(rows)
    assert_equal Reviewer::DEFAULTS[:primary], Reviewer.extract(text)[:primary],
                 "a blank cell must still never ADOPT anything unsafe"
    assert_equal({ primary: "" }, Reviewer.unreadable(text),
                 "a present row with a blank cell must be reported, not silently defaulted")
  end

  def test_an_absent_row_is_unauthored_and_stays_silent
    # The other side of the boundary, and the vendored-host contract: a field with NO row never
    # reaches the loop, so it is silently defaulted. This is what keeps a PROJECT.md that predates a
    # field green rather than reddening on arrival.
    rows = "| **Primary** — summoned first | `Codex` | any harness |"
    assert_empty Reviewer.unreadable(project_md(rows)),
                 "the three unauthored fields have no rows at all and must stay silent"
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

  # --- a MULTI-SPAN setting cell is REPORTED, not silently truncated -----------------------------

  # A settings table whose `Fallback order` cell is passed through VERBATIM (no backticks added), so a
  # fixture can author it ONE CODE SPAN PER ELEMENT — `` `Copilot`, `Gemini` `` — which is exactly the
  # convention PROJECT.md -> Branch & PR Policy already uses for its protected-branch list.
  def spanned_rows(primary: "Codex", fallback: "`Copilot`, `Gemini`")
    "| **Primary** — summoned first | `#{primary}` | any harness |\n" \
      "| **Fallback order** — tried in turn | #{fallback} | comma-separated, or `none` |\n" \
      "| **Bounded window** — wait | `30m` | `<integer><unit>` |\n" \
      "| **Degradation floor** — chain exhausted | `stop-and-ask` | fixed |"
  end

  def test_a_multi_span_setting_cell_is_reported_and_no_other_seam_can_see_it
    # THE TRUNCATION HOLE. `extract` reads the FIRST backticked span and stops, so a list authored one
    # span per element loses everything after the first — and every pre-existing seam stays silent, in
    # four different ways. Each assertion below is one of them, and together they are why the fault
    # needed a seam of its own rather than an extension of any existing check.
    text = project_md(spanned_rows)

    assert_equal({ fallback_order: "`Copilot`, `Gemini`" }, Reviewer.ambiguous(text),
                 "the ONLY seam that can see a cell offering more than one value")

    fields = Reviewer.extract(text)
    assert_equal "Copilot", fields[:fallback_order], "extract reads the FIRST span and stops"
    assert_empty Reviewer.unreadable(text),
                 "the cell IS backticked, so `unreadable` matches truthily and reports nothing"
    assert_empty Reviewer.invalid(fields),
                 "every value check runs against the TRUNCATED read, which is a valid one-entry chain"
    assert_equal %w[Codex Copilot], Reviewer.chain(fields),
                 "`Gemini` never reaches the chain, so nothing downstream can report it"
  end

  def test_a_dropped_span_is_invisible_to_unsummonable
    # The fourth seam, which needs the raw text rather than the fields. `Gemini` has no invocation row
    # and is nonetheless never reported unreachable — because it never became a chain entry at all.
    md = with_paths("| Codex | mention on the PR | x | — |\n| Copilot | request via the API | x | — |",
                    settings: "| **Primary** | `Codex` |\n" \
                              "| **Fallback order** | `Copilot`, `Gemini` |")
    assert_empty Reviewer.unsummonable(md),
                 "the precondition for this finding: a dropped span cannot be reported unreachable"
    assert_equal({ fallback_order: "`Copilot`, `Gemini`" }, Reviewer.ambiguous(md))
  end

  def test_a_multi_span_cell_defeats_the_self_reference_invariant_and_is_reported_anyway
    # The sharpest form: `` `Copilot`, `Codex` `` under a `Codex` primary is a file that VISIBLY falls
    # back to its own primary, and the truncated read cannot see it. Reporting the ambiguity is what
    # keeps a plainly-violated invariant from shipping green.
    text = project_md(spanned_rows(primary: "Codex", fallback: "`Copilot`, `Codex`"))
    fields = Reviewer.extract(text)

    refute_includes Reviewer.invalid(fields).keys, :fallback_order_self_reference,
                    "the precondition: the invariant passes on the truncated read"
    assert_equal({ fallback_order: "`Copilot`, `Codex`" }, Reviewer.ambiguous(text),
                 "so SOMETHING must report the cell the invariant was never applied to")
  end

  def test_a_single_backticked_span_is_never_ambiguous
    # The negative control, and the boundary: a comma-separated list inside ONE pair of backticks is
    # the documented form and reads correctly through every seam.
    text = project_md(all_rows(fallback: "Copilot, Gemini"))
    assert_empty Reviewer.ambiguous(text)
    assert_equal %w[Codex Copilot Gemini], Reviewer.chain(Reviewer.extract(text)),
                 "the single-span form is what every other seam reads correctly"
  end

  def test_ambiguous_resolves_the_same_row_extract_does
    # First-match-wins, mirrored. If the two disagreed about which row is authoritative, the error
    # message would quote a cell the parser never read. Both rows here are field-shaped and only the
    # FIRST is multi-span, so the guard is the only thing choosing.
    rows = "| **Fallback order** — authored | `Copilot`, `Gemini` | list |\n" \
           "| **Fallback order** — stray later row | `Grok` | list |\n" \
           "| **Primary** — summoned first | `Codex` | any |"
    text = project_md(rows)
    assert_equal({ fallback_order: "`Copilot`, `Gemini`" }, Reviewer.ambiguous(text))
    assert_equal "Copilot", Reviewer.extract(text)[:fallback_order]
  end

  def test_ambiguous_follows_the_setting_header_not_the_position
    # The multi-span cell sits at index 2; the "Allowed values" cell at index 1 carries exactly one
    # span. Read positionally, the fault is invisible and a harmless cell is accused instead.
    md = <<~MD
      # Project Config
      ## Reviewer

      | Field | Allowed values | Setting |
      |-------|----------------|---------|
      | **Fallback order** | comma-separated, or `none` | `Copilot`, `Gemini` |
      ## Human Gates
    MD
    assert_equal({ fallback_order: "`Copilot`, `Gemini`" }, Reviewer.ambiguous(md))
  end

  def test_ambiguous_ends_at_the_next_h2
    # A field-shaped row in a LATER section is not this section's declaration, exactly as for extract.
    md = <<~MD
      # Project Config
      ## Reviewer

      | Field | Setting |
      |-------|---------|
      | **Primary** | `Codex` |
      ## Some Other Section

      | Field | Setting |
      |-------|---------|
      | **Fallback order** | `Copilot`, `Gemini` |
    MD
    assert_empty Reviewer.ambiguous(md)
  end

  def test_a_row_matching_no_field_label_is_never_reported_as_ambiguous
    # Only the four FIELD rows are this seam's business. A prose row that happens to carry two code
    # spans is not a setting the parser truncated.
    #
    # THE SEPARATOR ROW IS DELIBERATELY OMITTED. Without the label guard every unlabelled row is
    # filed under a `nil` key, and only the FIRST such row gets there — first-match-wins then skips
    # the rest. A `|---|---|` row above the note would quietly claim that slot and this fixture would
    # pass with the guard deleted (it did, on the first mutation run). The note must be the first
    # unlabelled row in the section for the assertion to mean anything.
    md = <<~MD
      # Project Config
      ## Reviewer

      | Field | Setting |
      | A note about harnesses | `Copilot` and `Grok` are both fine |
      | **Primary** | `Codex` |
      ## Human Gates
    MD
    assert_empty Reviewer.ambiguous(md)
  end

  def test_ambiguous_falls_back_to_the_second_column_when_no_header_names_setting
    # DEFAULT_SETTING_COLUMN, mirrored for this seam. Every other fixture here heads its table
    # `Setting`, which binds column 1 explicitly and leaves the positional fallback unproven — a live
    # host path, since `extract` has the same fallback and its own test for it.
    md = <<~MD
      # Project Config
      ## Reviewer

      | Field | Value |
      |-------|-------|
      | **Fallback order** | `Copilot`, `Gemini` |
      ## Human Gates
    MD
    assert_equal({ fallback_order: "`Copilot`, `Gemini`" }, Reviewer.ambiguous(md))
  end

  def test_ambiguous_returns_empty_when_the_section_is_absent
    assert_empty Reviewer.ambiguous("# Project Config\n## Lifecycle Host\n- x\n")
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

  # --- the `### Invocation paths` sub-table (ADR 0027) --------------------------------------------

  # A `## Reviewer` section carrying the settings table FIRST and the invocation sub-table below it —
  # the shipped file's own order, which is what makes test_invocation_paths_ignores_the_settings_table
  # a real assertion rather than a lucky one.
  def with_paths(rows, settings: "| **Primary** | `Codex` |\n| **Degradation floor** | `stop-and-ask` |")
    <<~MD
      # Project Config
      ## Reviewer

      | Field | Setting |
      |-------|---------|
      #{settings}

      ### Invocation paths

      | Harness | Summons | Precondition | Check |
      |---------|---------|--------------|-------|
      #{rows}

      ## Human Gates
    MD
  end

  def test_invocation_paths_lists_declared_harnesses_in_order
    md = with_paths("| Codex | mention on the PR | app installed | — |\n" \
                    "| Copilot | request via the API | review enabled | — |")
    assert_equal %w[Codex Copilot], Reviewer.invocation_paths(md)
  end

  def test_invocation_paths_skips_the_header_and_separator_rows
    # The header binds the Summons column and is consumed; the `|---|---|` separator is skipped
    # structurally. Neither may surface as a harness — `unsummonable` would then treat a chain entry
    # named "Harness" as reachable.
    md = with_paths("| Codex | mention on the PR | app installed | — |")
    paths = Reviewer.invocation_paths(md)
    assert_equal %w[Codex], paths
    refute_includes paths.map(&:downcase), "harness"
    refute paths.any? { |h| h.include?("---") }, "the separator row must never be a harness"
  end

  def test_invocation_paths_skips_a_row_declaring_no_summons
    # The shipped placeholder row, verbatim. Its dashes are U+2014 (EM DASH) — confirmed by probe on
    # PROJECT.md — so a rule written for ASCII hyphens alone would read `—` as a real mechanism and
    # report the placeholder as a summonable harness, making the whole check vacuous on the file it
    # ships against.
    md = with_paths("| Codex | mention on the PR | app installed | — |\n" \
                    "| *(host adds its own)* | — | — | — |\n" \
                    "| Blank | | | |")
    assert_equal %w[Codex], Reviewer.invocation_paths(md)
  end

  def test_an_alignment_marked_separator_row_is_not_a_harness
    # The separator skip is STRUCTURAL, not a side effect of its dashes tripping the no-summons rule.
    # GitHub-flavored markdown allows alignment colons (`|:---|:---:|`), and `:---:` is not a dash
    # run — so a separator recognized only by its Summons cell would leak a harness named `:---` and,
    # by prefix matching, quietly satisfy nothing while cluttering the declared set.
    md = <<~MD
      # Project Config
      ## Reviewer

      ### Invocation paths

      | Harness | Summons |
      |:--------|:-------:|
      | Codex | mention it |
      ## Human Gates
    MD
    assert_equal %w[Codex], Reviewer.invocation_paths(md)
  end

  def test_en_dash_and_ascii_hyphen_also_declare_no_summons
    md = with_paths("| Codex | – | x | x |\n| Copilot | - | x | x |\n| Grok | summon it | x | x |")
    assert_equal %w[Grok], Reviewer.invocation_paths(md)
  end

  def test_a_blank_harness_cell_does_not_silence_the_whole_check
    # THE SILENCE DETECTOR, and the reason the blank-harness skip exists at all.
    # `"anything".start_with?("")` is TRUE, so a single half-finished row with a populated Summons
    # cell would make EVERY chain entry match it — the entire reachability check goes quiet while
    # parity stays green, which is exactly the false-green class this work exists to close.
    md = with_paths("|  | mention on the PR | app installed | — |\n" \
                    "| Codex | mention on the PR | app installed | — |",
                    settings: "| **Primary** | `Codex` |\n| **Fallback order** | `Nope` |")
    refute_includes Reviewer.invocation_paths(md), "",
                    "a blank Harness cell must never be returned as a declared harness"
    assert_equal %w[Nope], Reviewer.unsummonable(md),
                 "an unreachable entry must still be reported despite the blank row above it"
  end

  def test_invocation_paths_is_empty_when_the_sub_section_is_absent
    assert_empty Reviewer.invocation_paths(project_md(all_rows))
  end

  def test_invocation_paths_is_empty_when_the_WHOLE_SECTION_is_absent
    # A separate case from the one above, and reachable only by calling this seam directly:
    # `unsummonable` short-circuits on `section?` before it ever gets here, so nothing else in the
    # suite drives `invocation_paths` at a PROJECT.md with no `## Reviewer` at all. It is a public
    # method on a fail-SAFE reader, so the vendored-host answer is [] rather than a crash.
    assert_empty Reviewer.invocation_paths("# Project Config\n## Lifecycle Host\n- x\n")
  end

  def test_invocation_paths_ends_at_the_next_h3
    md = <<~MD
      # Project Config
      ## Reviewer

      ### Invocation paths

      | Harness | Summons |
      |---------|---------|
      | Codex | mention it |

      ### Something else

      | Harness | Summons |
      |---------|---------|
      | Impostor | mention it |
      ## Human Gates
    MD
    assert_equal %w[Codex], Reviewer.invocation_paths(md)
  end

  def test_invocation_paths_ends_at_the_next_h2
    md = <<~MD
      # Project Config
      ## Reviewer

      ### Invocation paths

      | Harness | Summons |
      |---------|---------|
      | Codex | mention it |

      ## Some Other Section

      | Harness | Summons |
      |---------|---------|
      | Impostor | mention it |
    MD
    assert_equal %w[Codex], Reviewer.invocation_paths(md)
  end

  def test_invocation_paths_ends_at_a_heading_of_ANY_level
    # Terminating on `## ` and `### ` alone admitted tables under DEEPER headings: an `#### Host
    # notes` subheading carrying a harness-shaped table injected phantom rows into the membership
    # list, so a chain entry named only there read as reachable and parity passed. Every level is
    # exercised because the terminator is a range (`#{1,6}`), and a range's ends are its mutants.
    ["# ", "#### ", "##### ", "###### "].each do |hashes|
      md = <<~MD
        # Project Config
        ## Reviewer

        ### Invocation paths

        | Harness | Summons |
        |---------|---------|
        | Codex | mention it |

        #{hashes}Host notes

        | Harness | Summons |
        |---------|---------|
        | Ghost | mention it |
        ## Human Gates
      MD
      assert_equal %w[Codex], Reviewer.invocation_paths(md),
                   "a `#{hashes.strip}` heading must end the sub-table - a harness-shaped table under " \
                   "one must never join the chain's membership list"
    end
  end

  def test_a_decoy_invocation_heading_under_an_unrelated_h2_does_not_satisfy_membership
    # FINDING 1 OF #118, IN ITS SUBTLEST FORM. The sub-table must BELONG to `## Reviewer`. A
    # file-global search for the H3 binds the first heading of that name anywhere in PROJECT.md, so
    # this host — which has authored the section and declared no summons mechanism inside it — would
    # ship GREEN off a table sitting under some other H2 entirely.
    md = <<~MD
      # Project Config
      ## Reviewer

      | Field | Setting |
      |-------|---------|
      | **Primary** | `Codex` |
      | **Fallback order** | `none` |

      ## Some Other Section

      ### Invocation paths

      | Harness | Summons |
      |---------|---------|
      | Codex | mention it |
    MD
    assert_empty Reviewer.invocation_paths(md),
                 "a sub-table outside `## Reviewer` is not this section's membership list"
    assert_equal %w[Codex], Reviewer.unsummonable(md),
                 "the chain must still read as unreachable - a decoy elsewhere cannot vouch for it"
  end

  def test_a_decoy_heading_BEFORE_the_section_does_not_hide_the_real_sub_table
    # The converse, and the reason scoping cannot be done by "take the LAST such heading" either: a
    # decoy above `## Reviewer` must not shadow a genuine, fully-declared chain into reading
    # unreachable, which is a false RED on a host that did everything right.
    md = <<~MD
      # Project Config
      ## Some Other Section

      ### Invocation paths

      | Harness | Summons |
      |---------|---------|
      | Impostor | mention it |

      ## Reviewer

      | Field | Setting |
      |-------|---------|
      | **Primary** | `Codex` |
      | **Fallback order** | `none` |

      ### Invocation paths

      | Harness | Summons |
      |---------|---------|
      | Codex | mention it |
      ## Human Gates
    MD
    assert_equal %w[Codex], Reviewer.invocation_paths(md)
    assert_empty Reviewer.unsummonable(md), "a declared chain must not be reported unreachable"
  end

  def test_a_row_mixing_separator_shaped_cells_with_real_ones_is_a_harness
    # The separator skip is `cells.all?`, and the quantifier is the invariant: under `any?` a single
    # dash placeholder ANYWHERE in a row would delete that harness from the membership list, and every
    # chain entry relying on it would be reported unreachable. Only a row that is separator-shaped in
    # EVERY cell is a separator.
    md = with_paths("| MyHarness | mention @bot on the PR | -- | -- |")
    assert_equal %w[MyHarness], Reviewer.invocation_paths(md),
                 "a row with dashes in SOME cells is a harness row, not a separator"
  end

  def test_a_two_dash_alignment_separator_is_still_not_a_harness
    # The separator pattern's lower bound, pinned. GFM's delimiter row does not require three hyphens,
    # so `|:--|:--:|` is a real table a host can write — and its alignment colons keep NO_SUMMONS from
    # catching it, so if the structural skip stopped recognizing two dashes the row would leak `:--`
    # into the membership list as a harness.
    md = <<~MD
      # Project Config
      ## Reviewer

      ### Invocation paths

      | Harness | Summons |
      |:--|:--:|
      | Codex | mention it |
      ## Human Gates
    MD
    assert_equal %w[Codex], Reviewer.invocation_paths(md)
  end

  def test_a_header_row_is_recognized_by_its_HARNESS_cell_alone
    # HEADER_CELLS has two entries and each must be separately provable. Here NO cell reads
    # "Summons", so nothing binds the mechanism column and only the `Harness` cell can identify this
    # row as the header — without that entry it is read as a data row declaring a harness called
    # "Harness", which a chain entry named `Harness…` would then match by prefix.
    md = <<~MD
      # Project Config
      ## Reviewer

      ### Invocation paths

      | Harness | How to summon |
      |---------|---------------|
      | Codex | mention it |
      ## Human Gates
    MD
    assert_equal %w[Codex], Reviewer.invocation_paths(md)
  end

  def test_the_summons_column_falls_back_to_the_second_when_no_header_names_it
    # DEFAULT_SUMMONS_COLUMN is a live host path, not a theoretical one: PROJECT.md invites hosts to
    # rewrite these rows and a host may head the column anything. The second row is what pins the
    # fallback to column 1 from BOTH sides — read from column 2 nothing is summonable, read from
    # column 0 every row is, and only column 1 tells the two apart.
    md = <<~MD
      # Project Config
      ## Reviewer

      ### Invocation paths

      | Harness | Mechanism |
      |---------|-----------|
      | Codex | mention it on the PR |
      | Copilot | — |
      ## Human Gates
    MD
    assert_equal %w[Codex], Reviewer.invocation_paths(md)
  end

  def test_invocation_paths_ignores_the_settings_table_above_it
    # The scan anchors on the H3, not on `## Reviewer`. A scan that merely walked the H2 would return
    # `Primary` and `Degradation floor` as if they were harnesses — and since matching is by prefix,
    # a chain entry named `Primary reviewer` would then read as reachable.
    md = with_paths("| Codex | mention on the PR | app installed | — |")
    paths = Reviewer.invocation_paths(md)
    assert_equal %w[Codex], paths
    refute_includes paths, "Primary"
    refute_includes paths, "Degradation floor"
  end

  def test_the_summons_column_is_bound_by_header_not_by_position
    # `PROJECT.md` openly invites hosts to rewrite these rows, so the column order is theirs to choose.
    # Read positionally, this table's dash PRECONDITIONS would be mistaken for the Summons cells and
    # the host's entire working chain would be reported unreachable — the same hazard `setting_column`
    # was added to close on the settings table.
    md = <<~MD
      # Project Config
      ## Reviewer

      ### Invocation paths

      | Harness | Precondition | Summons | Check |
      |---------|--------------|---------|-------|
      | Codex | — | mention on the PR | — |
      | Copilot | — | request via the API | — |
      ## Human Gates
    MD
    assert_equal %w[Codex Copilot], Reviewer.invocation_paths(md)
  end

  def test_the_harness_label_column_is_never_bound_as_the_summons_column
    # Column 0 is the LABEL column. Binding it would make every row read its own name as its summons
    # mechanism, so no row could ever be skipped and the whole chain would read as reachable — the
    # exact failure `setting_column`'s column-0 guard exists to prevent, mirrored here.
    #
    # The second header cell reads "Tool", NOT "Harness", deliberately: with both HEADER_CELLS
    # entries present in one row, either could be deleted and this row would still be recognized as a
    # header — two mutants, both unkillable. Here only the `summons` entry can do it, which is what
    # makes that entry separately provable (its sibling is pinned by
    # test_a_header_row_is_recognized_by_its_HARNESS_cell_alone).
    md = <<~MD
      # Project Config
      ## Reviewer

      ### Invocation paths

      | Summons | Tool |
      |---------|------|
      | Codex | — |
      ## Human Gates
    MD
    assert_empty Reviewer.invocation_paths(md),
                 "a `Summons`-headed label column must not be bound; this row declares no mechanism"
  end

  def test_invocation_paths_reads_through_emphasis_and_backticks
    md = with_paths("| **Codex** | `mention on the PR` | x | — |")
    assert_equal %w[Codex], Reviewer.invocation_paths(md)
  end

  # --- the chain ---------------------------------------------------------------------------------

  def test_chain_is_the_primary_then_the_fallback_in_order
    fields = Reviewer.extract(project_md(all_rows(primary: "Codex", fallback: "Copilot, Grok")))
    assert_equal ["Codex", "Copilot", "Grok"], Reviewer.chain(fields)
  end

  def test_none_as_the_sole_fallback_means_an_empty_fallback
    fields = Reviewer.extract(project_md(all_rows(fallback: "none")))
    assert_equal ["Codex"], Reviewer.chain(fields)
    assert_empty Reviewer.invalid(fields), "`none` alone is the legal way to declare no fallback"
  end

  # --- chain shape faults: each fixture trips exactly ONE new predicate ---------------------------

  def test_a_blank_fallback_element_is_reported
    # Deliberately carries NO `none`, so this fixture can only satisfy the blank-element predicate.
    # If it satisfied two, either branch could be deleted with the other still setting a shared key —
    # the unkillable-mutant trap rules/testing.md:23 names, and the reason each fault has its own key.
    fields = Reviewer.extract(project_md(all_rows(fallback: "Copilot, , Grok")))
    bad = Reviewer.invalid(fields)
    assert_equal "Copilot, , Grok", bad[:fallback_order_blank_element]
    refute_includes bad.keys, :fallback_order_none_mixed
    refute_includes bad.keys, :fallback_order_self_reference
    refute_includes bad.keys, :primary_blank
  end

  def test_a_trailing_comma_is_a_blank_element
    # Ruby's `split(",")` DROPS a trailing empty field, so an edit abandoned mid-word (`Copilot,`)
    # would read as a clean single-entry fallback. `split(",", -1)` is what keeps it visible.
    fields = Reviewer.extract(project_md(all_rows(fallback: "Copilot,")))
    assert_equal "Copilot,", Reviewer.invalid(fields)[:fallback_order_blank_element]
  end

  def test_none_mixed_with_real_entries_is_reported
    # Deliberately carries NO blank element, so only the none-mixed predicate can fire.
    fields = Reviewer.extract(project_md(all_rows(fallback: "none, Copilot")))
    bad = Reviewer.invalid(fields)
    assert_equal "none, Copilot", bad[:fallback_order_none_mixed]
    refute_includes bad.keys, :fallback_order_blank_element
  end

  def test_a_blank_primary_is_reported
    # Reached through the REAL parse, not a hand-edited hash: a backtick pair holding only whitespace
    # (`` ` ` ``) satisfies BACKTICKED, so `unreadable` says nothing and `extract` returns "". That is
    # the one path by which a blank primary escapes every pre-existing check — the chain then has no
    # first entry and there is nobody to summon, while parity stayed green.
    # A clean single-entry fallback, so the only new fault available is the blank primary.
    fields = Reviewer.extract(project_md(all_rows(primary: " ")))
    assert_equal "", fields[:primary], "the precondition for this test: the parse must yield a blank"
    assert_empty Reviewer.unreadable(project_md(all_rows(primary: " "))),
                 "a whitespace-only backtick pair is READABLE - the blank is the fault, not the form"
    bad = Reviewer.invalid(fields)
    assert_includes bad.keys, :primary_blank
    refute_includes bad.keys, :fallback_order_blank_element
    refute_includes bad.keys, :fallback_order_none_mixed
    refute_includes bad.keys, :fallback_order_self_reference
  end

  def test_a_primary_repeated_in_its_own_fallback_is_reported
    # The machine-checkable SHADOW of independence: a chain that falls back to itself is not a
    # fallback. Deliberately a single clean fallback element, so no other predicate can fire.
    fields = Reviewer.extract(project_md(all_rows(primary: "Codex", fallback: "Codex")))
    bad = Reviewer.invalid(fields)
    assert_equal "Codex", bad[:fallback_order_self_reference]
    refute_includes bad.keys, :fallback_order_blank_element
    refute_includes bad.keys, :fallback_order_none_mixed
  end

  def test_self_reference_is_case_insensitive
    fields = Reviewer.extract(project_md(all_rows(primary: "Codex", fallback: "Copilot, codex")))
    assert_equal "Codex", Reviewer.invalid(fields)[:fallback_order_self_reference]
  end

  def test_self_reference_sees_through_emphasis
    # `invalid` compares through `plain`, the same reduction `unsummonable` uses. Compared raw, the
    # two seams disagreed about the same string and BOTH went silent on a chain that falls back to
    # itself: `invalid` saw `**Copilot**` != `Copilot`, while `unsummonable` — which strips the
    # emphasis — found the `Copilot` row and reported nothing. The second assertion pins that
    # precondition, so this test fails for the right reason if either seam changes.
    md = with_paths("| Copilot | request via the API | x | — |",
                    settings: "| **Primary** | `Copilot` |\n| **Fallback order** | `**Copilot**` |")
    assert_empty Reviewer.unsummonable(md),
                 "the precondition: the emphasized entry resolves to a row, so this seam stays quiet"

    fields = Reviewer.extract(project_md(all_rows(primary: "Copilot", fallback: "**Copilot**")))
    assert_equal "Copilot", Reviewer.invalid(fields)[:fallback_order_self_reference],
                 "emphasis must not hide a fallback that names the primary"
  end

  def test_a_wholly_blank_fallback_order_is_reported
    # Reached through the REAL parse: a whitespace-only backtick pair satisfies BACKTICKED, so
    # `unreadable` says nothing and `extract` yields "". Gated under `parts.length > 1`, the
    # blank-element check could not see it — Ruby's `"".split(",", -1)` returns NO elements at all —
    # so the fallback simply vanished from the chain and NOTHING reported it, while `Copilot,` (which
    # still yields a working one-entry chain) was flagged. That asymmetry is the fault here.
    text = project_md(all_rows(fallback: " "))
    fields = Reviewer.extract(text)

    assert_equal "", fields[:fallback_order], "the precondition: the parse must yield a blank"
    assert_empty Reviewer.unreadable(text),
                 "a whitespace-only backtick pair is READABLE - the blank is the fault, not the form"
    assert_equal %w[Codex], Reviewer.chain(fields), "the fallback is gone from the chain entirely"

    bad = Reviewer.invalid(fields)
    assert_equal "", bad[:fallback_order_blank_element],
                 "a wholly blank fallback must be reported, exactly as a blank ELEMENT is"
    refute_includes bad.keys, :fallback_order_none_mixed
    refute_includes bad.keys, :fallback_order_self_reference
    refute_includes bad.keys, :primary_blank
  end

  def test_the_issue_repro_reports_BOTH_faults_under_distinct_keys
    # #118's own reproduction: `Reviewer.invalid` returned `{}` for this. It satisfies TWO predicates
    # at once, which is precisely why the keys must be distinct — under one shared `:fallback_order`
    # key, deleting either branch would leave the other still setting it and BOTH mutants would
    # survive. Asserting both keys fire is what makes each branch separately provable.
    fields = Reviewer.extract(project_md(all_rows(primary: "Not A Configured Harness",
                                                  fallback: "none, , Nope")))
    bad = Reviewer.invalid(fields)
    assert_equal "none, , Nope", bad[:fallback_order_blank_element]
    assert_equal "none, , Nope", bad[:fallback_order_none_mixed]
  end

  # --- unsummonable ------------------------------------------------------------------------------

  def test_unsummonable_reports_a_primary_with_no_row
    md = with_paths("| Copilot | request via the API | x | — |",
                    settings: "| **Primary** | `Not A Configured Harness` |\n" \
                              "| **Fallback order** | `Copilot` |")
    assert_equal ["Not A Configured Harness"], Reviewer.unsummonable(md)
  end

  def test_unsummonable_reports_a_fallback_with_no_row
    md = with_paths("| Codex | mention on the PR | x | — |",
                    settings: "| **Primary** | `Codex` |\n| **Fallback order** | `Nope` |")
    assert_equal %w[Nope], Reviewer.unsummonable(md)
  end

  def test_unsummonable_is_empty_when_every_entry_has_a_row
    md = with_paths("| Codex | mention on the PR | x | — |\n| Copilot | request via the API | x | — |",
                    settings: "| **Primary** | `Codex` |\n| **Fallback order** | `Copilot` |")
    assert_empty Reviewer.unsummonable(md)
  end

  def test_an_authored_section_with_no_sub_table_reports_the_whole_chain
    # FINDING 1 of #118. The host has AUTHORED the section — it is claiming the chain — but declared
    # no mechanism for anyone in it. Every entry is unreachable, so the PR gate resolves to the floor.
    text = project_md(all_rows(primary: "Codex", fallback: "Copilot"))
    assert_equal %w[Codex Copilot], Reviewer.unsummonable(text)
  end

  def test_unsummonable_is_SILENT_when_the_section_is_absent
    # THE VENDORED-HOST COMPATIBILITY GUARD, at the extractor level (its parity-level twin is
    # test_no_unsummonable_error_fires_without_a_reviewer_section). An absent section yields the
    # shipped DEFAULTS and no invocation paths, so without this guard every already-vendored host
    # would report its entire chain unreachable the moment it re-synced — reddening exactly the hosts
    # the additive contract exists to protect (ADR 0027 decision 5).
    md = "# Project Config\n## Lifecycle Host\n- **Host platform:** `GitHub`\n"
    assert_empty Reviewer.unsummonable(md)
    refute Reviewer.section?(md)
  end

  def test_an_entry_matches_its_row_by_prefix
    # A host may name a model-qualified entry while the invocation row names the bare harness.
    md = with_paths("| Codex | mention on the PR | x | — |",
                    settings: "| **Primary** | `Codex (GPT-5)` |\n| **Fallback order** | `none` |")
    assert_empty Reviewer.unsummonable(md)
  end

  def test_prefix_matching_is_a_known_collision
    # Pins a REAL hazard rather than leaving it to be discovered, in the file's existing
    # known-limitation style. `start_with?` is `labelled?`'s idiom, and it cuts both ways: it lets
    # `Codex (GPT-5)` resolve to a `Codex` row, and it equally lets a `Codex` row satisfy a
    # `Codex Cloud` entry a host meant as a DISTINCT harness — silently declaring reachable something
    # nobody can summon. Not fixed here: tightening the rule belongs with `labelled?`, in
    # scripts/reviewer.rb and scripts/human_gates.rb at once, with its own issue.
    md = with_paths("| Codex | mention on the PR | x | — |",
                    settings: "| **Primary** | `Codex Cloud` |\n| **Fallback order** | `none` |")
    assert_empty Reviewer.unsummonable(md),
                 "prefix matching resolves `Codex Cloud` to the `Codex` row today - if this starts " \
                 "failing, the matching rule was tightened; do it in human_gates.rb too"
  end

  def test_section_distinguishes_authored_from_absent
    assert Reviewer.section?(project_md(all_rows))
    refute Reviewer.section?("# Project Config\n## Human Gates\n")
    refute Reviewer.section?("# Project Config\n## Reviewer notes\n"),
           "a heading that merely STARTS WITH the section name is not the section"
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
      assert_match(/^\|\s*\*{0,2}#{Regexp.escape(Reviewer::ROW_LABELS[key])}/i, text,
                   "the shipped PROJECT.md must author a `#{key}` row, not rely on the parser default")
    end
  end

  def test_real_project_md_has_no_unreadable_cells
    assert_empty Reviewer.unreadable(File.read(project_md_path)),
                 "every shipped Reviewer value must be authored in backticks"
  end

  def test_real_project_md_has_no_ambiguous_cells
    assert_empty Reviewer.ambiguous(File.read(project_md_path)),
                 "the shipped bundle must not do the thing it reports hosts for - each setting cell " \
                 "must offer exactly ONE backticked value"
  end

  def test_real_project_md_documents_the_single_span_list_form
    # Doc/machine agreement, in the direction a host is most likely to get wrong. This repo's own
    # protected-branch list is authored one code span per element, so a host copying that convention
    # into `Fallback order` is the expected mistake — the allowed-values cell has to say otherwise at
    # the point of authorship, not only in an error message after the fact.
    fallback_row = File.read(project_md_path)[/^\|\s*\*\*Fallback order\*\*.*$/]
    assert_match(/ONE pair of backticks/, fallback_row.to_s,
                 "the Fallback-order allowed-values cell must name the single-span list form")
  end

  def test_real_project_md_states_the_harness_label_column_contract
    # `invocation_paths` reads the harness name positionally (`cells[0]`) while binding the mechanism
    # column by header, so "reorder the columns freely" is true of every column BUT the first. The
    # table openly invites hosts to rewrite these rows, so the one column they may not move has to be
    # named where they are authoring.
    text = File.read(project_md_path)
    section = text[/#{Regexp.escape(Reviewer::INVOCATION_SECTION)}.*?(?=\n## )/m]
    refute_nil section, "the invocation sub-table must be locatable"
    assert_includes section, "The first column is the harness name, by contract",
                    "the positional read of column 0 must be stated where a host authors its rows"
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

  def test_real_project_md_ships_a_fully_summonable_chain
    # The shipped bundle must not do the thing it now reports hosts for. Also the precondition for the
    # test below: if the sub-table were missing, that one's assertions would be vacuous.
    text = File.read(project_md_path)
    assert_includes text, Reviewer::INVOCATION_SECTION,
                    "the shipped PROJECT.md must declare `#{Reviewer::INVOCATION_SECTION}`"
    assert_empty Reviewer.unsummonable(text),
                 "every harness in the shipped reviewer chain must have a summons mechanism"
  end

  def test_real_project_md_declares_no_executable_precondition_check
    # Pins ADR 0027 decision 4 against the file. The baseline ships NO executable check — the Codex one
    # needs GitHub App auth an AC's normal token lacks, and the Copilot one IS the summons — so the
    # `Check` cells say host-supplied and the preamble no longer claims an unconditional pre-check.
    # Without this, a future edit could quietly re-add a check the AC cannot run, and prose is the one
    # thing the parity check never reads.
    text = File.read(project_md_path)
    section = text[/#{Regexp.escape(Reviewer::INVOCATION_SECTION)}.*?(?=\n## )/m]
    refute_nil section, "the invocation sub-table must be locatable"
    assert_includes section, "host-supplied",
                    "the shipped Check cells must be marked host-supplied, not imply a shipped check"
    refute_match(/precondition that must be verified first/, section,
                 "the preamble must no longer claim an unconditional pre-check (ADR 0027 supersedes " \
                 "ADR 0026 decision 4)")
    assert_includes section, "the summons is the probe",
                    "the absent-check path must be stated, not left to be inferred"
  end

  def test_real_project_md_allowed_values_name_the_invocation_paths_table
    # Doc/machine agreement. The checker validates chain membership against *Invocation paths*, so the
    # authored contract must say so — a stale cell still pointing at *Attribution & Model Declaration*
    # would re-open the documented-vs-enforced split this work exists to close.
    text = File.read(project_md_path)
    primary_row = text[/^\|\s*\*\*Primary\*\*.*$/]
    fallback_row = text[/^\|\s*\*\*Fallback order\*\*.*$/]
    assert_includes primary_row.to_s, "Invocation paths"
    assert_includes fallback_row.to_s, "Invocation paths"
    refute_includes primary_row.to_s, "Attribution & Model Declaration"
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
