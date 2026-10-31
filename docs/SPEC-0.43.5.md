# POLICE ASSISTANT 2026
# ADDITIONAL IMPLEMENTATION SPECIFICATION

# Patrol Radio Improvements
# Last-Known Direction Retention
# Pause-Map Patrol Timer
# RP Mask Sequence
# Chat Command Normalization
# Smart 10-55 / Megaphone / 10-57 Workflow
# Defensive Validation & Performance Regression Testing

PRIORITY: HIGH
TYPE: Functional Improvements + Stability Hardening

============================================================
0. RELATIONSHIP TO PREVIOUS TASK
============================================================

IMPORTANT:

This specification is an ADDENDUM to my previously
submitted critical bugfix task.

Do not replace or cancel the previous task.

The previous specification already covers:

- Confirmed F9 crash.
- pa26_map_grid.lua:83 nil template exception.
- Missing directionTemplate() return-value checks.
- pa26_patrol_session.lua.
- pa26_alerts.lua.
- Defensive validation.
- Associated regression testing.

Complete and verify that critical fix first.

Then implement the additional improvements described below.

This document is self-contained for the new features,
but the previous P0 requirements remain mandatory.

Do not perform a broad architectural rewrite.

Do not modify unrelated systems.

Do not publish to GitHub or deploy into the user's game
without separate authorization.


============================================================
1. MANDATORY ENGINEERING CONSTRAINTS
============================================================

Police Assistant 2026 is an existing modular
MoonLoader/LuaJIT project.

Before editing:

1. Inspect the actual current repository.
2. Identify existing implementations and reusable modules.
3. Identify current configuration schemas.
4. Identify existing unit tests.
5. Identify the current working version.
6. Preserve existing user changes.

The provided historical code references are based
on the previously inspected v0.43.3 implementation.

Current files may have changed.

Never blindly overwrite newer implementations.

PRESERVE:

- User profiles.
- Personal RP templates.
- Radio templates.
- Patrol templates.
- Custom bindings.
- Wheel layouts.
- Hotkeys.
- Contacts.
- Crew settings.
- Notes.
- Statistics.
- Active patrol records.
- Patrol history.
- UI positions.
- Map settings.
- CEF settings.
- Copilot preferences.

Keep the updater platform unchanged:

moonloader/lib/pa26_update_platform.lua

Previously approved SHA-256:

995b131aa0250b7ea407915ad7d109de71a8e43cec088603bc99cc489e60565f

Verify against the current baseline.

If the baseline differs, report it rather than replacing
the file.

ARCHITECTURE:

- Native GTA/SAMP reads belong in the world-update layer.
- ImGui callbacks consume prepared state.
- No new native reads directly inside OnFrame.
- Commands use the existing PA executor.
- Officer confirmations remain authoritative.
- No blind command execution.
- No continuous CEF DOM polling.
- No synchronous I/O inside render callbacks.
- No unnecessary new background threads.
- No large-scale refactoring without demonstrable need.

Implement incrementally.

Each functional group must be independently testable.


============================================================
2. LAST-KNOWN DIRECTION — RETENTION & VALIDATION
============================================================

USER REQUIREMENT:

PA must retain the last reliably observed direction
of travel when the officer stops.

Example:

The officer drives NORTH.

The car stops.

The officer remains in the same vehicle.

The officer prepares a radio report.

EXPECTED:

Direction: Север.

Stopping must not cause the direction to become unknown.

RELEVANT EXISTING CODE:

pa26_vehicle.lua

Vehicle:direction()

lastDirectionValue

directionKnown

Previously inspected implementation contains:

    self.lastDirectionValue =
        M.compass(dx, dy, cfg.directions)

The main script obtains direction through:

    sceneServices.vehicle.lastDirectionValue

Inspect the actual current code.

REQUIRED BEHAVIOR:

A. Driving north:

Store Север.

B. Stopping in the same vehicle:

Preserve Север.

C. Driving east afterward:

Update the last-known direction to Восток.

D. Stopping again:

Preserve Восток.

E. Vehicle identity changes:

