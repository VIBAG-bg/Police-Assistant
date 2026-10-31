# ADDITIONAL REQUIREMENTS FOR POLICE ASSISTANT v0.43.3
## Four Regression Fixes, CEF Chat Performance, and Release Verification

IMPORTANT CONTEXT:

Police Assistant v0.43.2 has ALREADY been released and published.

You are currently implementing v0.43.3, including the UI/UX
reorganization, knowledge-base improvements, and further CEF chat
performance optimizations.

Treat this document as an ADDENDUM to the existing v0.43.3
specification.

DO NOT:
- Start a separate release.
- Reimplement functionality that already works.
- Revert improvements introduced in v0.43.2.
- Rewrite stable subsystems unnecessarily.
- Sacrifice functionality for performance.
- Remove existing safety checks to make tests pass.

First inspect the CURRENT working tree, identify which fixes have
already been implemented, and apply only the remaining changes.

Pay particular attention to the four issues below.

============================================================
1. P1 — UNKNOWN DIRECTION IN COPILOT RADIO REPORTS
============================================================

Affected files:
- moonloader/lib/pa26_copilot.lua
- moonloader/lib/pa26_report_context.lua
- Relevant radio/report tests

PROBLEM:

In the v0.43.2 source, Copilot can substitute the literal value
"неизвестно" when the current direction is unavailable.

Some Copilot report-generation paths do not consistently use the
existing direction-handling mechanism.

This may produce unnatural radio messages such as:

"Продолжаю патрулирование в Сан-Фиерро,
двигаюсь на неизвестно."

Similar problems may occur in dispatch, pursuit, and other reports
containing optional direction-dependent phrases.

REQUIRED BEHAVIOR:

1. Inspect every Copilot report-generation path that uses:
   - {direction}
   - Vehicle heading
   - Last known travel direction
   - Direction-dependent phrases

2. Reuse the existing mechanism in:
   pa26_report_context.directionTemplate()

   Adapt its integration where appropriate instead of introducing
   a competing direction-processing system.

3. Direction source priority:

   a) Last RELIABLY OBSERVED travel direction of the relevant vehicle
      before it stopped or disappeared.

   b) Current reliable movement direction, where available and
      relevant to the report.

   c) Vehicle orientation ONLY as an explicitly approximate heading,
      if the report type permits this distinction.

   d) Unknown direction.

4. If direction is unknown:

   - Remove the direction-dependent phrase from DEFAULT templates
     when this can be done safely.
   - Preserve the rest of the report and its grammar.
   - Never produce "на неизвестно", "в сторону неизвестно",
     or similarly unnatural combinations.
   - Do not fabricate compass directions or map information.

5. USER-CUSTOMIZED TEMPLATES MUST BE PRESERVED.

   Do not silently rewrite, delete, or replace user-defined radio
   templates.

   If a custom template explicitly contains {direction} and no
   reliable value is available, use the existing safe preview/
   validation mechanism and a documented fallback policy.

6. Ensure that the same direction semantics are consistently
   applied to relevant Copilot, dispatch, pursuit, and patrol
   continuation reports without changing unrelated templates.

REGRESSION TESTS:

- Valid direction available.
- Direction missing.
- Vehicle stationary.
- Vehicle stops after moving in a known direction.
- Vehicle streams out.
- Patrol continuation report.
- Dispatch report.
- Default template.
- Customized template containing {direction}.
- Long report with multiple placeholders.

ACCEPTANCE CRITERION:

No default PA report produces an unnatural unknown-direction phrase.

Existing customized templates remain intact.


============================================================
2. P1 — CIVILIAN PASSENGERS COUNTED AS POLICE OFFICERS
============================================================

Affected file:
- moonloader/lib/pa26_dispatch.lua

Relevant function:
- M.officers()

PROBLEM:

The v0.43.2 implementation contains logic based on:

    local occupants = c.cruiserOccupants

However, cruiserOccupants can represent all vehicle occupants,
not exclusively verified police officers.

