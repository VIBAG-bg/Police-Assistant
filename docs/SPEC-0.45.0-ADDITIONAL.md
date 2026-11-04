# Police Assistant 2026 v0.45.0 — Additional Mandatory Requirements

Please incorporate the following requirements into the ongoing v0.45.0 implementation.

These are additional requirements, not replacements for the previously approved specification, review clarifications, preservation rules, or safety restrictions.

**Important:** Several issues described below affect existing v0.44.0 functionality and should be treated as compatibility and regression priorities, not merely optional new features.

## 1. Gender-Aware RP Templates — Full Audit and Correction

Perform a comprehensive audit of all existing RP bindings, templates, procedural messages, and contextual actions.

**Problem:** Some RP messages may use masculine Russian grammatical forms even when the player's character is female.

PA must properly support both male and female characters.

### Requirements

1. Inspect all existing RP templates, including:
   - Traffic stops.
   - ID and document checks.
   - Vehicle inspections.
   - Searches and arrests.
   - Handcuffing and escorting.
   - Wanted and fine procedures.
   - Radio interactions.
   - Medical or emergency interactions.
   - Other `/me`, `/do`, and related RP actions.

2. Implement consistent character-gender handling:
   - Male character → grammatically correct masculine forms.
   - Female character → grammatically correct feminine forms.
   - Unknown/unconfigured gender → safe, explicitly defined fallback.

3. Example:

   Male:
   `/me достал служебное удостоверение и предъявил его гражданину`

   Female:
   `/me достала служебное удостоверение и предъявила его гражданину`

4. Do not determine character gender from a nickname or the real user's identity.

5. Reuse an existing character/profile gender setting if available. Otherwise, provide an explicit setting with appropriate validation and persistence.

6. Where the target's gender affects a message, distinguish the officer's gender from the target's gender. Do not guess the target's gender.

7. All templates must remain editable through the existing Russian-language settings interface.

8. Preserve all user-customized templates. Do not overwrite personal RP text with updated author defaults.

9. Check gender handling after profile changes, imports, exports, fresh installations, and upgrades.

**Acceptance:** An officer using a female character must be able to perform all supported PA procedures without grammatically incorrect masculine RP narration.

Do not limit testing to a few sample bindings. Audit the complete existing template system.

## 2. CEF Chat — Fresh Installation Compatibility Bug

A real compatibility problem was reported on another player's computer running a **clean installation of PA v0.44.0**.

The computer belongs to a player using a female character.

Some Russian-to-English text conversion/transcription functionality and related chat features did not work correctly after the fresh installation.

This must be investigated as an actual user-reported compatibility defect.

### Required investigation

1. Compare a clean v0.44.0 installation with an existing working installation.
2. Check installation manifests, required resources, configuration defaults, initialization order, dependencies, file paths, and missing assets.
3. Verify which conversion functionality PA actually implements:
   - Russian-to-English keyboard-layout conversion, such as `руддщ` → `hello`.
   - Cyrillic-to-Latin transliteration, such as `Привет` → `Privet`.
   
   These are different operations. Do not confuse them or assume both are supported without checking the actual code and settings.
4. Test the existing advertised behavior with Russian and English keyboard layouts.
5. Verify compatibility with both native SA:MP chat and the Exsellent CEF chat where applicable.
6. Check encoding, CP1251 handling, keyboard shortcuts, input focus, configuration loading, and feature availability after a clean installation.
7. Verify that required settings are correctly initialized when no previous PA configuration exists.
8. Test fresh installation versus upgrading from an older version.
9. Verify that conversion does not accidentally modify text, send messages, or trigger commands.

### Critical preservation rule

The current CEF chat finally works smoothly on the main tested installation.

**Do not rewrite or broadly refactor the working CEF chat.**

First identify the actual cause of the reported defect.

If a CEF-related code change is genuinely required, make the smallest isolated correction possible and add regression tests.

Do not reintroduce:

- Typing lag.
- Text-selection freezes.
- Per-keystroke processing overhead.
- Unnecessary CEF polling.
- Input-focus problems.
- Duplicate messages.

Do not modify launcher or DLL files, bypass compatibility checks, or disable existing safeguards.

If the problem cannot be reproduced without access to the affected computer, document the diagnostic evidence and provide a precise manual reproduction checklist. Do not claim the compatibility issue is definitively fixed without verification.