Invalidate the previous vehicle's direction unless
there is an independently validated reason to retain it.

F. Teleportation / implausible coordinate jump:

Invalidate untrustworthy direction.

G. Missing initial observation:

Direction remains unknown until observed.

H. Temporary lack of movement:

Do not erase a valid last-known direction.

I. Script reload:

Follow existing session-recovery and trust rules.
Do not invent direction information.

J. On-foot movement:

Do not reuse vehicle direction as a newly observed
pedestrian direction without an explicit policy.

IMPORTANT:

The previously confirmed F9 nil error does not mean
that the direction variable itself was nil.

The crash occurred because directionTemplate()
returned nil for an unavailable direction and the
caller passed it into mapGrid.reportValues().

That failure is addressed by the previous P0 task.

This additional task must verify that lastDirectionValue
is actually preserved in the expected driving scenarios.

Do not merely suppress unknown-direction warnings
by inventing a direction.

Do not turn an invalid observation into a trusted one.

TESTS:

- North → stop → report: Север.
- South → stop → report: Юг.
- North → stop → east → stop: Восток.
- Initial stationary state without observations.
- Leaving the vehicle.
- Entering another vehicle.
- Vehicle identity change.
- Teleportation.
- Script reload.
- Missing coordinates.
- Temporary observation loss.

Verify compatibility with the previous directionTemplate()
error-handling fix.


============================================================
3. PATROL RADIO REPORTS — IMPROVED WORDING
============================================================

USER REQUIREMENT:

Improve the default wording of:

- Patrol start.
- Patrol resume.
- Periodic patrol report.
- Patrol finish.
- Crew-change report when appropriate.

Each relevant report must identify:

1. Unit.
2. Patrol action.
3. Verified crew composition.
4. Current location.
5. Map square when available.
6. Last-known valid direction when available.
7. Appropriate radio code.

IMPORTANT:

Preserve the existing structure and terminology
of the current patrol reports.

Do not replace the entire reporting system.

Reuse existing variables:

{unit}
{crew}
{crew_count}
{patrol_start}
{patrol_resume}
{patrol_finish}
{patrol_moving}
{patrol_available}
{area}
{map_square}
{direction}
{duration}

The {duration} variable must remain available internally,
but must NOT appear in default patrol-finish radio reports.

Reuse existing:

Session:crewText()

and automatic LINCOLN/ADAM unit assignment.

Do not implement a second independent crew system.


------------------------------------------------------------
3.1. EXAMPLE — SOLO START
------------------------------------------------------------

[SFPS] LINCOLN-1, начинаю патрулирование.
Состав: Victor Auditore.
Район Downtown (K-12), направление — север.
Код 4, доступен.


------------------------------------------------------------
3.2. EXAMPLE — TEAM START
------------------------------------------------------------

[SFPS] ADAM-1, начинаем патрулирование
в составе: Victor Auditore, Alexander Smith.
Район Downtown (K-12), направление — север.
Код 4, доступны.


------------------------------------------------------------
3.3. EXAMPLE — PERIODIC REPORT
------------------------------------------------------------

[SFPS] ADAM-1, продолжаем патрулирование
в составе: Victor Auditore, Alexander Smith.
Находимся в районе Downtown (K-12),
движемся на север. Код 4.


------------------------------------------------------------
3.4. EXAMPLE — RESUME
------------------------------------------------------------

[SFPS] ADAM-1, возобновляем патрулирование
в составе: Victor Auditore, Alexander Smith.
Текущее местоположение: Downtown (K-12).
Код 4.


------------------------------------------------------------
3.5. EXAMPLE — FINISH
------------------------------------------------------------

[SFPS] ADAM-1, завершаем патрулирование.
Состав: Victor Auditore, Alexander Smith.
Последнее местоположение: Downtown (K-12).
Код 4.


IMPORTANT:

These are STYLE EXAMPLES.

Do not hardcode:

SFPS
ADAM-1
LINCOLN-1
Victor Auditore
Alexander Smith
Downtown
K-12

Use actual server profile, unit, crew and map values.

Preserve the existing approved radio-prefix convention.


