# POLICE ASSISTANT 2026 — CRITICAL BUGFIX
# F9 PATROL WINDOW CRASH / NIL REPORT TEMPLATE
# Comprehensive Edge-Case Validation & Regression Testing

PRIORITY: P0 — Critical Runtime Stability
TYPE: Targeted bugfix + defensive validation + regression tests

OBJECTIVE:

Fix a confirmed Lua runtime error that occurs when opening the
F9 → Напарники → Патруль section.

Additionally, audit the same class of errors across the relevant
report-generation pipeline and ensure that invalid, missing or
temporarily unavailable data cannot cause unexpected closure
of the entire Police Assistant interface.

IMPORTANT:

This is a stability-focused maintenance task.

Do not implement unrelated features.
Do not redesign the UI.
Do not refactor large subsystems unnecessarily.
Do not introduce new continuous polling, FFI hooks, CEF
monitoring or expensive operations in ImGui render callbacks.

Preserve existing functionality, settings and user data.


============================================================
1. CONFIRMED BUG — ROOT CAUSE
============================================================

The user reproduced the following error in-game:

pa26_map_grid.lua:83:
attempt to index local 'template' (a nil value)

UI diagnostics:

Диагностика UI: partners

Observed behavior:

1. Player opens F9.
2. Navigates to "Напарники".
3. Opens the "Патруль" subsection.
4. The entire F9 window unexpectedly closes.
5. Other F9 sections become inaccessible until UI recovery.

The screenshot confirms that the PA error-recovery mechanism
was activated.

The investigation identified the following call chain:

Studio:drawPartners()
    → patrolUi.draw()
    → callbacks.patrolPreview()
    → Session:prepareLine()
    → reportContext.directionTemplate()
    → mapGrid.reportValues()
    → template:find()
    → Lua exception

The root cause is located in:

moonloader/lib/pa26_patrol_session.lua

Current problematic implementation:

    checked = require('pa26_report_context')
        .directionTemplate(checked, values)

    values = mapGrid.reportValues(values, checked)

The recently introduced directionTemplate() function may
legitimately return:

    nil, "Курс не наблюдался..."

This happens when:

- The officer's direction is unknown.
- A custom report template explicitly requires {direction}.
- Automatic removal of the direction clause is not allowed,
  because the template contains the user's personal wording.

However, Session:prepareLine() does not check whether
directionTemplate() returned nil.

Consequently, nil is passed to mapGrid.reportValues(),
which attempts to execute:

    template:find('{area}', 1, true)

This triggers the confirmed exception.

IMPORTANT:

This is not primarily a CEF bridge problem.
It is a missing error-propagation check in the report pipeline.

Do not modify CEF to solve this issue.


============================================================
2. FIX THE PRIMARY ROOT CAUSE
============================================================

File:

moonloader/lib/pa26_patrol_session.lua

Function:

Session:prepareLine(action, a, s, cfg)

Inspect the actual current implementation before editing.

The code must preserve both return values from
directionTemplate():

    local directionError

    checked, directionError =
        require('pa26_report_context')
            .directionTemplate(checked, values)

    if not checked then
        return nil, directionError
    end

    values = mapGrid.reportValues(values, checked)

Adapt this example to existing project conventions.

Do not discard the error message returned by directionTemplate().

Expected behavior:

CASE A — Known direction:

Direction: север
directionKnown: true

The template is processed normally.

CASE B — Unknown direction + unchanged stock template:

The direction-dependent clause is removed according to
the existing directionTemplate() rules.

No exception occurs.

CASE C — Unknown direction + custom template:

The original custom text is preserved.

The preview returns a readable warning explaining that
the officer must clarify the direction.

No command is sent.
No template is overwritten.
No UI window closes.

CASE D — Unknown direction + custom template without {direction}:

The preview works normally.

A missing direction must not block a report that does
not require direction information.