## 3. Motorcycle-Specific RP Interactions

PA must distinguish between ordinary cars and motorcycles when generating vehicle-related RP actions.

**Existing problem:** Some vehicle-inspection RP text is appropriate for cars but becomes unrealistic when used on motorcycles.

For example, an officer should not describe shining a flashlight into a vehicle interior when inspecting a motorcycle.

### Requirements

1. Inspect existing vehicle classification and RP template selection.
2. Reuse the established vehicle identification system.
3. Provide appropriate RP variants for:
   - Passenger cars.
   - Motorcycles.
   - Other vehicle categories where the current RP text would otherwise be physically inappropriate.
4. Select the appropriate template based on a verified vehicle category.
5. Do not assume that motorcycles have a passenger compartment, ordinary doors, a trunk, or other car-specific structures.
6. Provide separate editable templates for applicable vehicle categories.
7. Use a neutral fallback when vehicle classification is unavailable.
8. Preserve user-customized templates and existing vehicle-related commands.

### Example

For a car, an inspection may involve illuminating the passenger compartment.

For a motorcycle, the RP interaction should instead describe a plausible inspection of the motorcycle, its visible components, identification markings, or other actually relevant details.

Do not fabricate physical actions or describe inspecting equipment that may not exist on the particular vehicle.

**Acceptance:** Motorcycle interactions must never automatically use inappropriate passenger-car RP text.

## 4. ESC Key — Proper PA Window Closing Behavior

Implement natural ESC-key behavior for PA windows.

### Required interaction

**Scenario A — F4 is open:**

1. The player presses ESC.
2. PA closes F4.
3. GTA's pause menu does not open from that same keypress.
4. The player presses ESC again.
5. GTA opens its normal pause menu.

**Scenario B — F9 is open:**

The same behavior applies to F9.

**Scenario C — Multiple PA windows or overlays are active:**

Apply a consistent closing policy that safely dismisses the active PA window state without leaving invisible input-capturing overlays.

### Additional rules

- Do not let a single ESC press both close PA and open GTA's menu.
- Do not require the player to press F4/F9 again just to close the interface.
- Do not interfere with ESC inside native chat, CEF chat, GTA dialogs, or existing modal interactions.
- Do not break normal GTA pause-menu behavior when no PA window is active.
- Do not intercept ESC while the ordinary GTA pause map is already open unless PA has an explicitly active window that legitimately owns the input.
- Prevent key-repeat and key-hold from triggering two actions.
- Preserve focus restoration and avoid leaving mouse or keyboard input captured.
- Use existing UI/input ownership mechanisms wherever possible.

**Acceptance:** First ESC closes the active PA interface; the next separate ESC press opens GTA's normal menu.

This must work reliably for F4 and F9 without disrupting chat input.

## 5. Comprehensive Review of the Police Manual and Radio Procedures

Perform a thorough review of the available local PA manual, police knowledge database, authoritative source registry, operational procedures, and existing radio templates.

The objective is to expand PA's practical radio-reporting assistance using **verified Exsellent RP procedures and ten-codes**.

Do not invent radio codes, server rules, departmental procedures, permissions, or mandatory wording.

Use authoritative existing sources and distinguish verified rules from editable user-created templates.

Do not copy incorrect or outdated radio codes from competing assistants.

### Required result

Create a coherent set of practical, contextual radio-report templates for common police situations.

Each scenario should have relevant reporting stages rather than one generic message.

Radio messages must be:

- Grammatically correct in Russian.
- Appropriate to the current faction and situation.
- Editable in PA settings.
- Previewable before transmission.
- Compatible with the existing command executor.
- Respectful of command-length and encoding limits.
- Protected against accidental, duplicate, or automatic sending.

Only use a ten-code when its meaning and applicability have been verified.

## 6. Gas Station Robbery — Dedicated Response Workflow

Add a dedicated response workflow for gas station robberies.

This should be a practical operational assistant, not an autonomous RP bot.

### Suggested stages

**Stage 1 — Responding / En Route**

The officer receives or selects a verified gas station robbery incident and explicitly reports that the unit is responding.

**Stage 2 — Arrival at the Scene**

The officer reaches the location and can explicitly report arrival.

**Stage 3 — Situation Assessment**