------------------------------------------------------------
3.6. REMOVE DURATION FROM FINISH REPORT
------------------------------------------------------------

EXPLICIT REQUIREMENT:

Do NOT include patrol duration in the default
outgoing patrol-finish radio report.

Remove stock phrases such as:

"Время на смене: 01:25:30"

"Продолжительность патруля: ..."

"Время патрулирования: ..."

However:

Do NOT remove elapsed time from PA itself.

The timer must continue working in:

- Patrol HUD.
- Statistics.
- Patrol history.
- Session recovery.
- Personal records.
- Internal scheduling.

This is ONLY a radio-text change.

Do not delete the {duration} variable.

It remains useful elsewhere.

If a user-customized finish template contains {duration},
preserve the custom text and allow the user to edit it.

Do not overwrite personal templates.


------------------------------------------------------------
3.7. CREW VALIDATION
------------------------------------------------------------

REQUIRED:

- Solo patrol uses singular grammar.
- Team patrol uses plural grammar.
- Crew members come from the verified roster.
- Random passengers are not automatically officers.
- Nearby players are not automatically crew members.
- Recycled player IDs must be rejected.
- Missing callsigns must be handled.
- Duplicate officer names must be avoided.
- Crew changes must respect existing confirmation rules.

Use verified IC names for IC radio reports.

Do not silently substitute OOC nicknames for IC names.

If configurable naming styles already exist, preserve them.

UNKNOWN DIRECTION:

If a valid direction exists, use it.

If direction is unknown:

- Stock templates omit the direction phrase cleanly.
- Custom templates requiring direction request clarification.
- No invented direction.
- No nil exception.
- No malformed punctuation.

CHARACTER LIMIT:

Validate the final command after substitution
and CP1251 conversion.

Do not silently truncate.

Do not automatically split a report unless the existing
approved executor explicitly supports that behavior
with the required confirmation.

PRESERVE USER DATA:

Update only recognized stock templates.

If a migration is required, identify unchanged stock
templates reliably.

Never overwrite personalized wording.


============================================================
4. ACTIVE PATROL TIMER DURING ESC MAP
============================================================

CURRENT PROBLEM:

In pa26_patrol_session.lua, Session:tick()
previously required:

    not previous.paused
    and not state.paused

before increasing elapsed_ms.

The main script also uses getGameTimer().

This can cause time spent in the GTA pause menu
to be excluded from active patrol duration.

USER REQUIREMENT:

An ACTIVE patrol must continue counting time while
the officer studies the GTA map:

Esc → Карта.

EXAMPLE:

Before opening the map:

00:15:00

Player spends two minutes on the map.

After returning:

00:17:00

approximately.

No elapsed time should be lost.


------------------------------------------------------------
4.1. DISTINGUISH PATROL AND GAME PAUSE
------------------------------------------------------------

These are different conditions:

A. GTA pause-map open:

Active patrol timer continues.

B. Manual PA patrol pause:

Patrol timer stops.

C. PA patrol resumed:

Timer continues from the saved duration.

D. Character disconnected:

Existing session safety rules apply.

E. Character changed:

Do not continue the old patrol for another character.

F. Confirmed death/respawn:

Preserve existing interruption rules.

G. Game focus lost:

Preserve the existing focus-loss policy.

H. PA reload:

Preserve existing trusted recovery rules.

The GTA menu being open must not automatically mean
the officer stopped patrolling.


------------------------------------------------------------
4.2. CLOCK SOURCE
------------------------------------------------------------

Investigate the actual behavior of getGameTimer()
during Esc pause.

Do not assume GTA game time advances normally.

Use a suitable monotonic elapsed-time source if necessary.

Prefer an existing project clock abstraction.

Do not use os.clock() as a replacement for wall-clock time.

Handle:

- Counter rollover.
- Long pauses.
- Unexpected time jumps.
- Script reload.
- Reconnect.
- Invalid state.
- Stalled game frames.

A legitimate two-minute Esc-map visit must not be
discarded because the elapsed delta exceeds 5000 ms.

However, stale or untrusted sessions must not receive
arbitrary elapsed time.

Do not modify unrelated game timers.