Consequently, PA may incorrectly believe there are enough police
officers for an operation even when some passengers are civilians.

A more reliable patrolOccupants representation already exists
in v0.43.2.

REQUIRED BEHAVIOR:

1. Inspect the actual data structures and validation rules for:

   - cruiserOccupants
   - patrolOccupants
   - Colleague identification
   - Active crew members
   - Confirmed nearby police officers

2. For calculations requiring POLICE STAFF, count only officers
   whose police status is confirmed by an existing trustworthy
   mechanism.

3. Reuse patrolOccupants or an equivalent verified-officer source.

4. Do not automatically treat:

   - Every vehicle passenger
   - Every nearby player
   - Every saved contact
   - Every player in a police vehicle

   as a confirmed police officer.

5. Unknown identities must not silently increase the verified
   officer count.

6. Keep the distinction between:

   - Total vehicle occupants
   - Verified police officers
   - Officers currently participating in the same operation

7. Preserve existing dispatch requirements and their authoritative
   knowledge-base references.

REGRESSION TESTS:

A. One officer driving alone:
   Verified officers = 1.

B. One officer + one civilian passenger:
   Verified officers = 1.

C. Two confirmed police officers:
   Verified officers = 2.

D. One confirmed officer + one unidentified passenger:
   Verified officers = 1.

E. Verified colleague leaves the vehicle:
   Recalculate correctly.

F. Player reconnects or receives a different server ID:
   No stale identity-based officer count.

G. No verified roster available:
   Use a conservative fallback; do not invent officers.

ACCEPTANCE CRITERION:

Civilian and unverified passengers can NEVER satisfy a minimum
police staffing requirement.


============================================================
3. P1 — /ud CONTACT FOLLOWED BY VEHICLE STREAM-OUT
============================================================

Affected files:
- moonloader/lib/pa26_copilot_incident.lua
- moonloader/lib/pa26_copilot.lua
- Relevant state-machine tests

PROBLEM:

The current traffic-stop completion logic primarily offers
completion after:

- The officer returns to the cruiser; OR
- The stopped vehicle is observed departing.

An edge case remains:

1. The officer performs a legitimate 10-55.
2. The officer manually sends /ud, including through a custom bind.
3. PA observes the /ud command.
4. The stopped vehicle suddenly disappears from the streamed
   game objects.
5. No reliable departure movement was observed.
6. The officer is still on foot.

In this scenario, an automatic finish offer may never appear.

IMPORTANT:

Vehicle stream-out is NOT proof that the driver fled.

Do not automatically start pursuit merely because the vehicle
is no longer streamed.

REQUIRED BEHAVIOR:

1. Preserve the existing manual /ud recognition mechanism.

2. Recognize /ud regardless of whether it was sent:

   - Manually through chat.
   - Through a user-defined binding.
   - Through another existing legitimate command path.

   Use the observable outgoing-command event, not the name of
   the binding.

3. Keep these concepts separate:

   - Contact observed (/ud).
   - Stop reason actually explained.
   - Vehicle visually departed.
   - Vehicle merely became unavailable/stale.
   - Traffic stop completed.

4. Do not automatically mark explain_stop as completed solely
   because /ud was used.

5. Preserve the last known vehicle and traffic-stop context
   after stream-out.

6. When /ud has been observed for the current stop and the
   stopped vehicle becomes unavailable:

   If the situation has not already been completed, offer an
   appropriate Y/N completion prompt.

   Suggested text:

   "10-55 завершена? Доложить 10-99 / Код 4? [Y/N]"

   The prompt must remain consistent with the existing Copilot
   toast and confirmation system.

7. On Y:

   Offer or execute the existing finish-report workflow,
   subject to its normal validation and confirmation rules.

   Use the last reliable vehicle details, location, unit,
   and stop outcome.

   Clearly distinguish last-known data from current data.