Provide relevant optional reporting actions, such as:

- Situation being assessed.
- Area being secured.
- Additional units requested.
- Suspect observed.
- Suspect fleeing.
- Pursuit initiated, if applicable.

**Stage 4 — Resolution**

Provide appropriate manual actions for reporting the conclusion or requesting further assistance.

### Important restrictions

- Do not automatically claim that the officer has arrived based solely on proximity unless an appropriate confirmation mechanism is provided.
- Do not invent suspect numbers, identities, weapons, casualties, or incident outcomes.
- Do not send radio messages automatically.
- Do not assume that every robbery follows the same sequence.
- Do not advance to an irreversible stage without explicit officer action.
- Never invent official radio codes or server-specific rules.

Use existing location, patrol, incident, and radio variables only when verified.

## 7. Redesign the Incident Reporting Controls

The current UI sometimes places a repetitive **"report about this call"** action beneath individual incident buttons.

This is visually repetitive and makes operational workflows less convenient.

Redesign this part of the interface.

### Desired UX

Separate:

1. **Incident selection** — What happened?
2. **Response stage** — What is the officer doing now?
3. **Radio action** — What should be reported?
4. **Completion or cancellation** — Has the incident ended?

For example, a compact response section might provide:

- `Выехал`
- `Прибыл`
- `Нужна помощь`
- `Преследование`
- `Завершил`

These are conceptual action labels, not a requirement to add all five buttons to every incident.

Design context-sensitive controls that display only relevant actions.

### Visual requirements

- Keep F4 compact and operational.
- Place advanced template editing in F9.
- Avoid repeating identical reporting buttons under every incident.
- Use consistent Font Awesome icons and existing PA visual styling.
- Maintain responsive layouts at supported resolutions.
- Show the currently selected incident and response stage clearly.
- Do not create additional mandatory windows or unnecessary confirmation layers.
- Preserve existing incident actions and personal templates.

The final interface should look integrated into the established v0.44.0 design, not like a separate plugin.

## 8. `/setmark` — Suspect Search and Radio Reporting

Extend the existing `/setmark` workflow with appropriate officer-controlled RP and radio-reporting support.

### Desired scenario

An officer has a legitimate, verified reason to locate a suspect.

The officer prepares the required RP interaction and uses `/setmark` according to the actual server rules.

PA should then provide appropriate optional radio-reporting actions for the subsequent search.

### Suggested reporting stages

- Search initiated.
- Unit responding toward the last known or indicated location.
- Unit arrived in the search area.
- Search continuing.
- Additional assistance requested.
- Suspect located, when explicitly confirmed.
- Search concluded or cancelled.

### Mandatory restrictions

- Do not automatically equate receiving a wanted bulletin with having sufficient IC grounds for satellite tracking.
- Do not skip mandatory RP preparation.
- Do not automatically send `/setmark`.
- Verify that the RP text and server command refer to the same intended suspect.
- Revalidate player identity before consequential actions.
- Do not announce that a suspect has been located merely because a marker or coordinate exists.
- Distinguish an approximate search area from an actually observed suspect.
- Do not fabricate verified server mechanics.

Integrate these actions with the existing pursuit, wanted, and incident-reporting systems.

Do not create a disconnected duplicate workflow.

## 9. Colleague Assistance Signals and `/ml` Scenarios

Analyze how colleague assistance requests and the `/ml` command actually work on Exsellent RP.

Do not assume the exact meaning, syntax, or server behavior of `/ml` without verifying it.

### Required functionality

Where supported by verified server evidence, provide contextual responses to colleague assistance signals.

Possible officer-controlled reporting stages:

1. Assistance request received.
2. Officer responding to the colleague.
3. Officer en route.
4. Officer arrived at the relevant location.
5. Officer assisting at the scene.
6. Additional units requested.
7. Assistance completed or cancelled.

The actual available stages must depend on confirmed server mechanics.

### Integration

- Reuse the existing message observer and notification system.
- Do not add another global keyboard-confirmation handler.
- Do not automatically treat untrusted chat text as a genuine colleague request.
- Validate identities and session state when relevant.
- Do not automatically navigate, transmit radio messages, or initiate RP sequences.
- Respect the existing Copilot and patrol notification priorities.
- Support appropriate radio templates using verified ten-codes.