------------------------------------------------------------
4.3. ABSOLUTELY NO COMMANDS DURING ESC
------------------------------------------------------------

While Esc map is open:

- No /r.
- No /f.
- No /d.
- No /m.
- No /su.
- No /pt.
- No keyboard injection.
- No automatic confirmation windows.

Only elapsed time is updated.

If a periodic report becomes due:

- Record that a report is due.
- Do not transmit anything.
- Do not accumulate multiple missed reports.
- Do not replay old reports.

After returning to gameplay:

Offer at most ONE current report.

Use CURRENT:

- Location.
- Crew.
- Unit.
- Direction.
- Server session.

Require normal validation and officer confirmation.

Allow the officer to skip the report.

Do not generate a catch-up queue.


------------------------------------------------------------
4.4. TESTS
------------------------------------------------------------

Test:

- 10 seconds in Esc map.
- 120 seconds in Esc map.
- 900 seconds in Esc map.
- Manual pause before Esc.
- Resume after Esc.
- Periodic report due during Esc.
- Alt-Tab while Esc is open.
- Reconnect.
- Character change.
- PA reload.
- Clock rollover.
- Unexpected timer discontinuity.
- Long game stall.
- Missing player state.

Verify correct elapsed time and zero duplicate reports.


============================================================
5. /MASK ROLEPLAY SEQUENCE
============================================================

SERVER COMMAND CONFIRMED:

The user confirms that Exsellent RP supports:

/mask

This command PUTS A MASK ON THE PLAYER CHARACTER.

Implement the requested roleplay sequence using
the existing server command.


------------------------------------------------------------
5.1. REQUIRED ORDER
------------------------------------------------------------

1. Send RP action:

/me аккуратно расправил маску и натянул её на лицо, скрыв свои черты.

2. Send:

/mask

3. Wait for a short configurable delay.

Suggested initial value:

700 ms.

4. Send:

/offobject


------------------------------------------------------------
5.2. GRAMMATICAL GENDER
------------------------------------------------------------

Use PA's existing gender system.

Male:

аккуратно расправил маску и натянул её на лицо...

Female:

аккуратно расправила маску и натянула её на лицо...

Do not introduce another independent grammar parser.

Allow editing the complete RP phrase in-game.

Validate outgoing text length after gender expansion.


------------------------------------------------------------
5.3. SERVER COMMAND SAFETY
------------------------------------------------------------

/mask is confirmed to equip the mask.

Do not delay implementation merely because of uncertainty
about whether /mask exists.

However, separately inspect /offobject behavior.

Verify that /offobject performs the intended operation
in the supported server/client configuration.

Do not assume that every server command succeeds.

If /mask fails, is rejected or is cancelled:

Do not continue blindly to /offobject.

If command success cannot be observed and sending
/offobject could produce an incorrect effect:

Require officer confirmation before that final step.

Do not falsely report that the mask was equipped
merely because /mask was sent to the client.


------------------------------------------------------------
5.4. EXECUTOR INTEGRATION
------------------------------------------------------------

Use the existing PA command pipeline.

Do not introduce a competing /mask handler.

Do not use blocking sleeps in ImGui.

Do not implement this through continuous CEF scanning.

Trigger on an intentional user action.

Prevent:

- Recursive command interception.
- Duplicate Enter.
- Double-click.
- Native/CEF duplicate events.
- Reconnect duplication.
- Script reload duplication.
- Two simultaneous mask sequences.
- Another script changing a command.
- Executing the final command after cancellation.

The ordinary /mask server command must remain usable
when the PA RP feature is disabled.


------------------------------------------------------------
5.5. SETTINGS
------------------------------------------------------------

Add compact controls inside an appropriate existing
RP/actions settings section:

[ ] RP-отыгровка при надевании маски

[ Редактировать текст ]

[ Задержка после /mask ]

[ Предпросмотр ]

[ Сбросить текст ]

Avoid creating an unnecessary new large settings tab.

Preserve settings through reloads and updates.


============================================================
6. /B .И → /N CHAT COMMAND NORMALIZATION
============================================================