============================================================
3. FIX THE SECOND IDENTIFIED BUG
============================================================

File:

moonloader/lib/pa26_alerts.lua

Function:

M.prepare()

Another potentially unsafe call exists around the original
line 56:

    local template =
        require('pa26_report_context')
            .directionTemplate(
                source[kind..'_template'],
                state
            )

The result is subsequently passed to reportValues()
without checking whether template is nil.

This is the same error class.

Fix it by preserving the error value and returning a
controlled failure if the template cannot be prepared.

Example:

    local template, directionError =
        require('pa26_report_context')
            .directionTemplate(
                source[kind..'_template'],
                state
            )

    if not template then
        return nil, directionError
    end

Continue processing only when template is valid.

Ensure that:

- SOS reports remain functional.
- Shots-fired reports remain functional.
- CODE 0 reports remain functional.
- Patrol reports remain functional.
- Existing radio channels remain unchanged.
- Existing confirmation requirements remain unchanged.
- No automatic command emission is introduced.


============================================================
4. AUDIT ALL SIMILAR CALL SITES
============================================================

Search the entire project for:

directionTemplate(
reportValues(
reportPolicy(
template:find(
template:gsub(
core.expandGender(

Inspect all places where the result of a function returning:

    value, error

is subsequently used without validating value.

Pay particular attention to:

pa26_patrol_session.lua
pa26_alerts.lua
pa26_radio_guard.lua
pa26_copilot.lua
pa26_vehicle.lua
pa26_patrol_events.lua
pa26_report_context.lua
pa26_map_grid.lua

Previously inspected call sites:

- pa26_radio_guard.lua already checks the result of
  directionTemplate().

- pa26_copilot.lua already checks the result.

- pa26_vehicle.lua already checks the result.

Verify these protections still exist in the current revision.

Do not assume line numbers from the previous revision
are still accurate.

Use the actual checked-out source.

For every relevant call site, establish whether:

1. The function can return nil.
2. The caller checks the return value.
3. The error message is preserved.
4. The failure stops only the affected operation.
5. The UI remains functional.
6. No command is sent after a failed validation.

Fix confirmed unsafe paths.

Avoid introducing speculative changes to unrelated code.


============================================================
5. DEFENSIVE CONTRACTS FOR MAP FORMATTING
============================================================

Review:

pa26_map_grid.lua

Functions:

M.location()
M.reportValues()
M.reportPolicy()

These functions currently expect certain inputs to be valid.

Define and enforce explicit input contracts.

Required validation:

- values must be a valid table.
- template must be a string.
- missing map data must not trigger indexing errors.
- unknown district must remain a supported condition.
- missing map_square must remain a supported condition.
- disabled map grid must remain a supported condition.
- empty report text must be handled according to
  the existing report-validation rules.

IMPORTANT:

Do not silently replace a missing report template with an
empty string merely to suppress exceptions.

That could hide a broken caller and produce incorrect
or incomplete reports.

Prefer explicit error propagation.

However, do not change the return-value contract of
M.reportValues() or M.reportPolicy() without updating and
testing every affected caller.

The goal is to prevent crashes without silently
changing the meaning of reports.

Preserve:

- Custom location templates.
- Existing map-square calculations.
- Manual and automatic square settings.
- Existing district formatting.
- Existing user map preferences.


============================================================
6. UNKNOWN DIRECTION — COMPLETE EDGE-CASE COVERAGE
============================================================

Review:

pa26_report_context.lua

Functions:

directionKnown()
directionTemplate()

Preserve the previously approved behavior.

UNKNOWN DIRECTION CASES:

1. direction == nil
2. direction == ""
3. direction == "неизвестно"
4. direction == "не определено"
5. direction == "не определён"
6. directionKnown == false
7. Valid direction but directionKnown == false
8. Missing directionKnown field
9. Malformed or unexpected runtime direction value

KNOWN DIRECTION CASES:

1. "север"
2. "юг"
3. "восток"
4. "запад"
5. Other supported direction strings
6. A valid last-known direction explicitly marked as known

Do not change the established policy for determining whether
the last-known direction is still valid.

In particular, do not invent a direction simply because
the vehicle is stationary.

Do not silently replace unknown direction with "север",
"юг" or another arbitrary value.

STOCK TEMPLATE RULE:

If the original standard template contains a known
direction-dependent phrase, remove only that phrase.

Preserve the remaining report.

Avoid:

- Double commas.
- Duplicate spaces.
- Broken punctuation.
- Dangling words.
- Empty sentences.
- Literal unresolved {direction}.
- Incorrect grammatical forms.

CUSTOM TEMPLATE RULE:

If a user-customized template requires an unknown direction,
return an actionable warning.

Preserve the exact custom text.

No auto-rewriting.
No reset to defaults.
No accidental saving of a modified template.


============================================================
7. F9 ERROR ISOLATION & RECOVERY
============================================================

Inspect:

police_assistant_2026.lua

Functions:

safeDraw()
recordUiFailure()
recoverUi()
toggleWindow()

Current behavior:

A Lua exception in a render callback can cause:

    uiFailed = true

The main F9 rendering condition then prevents the entire
interface from opening.

Preserve the global recovery mechanism as a last-resort
protection against genuinely unexpected ImGui failures.

However, expected application-level errors must never
reach this global handler.

Examples:

- Unknown direction.
- Invalid report template.
- Missing optional information.
- Unavailable patrol preview.
- Missing district.
- Invalid user-entered value.

These conditions must produce normal validation messages.

They must not mark the entire UI as failed.

EXPECTED USER EXPERIENCE:

If a patrol preview cannot be prepared:

- F9 remains open.
- The Patrol section remains accessible.
- The relevant preview displays a readable reason.
- Other previews continue working.
- The user can navigate to "Напарники".
- The user can navigate to "Настройки".
- No global UI recovery is required.

Do not add expensive xpcall/pcall wrappers around every
ImGui widget on every frame.

Prefer validating and returning errors at the source.

If improving safeDraw() traceback collection, use the
appropriate xpcall error-handler pattern and preserve
correct ImGui scope cleanup.

Do not risk destabilizing ImGui merely to improve logging.

A genuine unexpected renderer exception should still
be captured and reported.

Do not create a recovery loop that repeatedly crashes,
recovers and crashes again without user intervention.


============================================================
8. PERFORMANCE — STRICT NON-REGRESSION REQUIREMENTS
============================================================

The project recently experienced significant frame-time
degradation associated with CEF integration.

This fix must not reintroduce that problem.

STRICT REQUIREMENTS:

- Do not modify the CEF bridge unless demonstrably required.
- Do not add DOM observers.
- Do not add continuous chat-input polling.
- Do not add new WinAPI polling loops.
- Do not add FFI memory reads.
- Do not add timers for report validation.
- Do not introduce file I/O inside render callbacks.
- Do not add excessive logging per frame.
- Do not allocate large diagnostic structures each frame.
- Do not repeatedly validate the entire user library
  on every rendered frame.

Existing lightweight preview generation may remain.

Validation must be deterministic and inexpensive.

Where practical, avoid recalculating identical expensive
data without a corresponding state change.

However, do not introduce complicated caching or stale-state
bugs for an operation that is already inexpensive.

Any performance optimization must preserve correct updates
when the report template, officer position, direction
or selected configuration changes.


============================================================
9. USER DATA PRESERVATION
============================================================

ABSOLUTE REQUIREMENT:

Preserve all user data and customizations.

Including:

- Personal report templates.
- Patrol templates.
- Custom radio phrases.
- Contacts and partner lists.
- Active patrol records.
- Saved patrol history.
- Personal notes.
- Keybindings.
- Radial menu layouts.
- UI positions.
- Existing map settings.
- Existing CEF settings.
- Profiles.
- Statistics.

Do not delete or reset configuration files.

Do not automatically migrate or rewrite custom report
templates to resolve an unknown direction.

Do not remove a user-defined {direction} variable.

Do not modify the updater platform.

If the current project still contains:

moonloader/lib/pa26_update_platform.lua

preserve it byte-identically.

Previously approved SHA-256:

995b131aa0250b7ea407915ad7d109de71a8e43cec088603bc99cc489e60565f

Verify this hash against the actual repository baseline.

If the baseline differs, report the discrepancy rather
than overwriting the file.

Do not publish to GitHub.
Do not create a release.
Do not deploy into the user's game.

Implement and test locally only.


============================================================
10. REQUIRED AUTOMATED REGRESSION TESTS
============================================================

Add focused tests using the existing PA test conventions.

Suggested:

tests/test_direction_template_regression.lua

or extend the existing relevant test suite.

Do not create an incompatible parallel testing framework.

TEST GROUP A — ORIGINAL CRASH REPRODUCTION

Reproduce the exact failure path:

F9 → Partners → Patrol → Patrol Preview.

Use an unknown direction and a custom report template
containing {direction}.

Expected:

- No exception.
- Preview returns nil + meaningful validation message.
- No attempt to call mapGrid.reportValues() with nil.
- No global UI failure.
- No outgoing command.

Include a regression assertion that would fail against
the old buggy implementation.


TEST GROUP B — ALL PATROL PREVIEW ACTIONS

Test:

start
resume
finish
crew
periodic

For each action, verify:

- Known direction.
- Unknown direction.
- Default template.
- Custom template with {direction}.
- Custom template without {direction}.
- Unavailable optional location data.

All expected failures must return normally.

No unhandled Lua exceptions.


TEST GROUP C — RADIO ALERTS

Test the second identified vulnerable call site:

pa26_alerts.lua

Cover at least:

SOS
Shots fired
CODE 0
Patrol-related reports

Verify:

- No crash when directionTemplate() returns nil.
- Error messages propagate correctly.
- No command is emitted on validation failure.
- Valid commands remain unchanged.
- Existing confirmation behavior remains unchanged.


TEST GROUP D — LAST-KNOWN DIRECTION

Test:

1. Officer moves north.
2. Direction is known.
3. Officer stops.
4. Valid last-known direction is retained by existing
   direction-state rules.

The report should still use "север" while that
direction is considered valid.

Separately test that an explicitly unknown or expired
direction does not reuse stale information.

Do not change the direction-state policy as part of
this bugfix.


TEST GROUP E — MAP AND REPORT FORMATTING

Test:

- Missing map_square.
- Empty district.
- Disabled map grid.
- Custom location template.
- Stock location template.
- Missing report template.
- Invalid report-template type.
- Report containing {area}.
- Report containing {location}.
- Report containing both {area} and {map_square}.
- Report without location variables.

Assert that valid formatting stays identical to the
previous approved behavior.

Assert that invalid input produces a controlled error.


TEST GROUP F — DATA VALIDATION

Test:

nil
false
numbers
empty strings
malformed tables
missing optional fields
invalid template variables

Use realistic test fixtures.

Do not mutate production user data.

Invalid configuration must not cause an unhandled
exception during normal UI preview.


TEST GROUP G — UI RECOVERY REGRESSION

Use the project's existing UI harness if available.

Verify:

- Validation failure does not set uiFailed.
- F9 remains available.
- Other sections remain accessible.
- Existing drafts remain intact.
- An actual unexpected renderer error still triggers
  the established recovery mechanism.
- /pa26repair continues working.
- Recovery does not repeat pending commands.

If a real x86 ImGui or MoonLoader runtime is unavailable,
run the unit-level tests and explicitly document which
interactive scenarios require manual in-game verification.

Do not claim that an in-game scenario was tested if
it was only simulated.


============================================================
11. FULL PROJECT REGRESSION PASS
============================================================

After implementing the fix:

1. Run relevant targeted tests.
2. Run the complete existing unit-test suite.
3. Run the project's syntax checks.
4. Run existing Lua module-loading checks.
5. Run existing UI tests if available.
6. Run x86-specific tests if supported.
7. Run configuration validation tests.
8. Run updater-integrity checks.
9. Run existing performance tests if available.

Use the project's actual test runner and documented
commands.

Do not invent passing test results.

If a tool or runtime is unavailable, explicitly report:

- Which test could not run.
- Why it could not run.
- Whether a substitute check was performed.
- What still requires verification in GTA.

Review all changes for:

- New nil-indexing risks.
- Unchecked function return values.
- Unintended changes in report text.
- Unsafe command execution.
- Excessive per-frame work.
- Lost user settings.
- Changed CEF behavior.
- Unexpected dependencies.


============================================================
12. MANUAL IN-GAME VERIFICATION CHECKLIST
============================================================

Prepare a concise manual checklist for the user.

It must include:

[ ] Open F9.
[ ] Open Напарники.
[ ] Open Патруль.
[ ] Inspect all report previews.
[ ] Verify missing direction shows a warning.
[ ] Return to Напарники.
[ ] Open Настройки.
[ ] Close and reopen F9.
[ ] Check a valid northbound patrol report.
[ ] Check a stationary/unknown-direction report.
[ ] Check SOS and other relevant radio actions.
[ ] Verify custom templates remain unchanged.
[ ] Verify no unexpected outgoing commands.
[ ] Verify no new frame-time spikes or freezes.

The user must be able to verify the fix without
resetting any personal settings.


============================================================
13. FINAL REPORT — MANDATORY
============================================================

After completing the work, provide:

A. ROOT CAUSE

Explain the exact bug and how the provided screenshot
corresponds to the defective code.

B. FILES CHANGED

List every changed file and why it was changed.

C. ADDITIONAL BUGS

Identify all analogous unchecked return-value bugs
found during the audit.

Clearly distinguish:

- Confirmed defects.
- Potential risks.
- Already protected call sites.

D. TEST RESULTS

For every test command, report:

- Command executed.
- Tests passed.
- Tests failed.
- Tests skipped.
- Reason for skipping, if applicable.

E. PERFORMANCE

Confirm whether any new per-frame work was introduced.

F. DATA PRESERVATION

Confirm whether any persistent data format or
configuration default changed.

G. UPDATER INTEGRITY

Provide the actual SHA-256 and confirm the updater
was not modified.

H. IN-GAME TEST PLAN

Provide the short manual verification checklist.

I. FINAL STATUS

Use one of:

FIXED — VERIFIED BY AUTOMATED TESTS
FIXED — REQUIRES IN-GAME VERIFICATION
PARTIALLY FIXED — REMAINING ISSUES

Never claim complete in-game verification without
actually running the relevant tests in GTA.

============================================================
14. ACCEPTANCE CRITERIA
============================================================

The task is complete only when:

1. The confirmed pa26_map_grid.lua:83 crash is fixed
   at its real source.

2. pa26_patrol_session.lua correctly propagates
   directionTemplate() errors.

3. pa26_alerts.lua has equivalent protection.

4. All other relevant directionTemplate() call sites
   have been inspected.

5. Unknown direction never crashes a report preview.

6. User-customized templates are preserved.

7. Valid report generation remains unchanged.

8. Normal validation errors cannot close F9.

9. Relevant automated regression tests pass.

10. Existing project tests do not regress.

11. No new expensive per-frame processing is introduced.

12. The updater and personal user data remain untouched.

IMPLEMENT NOW.
First inspect the current repository, reproduce the failure
with a regression test, apply the smallest reliable fix,
then run the complete relevant verification suite.