If `/ml` cannot be reliably observed or its contract is unknown, provide only safe, manually initiated functionality and report the limitation.

## 10. Broader Radio Scenario Audit

In addition to gas station robberies, suspect searches, and colleague assistance, examine existing police workflows and identify other situations where meaningful radio reports are missing.

Prioritize scenarios already supported by PA, such as:

- Traffic stops.
- High-risk stops.
- Active pursuits.
- Suspect searches.
- Requests for backup.
- Arrival at incidents.
- Changes in incident status.
- Incident completion.
- Relevant patrol events.

Do not add unnecessary radio messages simply to increase the number of templates.

Each new action must have a clear operational purpose.

Where suitable, support variables such as:

- Unit or callsign.
- Department.
- Selected incident.
- Current area.
- Relevant target.
- Response stage.

Every variable must be validated, and unknown information must not be invented.

## 11. RP and Radio Template Configuration

All new RP and radio features must remain customizable.

Provide appropriate Russian-language settings for:

- Male and female character variants.
- Vehicle-specific interactions.
- Radio templates.
- Incident-specific messages.
- Applicable ten-codes.
- Response stages.
- Optional delays and confirmation requirements.
- Relevant shortcuts.

Support accurate final-message previews.

Respect CP1251 encoding, server-command length restrictions, current user profiles, and existing persistence rules.

Do not overwrite previously customized messages during migration.

Do not introduce a second independent template database if the existing PA architecture can support these features.

## 12. Tests and Acceptance

Add focused automated tests for each new or corrected subsystem.

### Required test coverage

**Gender-aware RP**

- Male character.
- Female character.
- Unknown gender.
- Profile changes.
- Custom template overrides.
- Relevant grammatical forms.

**CEF compatibility**

- Clean installation.
- Upgrade installation.
- Missing or invalid configuration.
- Russian and English keyboard layouts.
- All actually supported layout-conversion/transliteration features.
- Native chat and CEF chat where applicable.
- Typing and selection performance.
- No duplicate or unintended messages.

**Vehicle RP**

- Passenger car.
- Motorcycle.
- Unsupported or unknown vehicle.
- Vehicle switching during an active procedure.
- User-customized vehicle templates.

**ESC behavior**

- F4 open.
- F9 open.
- Both interfaces or relevant overlays active.
- No PA interface open.
- Native chat active.
- CEF chat active.
- GTA dialog active.
- Key held or repeated.
- Focus loss and restoration.

**Radio workflows**

- Gas station robbery response.
- Arrival reporting.
- Backup requests.
- `/setmark` suspect-search reports.
- Colleague assistance and verified `/ml` behavior.
- Cancellation and interrupted workflows.
- Missing target, location, or callsign.
- Invalid or stale session context.
- Duplicate message prevention.
- User-customized templates and exact previews.

Record real test outcomes. Mark scenarios requiring GTA or the affected user's computer as `NOT RUN` until they have actually been verified.

## 13. Final Instructions

Treat these requirements as mandatory additions to the v0.45.0 development scope.

Prioritize the work as follows:

**P0 — Compatibility and correctness**

1. Investigate the reported clean-install CEF conversion defect.
2. Audit and correct female-character RP handling.
3. Implement reliable ESC window dismissal.
4. Correct inappropriate motorcycle RP behavior.
5. Preserve all v0.44.0 functionality and user data.

**P1 — Operational functionality**

6. Redesign incident-reporting controls.
7. Add gas station robbery response reporting.
8. Integrate `/setmark` search-stage radio reporting.
9. Implement verified colleague-assistance workflows.
10. Expand useful radio reports based on the actual police manual.

**P2 — Polish**

11. Improve grouping, labels, icons, responsive layouts, and usability without adding unnecessary interface complexity.

These priorities apply to the additional work described here. They do not replace the core v0.45.0 GPS acceptance requirements.

Continue working incrementally and run regression tests after each major change.

Maintain the existing restriction against GitHub operations, GTA installation, publication, and modification of live user data.

**The objective is not merely to add more buttons. It is to make Police Assistant genuinely useful during real police roleplay, with accurate contextual actions, natural Russian RP narration, and an interface that remains fast and convenient during gameplay.**

Please implement these requirements as part of the local Police Assistant 2026 v0.45.0 development effort.