USER REQUIREMENT:

When the player manually enters:

/b .и Привет, как дела?

The actual outgoing command must become:

/n Привет, как дела?

IMPORTANT:

The "и" in ".и" is Cyrillic.


------------------------------------------------------------
6.1. EXACT MATCHING
------------------------------------------------------------

Match only:

/b .и <non-empty text>

Support reasonable whitespace differences.

Do not modify unrelated messages.

EXAMPLES:

INPUT:
/b .и Привет!

OUTPUT:
/n Привет!

INPUT:
/b .и   Сегодня патрулируем.

OUTPUT:
/n Сегодня патрулируем.

INPUT:
/b Привет!

OUTPUT:
/b Привет!

INPUT:
/b .информация

OUTPUT:
/b .информация

INPUT:
/n Привет!

OUTPUT:
/n Привет!

Do not transform a larger word beginning with ".и".

Do not emit an empty /n when no message text exists.


------------------------------------------------------------
6.2. ENCODING
------------------------------------------------------------

Handle:

- Cyrillic UTF-8.
- CP1251 outgoing commands.
- Mixed Cyrillic/Latin text.
- Spaces.
- Punctuation.

Normalize at the correct stage of the existing codec.

Never compare raw CP1251 bytes against UTF-8 literals
without decoding appropriately.

Avoid double encoding.

Preserve user text.

Validate final outgoing length.


------------------------------------------------------------
6.3. NATIVE / CEF
------------------------------------------------------------

Integrate with existing outgoing-command handling.

Support the actual submitted command from:

- Native SA:MP chat.
- CEF launcher chat, where supported by the existing bridge.

Do not continuously observe the text field.

Do not add new DOM polling.

Do not add new per-frame parsing.

Perform conversion only on actual submission.

Avoid:

- Duplicate transmission.
- Recursive processing.
- Double interception.
- Modification of unrelated scripts' commands.
- Modification of PA-generated commands without authorization.

Preserve the recently optimized CEF bridge.


============================================================
7. SMART 10-55 → MEGAPHONE → 10-57 WORKFLOW
============================================================

USER REQUIREMENT:

A normal traffic stop should allow repeated megaphone
warnings before escalation.

Suggested default:

THREE warnings.

However, if the suspect clearly flees, the officer
must be able to start 10-57 immediately.

OFFICER CONTROL IS MANDATORY.


------------------------------------------------------------
7.1. REUSE EXISTING COPILOT SYSTEMS
------------------------------------------------------------

Inspect:

pa26_copilot.lua
pa26_copilot_incident.lua
pa26_copilot_settings.lua
pa26_vehicle.lua

Existing functionality includes:

repeat_megaphone
warning_cooldown_ms
stop_order
pursuit
flee_offer
warning_count
ooc_warning_count

Extend the existing implementation.

Do not create a second independent pursuit state machine.

IMPORTANT:

Existing warning_count and ooc_warning_count may refer
to use-of-force or tire-shooting warnings.

Do not repurpose those values for the initial
traffic-stop sequence.

Use a separate stop-warning counter if required.


------------------------------------------------------------
7.2. NORMAL TRAFFIC STOP
------------------------------------------------------------

STEP 1:

Officer selects a verified vehicle.

PA offers the initial stop demand.

After confirmed execution:

10-55 — Предупреждение 1/3

STEP 2:

If the vehicle continues moving without sufficiently
reliable evidence of active flight:

After a configurable interval, offer:

[ Повторить требование ]

After execution:

10-55 — Предупреждение 2/3

STEP 3:

After another interval:

[ Повторить требование ]

After execution:

10-55 — Предупреждение 3/3

Do not send repeated commands automatically.

The officer must confirm each action.

THREE WARNINGS ARE NOT AN AUTOMATIC PURSUIT TRIGGER.

A pursuit still requires the officer's decision
and an appropriate observed situation.


------------------------------------------------------------
7.3. IMMEDIATE FLIGHT EXCEPTION
------------------------------------------------------------

Example:

The officer issues the FIRST stop demand.

The driver immediately accelerates away.

The vehicle increases its distance significantly.