8. On N:

   DO NOT automatically start a pursuit based solely on
   vehicle stream-out.

   If actual flight/departure evidence was previously observed,
   the next appropriate prompt may be:

   "Начать 10-57 VICTOR? [Y/N]"

   Otherwise, keep the situation active and allow the officer
   to continue or resolve it manually.

9. Do not repeatedly offer the same finish toast every frame.

   Add appropriate state guards, cooldowns, and dismissal
   handling consistent with the existing architecture.

10. Do not create a false finish/pursuit prompt when:

    - /ud belongs to a different player or situation.
    - The active vehicle is intentionally changed.
    - The stop has already ended.
    - The relevant state was reset.
    - The player is entering text in CEF.
    - Another confirmation modal already owns Y/N input.

REGRESSION TESTS:

- /ud + return to cruiser.
- /ud + confirmed vehicle departure.
- /ud + abrupt stream-out without departure evidence.
- No /ud + abrupt stream-out.
- /ud used through a custom binding.
- Different vehicle selected.
- Wrong player ID associated with /ud.
- Officer cancels the finish offer.
- Officer accepts the finish offer.
- Officer rejects finish after confirmed flight.
- Officer rejects finish after stream-out only.
- Multiple ticks after toast dismissal.
- Last known vehicle data retained correctly.

ACCEPTANCE CRITERION:

A legitimate traffic stop can still be completed after stream-out.

Stream-out alone never causes an automatic 10-57 pursuit.


============================================================
4. P2 — WRONG SPEECH DRAFT AFTER CHANGING STOP REASON
============================================================

Affected file:
- moonloader/lib/pa26_ground_window.lua

PROBLEM:

The traffic-stop explanation window tracks manual edits using
a flag such as:

    speechEdited = true

When the officer manually edits the speech and then selects
another stop reason, the old custom text may remain.

Example:

1. Select speeding.
2. Manually edit the explanation.
3. Change the reason to running a red light.
4. The speech field still describes speeding.

This can lead to an incorrect RP message being sent.

REQUIRED BEHAVIOR:

1. Inspect the existing speech draft and reason-selection logic.

2. Avoid sending text associated with a previous reason after
   the selected reason changes.

3. Preferred UX:

   - Maintain a separate speech draft for each selected reason
     when feasible.

   OR

   - On reason change, clearly offer to generate a new speech
     while preserving the old manually edited text until the
     user confirms replacement.

4. If the previous draft contains unsaved manual changes,
   never silently discard them.

5. Provide a clear way to restore the standard speech for
   the newly selected reason.

6. Make the currently selected reason visible near the preview
   so the officer can quickly detect mismatches.

7. Preserve:

   - User-defined templates.
   - Natural-language speech editing.
   - Article selection.
   - Scrollable reason list.
   - Existing send confirmations.
   - Manual RP workflow.

8. Do not introduce an extra modal for every ordinary reason
   selection when there are no manual edits.

REGRESSION TESTS:

- Reason A selected.
- Reason A manually edited.
- Switch to Reason B.
- Switch back to Reason A.
- Restore default speech.
- Cancel reason change with modified text.
- Select another reason without editing.
- Send after a reason change.
- Reopen the window during the same stop.

ACCEPTANCE CRITERION:

The officer must never accidentally send a speech draft that
belongs to a different selected stop reason.


============================================================
5. P0 — CEF CHAT INPUT LAG AND MICRO-FREEZES
============================================================

THIS IS THE MOST IMPORTANT USER-EXPERIENCE REQUIREMENT.

The user previously experienced noticeable input lag and
micro-freezes in the game's CEF chat while Police Assistant
was enabled.

Symptoms included:

- Stuttering while typing individual characters.
- Short freezes during continuous typing.
- Delayed visual updates of entered text.
- Freezes when selecting words with the mouse.
- Lag when dragging across text.
- Slow editing, deletion, and sometimes pasting.

When PA was disabled, normal CEF chat interaction was smooth.

v0.43.2 introduced meaningful optimizations, including:

- Removal of expensive live input preview processing.
- Restricting certain CEF event handling.
- Reducing expensive Lua mouse-event processing.
- Limiting repeated CEF integration loading.
- Deferring some CEF file checks while typing.

These improvements MUST be preserved.

However, synthetic improvements alone do not prove that the
real GTA/SA:MP CEF environment is free from micro-freezes.

PRIMARY GOAL:

The user must be able to type, edit, paste, delete, and select
text in CEF chat with PA enabled as smoothly as with PA disabled,
while retaining ALL other Police Assistant functionality.

-------------------------
5.1. Investigate thoroughly
-------------------------

Inspect the full input/event pipeline:

CEF DOM input events
    -> CEF adapter
    -> JavaScript event bridge
    -> Lua/MoonLoader event handlers
    -> State synchronization
    -> UI updates
    -> Other PA subsystems

In particular, investigate:

1. input, keydown, keyup, beforeinput, composition events.
2. selectionchange and mouse-selection handling.
3. Mouse movement listeners and event propagation.
4. requestAnimationFrame callbacks.
5. MutationObserver callbacks.
6. Forced synchronous layout reads.
7. getBoundingClientRect and computed-style lookups.
8. Repeated DOM queries.
9. Repeated JSON serialization.
10. Repeated calls between Lua and CEF.
11. Per-frame resource/file checks.
12. Excessive background polling.
13. Unexpected repeated callback registration.
14. Feedback loops between CEF and PA state updates.
15. Any expensive text-width or chat-splitting calculations
    triggered per character or selection movement.

Do not assume the remaining problem is necessarily inside
pa26-chat.js.

The bottleneck may be caused by Lua hooks, bridge interactions,
other PA modules, or the integration between these components.

-------------------------
5.2. Performance requirements
-------------------------

A. No heavy work per character.

B. No heavy work per selectionchange event.

C. No repeated full DOM scans during typing.

D. No repeated traversal of all binds, knowledge records,
   chat messages, or PA UI elements during text editing.

E. Avoid unnecessary synchronous CEF -> Lua -> CEF round trips.

F. Cache stable derived values and invalidate only when necessary.

G. Move nonessential processing outside the latency-sensitive
   input path.

H. Do not delay or debounce the actual input rendering.

I. Preserve normal text editing behavior:

   - Ctrl+A
   - Ctrl+C
   - Ctrl+V
   - Backspace
   - Delete
   - Arrow keys
   - Shift+Arrow selection
   - Mouse drag selection
   - Double-click word selection
   - Right-click/context operations where supported
   - Russian and English text
   - IME/composition behavior where applicable

J. Preserve safe chat-length validation and message splitting.

   These checks may be performed during submission rather
   than on every keystroke.

   It is acceptable to remove the optional live warning
   that a message will wrap into two lines.

   It is NOT acceptable to break safe outgoing-message
   handling merely to remove that warning.

K. PA must remain responsive while the chat is open.

L. All F4/F9, Copilot, quick reports, binds, radar,
   knowledge tools, and other features must continue working.

-------------------------
5.3. Benchmark and profiling
-------------------------

Do not rely exclusively on the previously reported synthetic
results.

The v0.43.2 documentation reported improvements such as:

Median input processing:
    ~0.20 ms -> ~0.10 ms

95th percentile:
    ~0.50 ms -> ~0.30 ms

CSS reads:
    59 -> 7

Geometry checks:
    17 -> 2

HTTP requests:
    11 -> 2

Treat these as previously reported SYNTHETIC measurements,
not independently verified in-game results.

For v0.43.3:

1. Reproduce the existing automated benchmark.

2. Record the exact environment, test setup, workload,
   sample size, measurement method, and limitations.

3. Identify remaining expensive event handlers.

4. Add realistic stress tests:

   - Continuous typing.
   - Fast typing.
   - Large pasted text.
   - Long Russian messages.
   - Rapid backspace/delete.
   - Selecting individual words.
   - Dragging across multiple words.
   - Repeated selection/deselection.
   - Chat history containing many messages.
   - Chat open during an active Copilot situation.
   - F4/F9 opening and closing while chat is used.