PA has sufficiently reliable current observations.

In this case:

Immediately offer:

[ Начать 10-57 VICTOR ]

Do not force two additional megaphone warnings.

Do not artificially delay a genuine pursuit.

The officer confirms the 10-57 action.

Never send it automatically.


------------------------------------------------------------
7.4. WARNING SETTINGS
------------------------------------------------------------

Add configurable settings:

Stop-warning count:

Default 3.

Warning suggestion cooldown:

Default suggestion 4000 ms.

Enable repeated stop-warning suggestions:

Default enabled.

Enable immediate pursuit suggestion on confirmed flight:

Default enabled.

Keep these settings separate from use-of-force
warning counters.

Do not enforce a fixed three-warning requirement
against a confirmed flight scenario.


------------------------------------------------------------
7.5. WARNING COUNT VALIDATION
------------------------------------------------------------

Increment the warning counter only after a confirmed
command emission through the PA executor.

Do not count:

- Cancelled proposals.
- Rejected validation.
- Duplicate events.
- UI previews.
- Unsent commands.
- Repeated proposals.
- Failed executor requests.

Distinguish client-side submission from actual server
acceptance if the server does not provide acknowledgement.

Do not claim success that cannot be observed.


------------------------------------------------------------
7.6. TARGET IDENTITY & INCIDENT LIFECYCLE
------------------------------------------------------------

Warning state must belong to the current verified incident.

Preserve existing:

- Vehicle identity.
- Driver identity.
- Player generation.
- Incident ID.
- Session identity.
- Stream-out handling.
- Target retention.
- Cancellation behavior.

Do not transfer warnings to another vehicle or driver.

Handle:

- Player reconnect.
- Recycled SAMP ID.
- Vehicle replacement.
- Driver exit.
- Target loss.
- Vehicle stream-out.
- Incident finish.
- Officer cancellation.
- PA reload.

A temporary observation failure must not automatically
destroy the incident if existing retention rules
allow it to remain valid.

However, stale identity must never authorize commands.


------------------------------------------------------------
7.7. FALSE POSITIVE PREVENTION
------------------------------------------------------------

Do not interpret minor movement as confirmed flight.

Examples:

- GPS jitter.
- Vehicle rolling slightly downhill.
- Driver moving toward the curb.
- Small positioning corrections.
- Stream-in coordinate jumps.
- Temporarily missing coordinates.
- Camera movement.
- Game interpolation.

Use verified movement thresholds and existing Copilot logic.

If evidence is insufficient:

Show an optional neutral suggestion.

Do not falsely declare that the suspect fled.


============================================================
8. /SU AND /PT — SEPARATE SAFE ACTIONS
============================================================

Do not blindly chain:

10-57 → /su → /pt

into one automatic action.

DESIRED WORKFLOW:

1. Officer confirms pursuit.
2. PA prepares the 10-57 report.
3. Officer confirms the report.
4. PA may suggest an appropriate /su action.
5. Officer confirms the legal basis.
6. PA may suggest /pt separately.

Pursuit initiation does not automatically justify
a specific wanted level.

Preserve existing UK/AK references and procedures.

No automatic wanted assignment without officer confirmation.

No blind delayed commands.

If an action is prepared and delayed:

Revalidate everything before execution.

CHECK:

- Target ID.
- Target generation.
- Nickname/identity.
- Vehicle.
- Incident.
- Connection.
- Character.
- Legal basis.
- Command cooldown.
- Existing queued actions.

If outdated:

Cancel the proposal.

Do not send it.

Show a concise explanation.

Avoid competing modals.

Use a small configurable suggestion cooldown if helpful,
but do not prevent urgent manual action.

No automatic /su or /pt merely because a timer expired.


============================================================
9. SHARED EDGE-CASE REQUIREMENTS
============================================================

Test the interaction of all new features with:

- F9 opening and closing.
- Esc map opening and closing.
- Native chat.
- CEF chat.
- Server dialogs.
- PA modals.
- Existing executor queue.
- Manual action confirmation.
- Player death.
- Respawn.
- Reconnect.
- Character change.
- Vehicle change.
- Target stream-out.
- Duplicate Enter.
- Double-click.
- Reused player IDs.
- Script reload.
- PA recovery.
- Demo mode.
- Focus loss.
- Missing coordinates.
- Unknown direction.
- Invalid user templates.
- Very long messages.
- Invalid text encoding.

EXPECTED:

Normal validation errors must not cause a Lua exception.

No unexpected F9 closure.

No duplicate commands.

No stale commands.

No lost user settings.

No automatic execution of unconfirmed actions.


============================================================
10. PERFORMANCE REQUIREMENTS
============================================================

The project recently required significant CEF
performance corrections.

Do not reintroduce frame-time degradation.

STRICTLY AVOID:

- Continuous CEF DOM polling.
- Per-frame chat-field scanning.
- New unnecessary WinAPI hooks.
- Expensive global player scans.
- Blocking I/O in ImGui.
- Network operations in render callbacks.
- Repeated JSON serialization every frame.
- Unbounded event queues.
- Excessive diagnostic logging.
- Unnecessary FFI allocations.
- Continuous command-text conversion.

Chat transformations must be event-driven.

Patrol timing must remain lightweight.

Copilot warnings must reuse existing scene observations.

Do not add a new polling loop when an existing
service tick can handle the work.

Do not create complicated caching that introduces
stale-state bugs.

Keep all changes modular and measurable.

Use existing performance instrumentation when available.

Report measurable before/after differences if tests
or benchmarks support them.


============================================================
11. CONFIGURATION & MIGRATION SAFETY
============================================================

New settings must:

- Have validated defaults.
- Be editable inside PA.
- Persist correctly.
- Survive PA reload.
- Survive game restart.
- Survive future updates.
- Respect existing configuration migration conventions.

Never reset personal settings to introduce new defaults.

Preserve unknown or customized values according to
the project's existing schema policy.

Do not rewrite custom radio templates.

Do not delete the duration variable.

Do not alter the frozen updater.

Avoid unnecessary new configuration files.


============================================================
12. AUTOMATED REGRESSION TESTS
============================================================

Add or extend tests using the existing test infrastructure.

Do not create a separate incompatible testing framework.


TEST GROUP A — DIRECTION

- Last known north survives stopping.
- Last known south survives stopping.
- Direction updates after turning.
- Initial unknown direction.
- Vehicle identity change.
- Teleportation.
- Unknown direction with stock report.
- Unknown direction with custom report.
- No nil exception.
- No F9 crash.


TEST GROUP B — PATROL RADIO

- Solo start.
- Team start.
- Resume.
- Periodic.
- Finish.
- Crew change.
- Missing partner.
- Recycled ID.
- Long names.
- Long unit identifier.
- Unknown district.
- Unknown direction.
- Custom-template preservation.
- Correct grammatical number.
- CP1251 length validation.

Assert that default finish reports do NOT contain
patrol duration.

Assert that internal statistics STILL contain
the correct patrol duration.


TEST GROUP C — PAUSE MAP

- 10-second map visit.
- 2-minute map visit.
- 15-minute map visit.
- Manual patrol pause.
- Focus loss.
- Reconnect.
- Clock rollover.
- Clock jump.
- Periodic report due during Esc.
- No command during pause.
- No catch-up spam.
- Accurate duration after returning.


TEST GROUP D — MASK

- Successful mask application.
- Correct RP text.
- Correct gender.
- Correct command order.
- Configurable delay.
- Failed /mask.
- Cancelled sequence.
- Duplicate Enter.
- Reconnect.
- Script reload.
- Missing acknowledgement.
- /offobject safety.
- Feature disabled.
- Existing server command preserved.


TEST GROUP E — CHAT CONVERSION

- /b .и text becomes /n text.
- Ordinary /b unchanged.
- Ordinary /n unchanged.
- Empty text.
- Similar nonmatching prefixes.
- Cyrillic text.
- Mixed-language text.
- CP1251.
- Native chat.
- CEF chat.
- Duplicate events.
- No recursion.


TEST GROUP F — TRAFFIC STOP