5. Profile Lua-side work as well as JavaScript.

6. Avoid introducing instrumentation that itself causes
   noticeable input lag.

7. Provide a practical manual testing checklist that can be
   executed in the real Exsellent RP client.

8. Clearly distinguish:

   - Automated tests passed.
   - Synthetic benchmarks passed.
   - Native integration checks passed.
   - Actual GTA/SA:MP gameplay tests completed.
   - Actual gameplay tests NOT performed.

Never claim the real in-game lag is fixed unless it has actually
been tested in the relevant environment.

-------------------------
5.4. Release asset verification
-------------------------

There was a version/provenance inconsistency in earlier reports.

The previously supplied v0.43.1 archive contained a different
pa26-chat.js from the v0.43.2 source archive.

Therefore:

1. Inspect the actual files, not only release notes.

2. Compare SHA-256 values for:

   - The released v0.43.2 CEF adapter.
   - The current v0.43.3 working version.
   - The final v0.43.3 release package.

3. Verify that the final CEF JavaScript is included in the
   correct update/install payload when necessary.

4. Verify that an existing v0.43.2 installation can receive
   the new CEF changes through the supported updater.

5. Avoid unnecessary rewriting of the protected update platform.

6. Preserve file integrity and established updater safeguards.

7. Document precisely which CEF assets changed and why.

ACCEPTANCE CRITERION:

CEF chat must remain fully functional, and PA must not introduce
perceptible typing or mouse-selection freezes in real gameplay.

Automated benchmark improvements are supporting evidence,
not proof of the final gameplay outcome.


============================================================
6. TESTING, BACKWARD COMPATIBILITY, AND DELIVERY
============================================================

Do not treat these four issues as unrelated one-line patches.

Inspect how they interact with the existing Copilot state machine,
report preparation, game-thread event pipeline, UI confirmations,
and player identity tracking.

For each issue:

1. Write a regression test that FAILS against the affected
   v0.43.2 behavior, where reproducible.

2. Implement the smallest maintainable correction.

3. Verify the regression test passes.

4. Verify existing behavior is not broken.

5. Run the relevant full test suites.

6. Check for unintended side effects.

Additional requirements:

- Preserve configuration compatibility with v0.43.2.
- Preserve the 0.43.3 UI/UX reorganization currently underway.
- Preserve custom binds and manual RP.
- Preserve existing user-defined report templates.
- Preserve established command execution guards.
- Preserve automatic update functionality.
- Do not create additional chat input hooks unnecessarily.
- Do not remove features merely to improve performance numbers.
- Do not introduce new UI clutter.
- Do not introduce per-frame expensive processing.
- Do not claim unperformed gameplay tests as completed.

FINAL REPORT:

Provide a dedicated section covering these issues.

For each issue, report:

1. Root cause.
2. Exact files/functions changed.
3. Implementation details.
4. Regression tests added.
5. Test results.
6. Remaining limitations.

For CEF performance, additionally report:

- Actual JavaScript changes.
- Lua-side changes.
- Before/after benchmark measurements.
- Test methodology.
- Whether testing was synthetic or performed in GTA.
- Whether the v0.43.3 updater includes the corrected CEF assets.
- Whether additional in-game validation is required.

FINAL PRIORITY ORDER:

P0:
CEF chat must be smooth without sacrificing PA functionality.

P1:
Correct direction handling, verified officer counting,
and traffic-stop completion after /ud + stream-out.

P2:
Safe stop-reason speech editing.

P3:
Optional UI polish, only after the above requirements pass.

DO NOT release v0.43.3 with known P0 regressions.

The ultimate objective is simple:

Police Assistant should provide all its existing functionality
without making ordinary in-game activities — especially typing
and selecting text in CEF chat — slower than when PA is disabled.