- First warning.
- Second warning.
- Third warning.
- Warning cooldown.
- Cancelled warning.
- Driver complies.
- Driver flees after first warning.
- Driver flees after second warning.
- Driver remains stationary.
- Minor GPS jitter.
- Vehicle changes.
- Driver exits.
- Recycled player ID.
- Stream-out.
- Officer cancellation.
- Incident reset.
- Immediate 10-57 proposal.
- No automatic 10-57.


TEST GROUP G — /SU AND /PT

- Independent action confirmation.
- Correct legal grounds.
- No automatic wanted assignment.
- Expired proposal.
- Target changed.
- Reused ID.
- Reconnect.
- Cooldown.
- Duplicate suppression.
- No stale delayed command.


TEST GROUP H — PERFORMANCE & COMPATIBILITY

- No new continuous CEF operations.
- No additional expensive render operations.
- No command-processing recursion.
- No unbounded memory growth.
- Existing UI tests remain passing.
- Existing updater integrity tests remain passing.


============================================================
13. IMPLEMENTATION ORDER
============================================================

Follow this order:

PHASE 0:

Complete the previously submitted F9 critical bugfix.

Run focused regression tests.

PHASE 1:

Last-known direction retention and patrol radio improvements.

Run patrol/report tests.

PHASE 2:

Esc-map patrol timer continuation.

Run timing/recovery tests.

PHASE 3:

/mask RP sequence and /b .и normalization.

Run command-pipeline tests.

PHASE 4:

Smart 10-55 warning workflow and 10-57 escalation.

Run Copilot tests.

PHASE 5:

Safe /su and /pt interaction.

Run end-to-end workflow tests.

PHASE 6:

Run the complete available project test suite.

Include:

- Lua syntax checks.
- Module-loading checks.
- Unit tests.
- Configuration validation.
- Existing ImGui tests.
- x86-specific tests where supported.
- CEF regression tests.
- Patrol-session tests.
- Radio-report tests.
- Copilot tests.
- Updater integrity checks.

Do not continue past a failing critical test
without resolving or explicitly reporting it.


============================================================
14. FINAL REPORT — REQUIRED
============================================================

After implementation, provide:

1. CHANGED FILES

Every changed file and its purpose.

2. DIRECTION RETENTION

Explain when lastDirectionValue is retained
and when it is invalidated.

3. PATROL RADIO

Show before/after examples for:

Start.
Periodic.
Resume.
Finish.

Confirm that duration was removed ONLY from
default outgoing finish reports.

4. ESC TIMER

Identify the selected clock source.

Explain how map time is counted.

Explain what happens when periodic reports become due.

5. MASK

Explain:

- RP sequence.
- Command ordering.
- Delay.
- Failure handling.
- /offobject behavior.

6. CHAT NORMALIZATION

Explain:

- Matching.
- Encoding.
- Native/CEF compatibility.
- Duplicate prevention.

7. COPILOT

Explain:

- Three-warning workflow.
- Cooldowns.
- Immediate flight exception.
- Incident identity checks.
- /su and /pt validation.

8. DATA PRESERVATION

Confirm that personal settings and templates remain intact.

9. PERFORMANCE

List any newly introduced per-frame operations.

Include measurements if available.

10. TEST RESULTS

For each command:

- Exact command executed.
- Tests passed.
- Tests failed.
- Tests skipped.
- Reason for skipped tests.

11. UPDATER

Actual SHA-256.

Confirm byte-identical preservation.

12. KNOWN LIMITATIONS

Identify anything that requires in-game verification.

13. MANUAL TEST CHECKLIST

Provide a concise numbered list for testing
the new functions inside GTA.

FINAL STATUS:

Use one of:

IMPLEMENTED — AUTOMATED TESTS PASSED
IMPLEMENTED — IN-GAME VERIFICATION REQUIRED
PARTIALLY IMPLEMENTED — REMAINING ISSUES

Do not claim in-game testing unless GTA/MoonLoader
was actually used.

Do not publish to GitHub.

Do not deploy to the user's game.

IMPLEMENT INCREMENTALLY AND VERIFY THOROUGHLY.