# Police Assistant 2026 v0.45.0 — Final All-in-One GPS Integration, Compatibility Fixes and Release Preparation

Proceed with the final local development and stabilization stage of Police Assistant 2026 v0.45.0.

**My decision is final: PA v0.45.0 must be distributed as a complete All-in-One package with its own road-graph data.**

I confirm that the provided `roads.bin` may be included in the Police Assistant distribution packages.

The goal is to deliver a self-contained release candidate that users can install on supported GTA San Andreas / SA:MP builds without separately downloading, locating, or copying launcher GPS files.

All previously approved requirements, safety restrictions, preservation guarantees, and review findings remain applicable.

## 1. Mandatory All-in-One GPS Packaging

Include the provided `roads.bin` directly in the PA distribution.

Use this PA-owned location:

`moonloader/resource/pa26/roads.bin`

The file must be present after a standard clean installation.

Reference file information:

- Format: LGPS v1.
- Size: 589,664 bytes.
- Nodes: 28,991.
- Edges: 29,810.
- SHA-256: `c1d347286ccb0349940800570078c6872bef31c12ac6d6f77a4b1cf8b857d7db`

Verify the supplied file against this hash before packaging.

Do not alter the original graph data unless a separate transformation is genuinely necessary, documented, and independently verified.

### Required packages

Include the verified road graph in:

1. The normal PA installation ZIP.
2. The PA update ZIP.
3. The complete source distribution, where the bundled runtime resources are represented.
4. Relevant installation and update manifests.
5. SHA-256 integrity and packaging checks.

**The user must not need to copy `roads.bin` manually.**

A fresh installation must contain everything PA requires for its independent road-navigation backend.

The installer must automatically place the graph at the correct PA-owned location.

The updater must handle this new PA-owned resource without changing the frozen update-platform implementation.

Do not include `ExsellentGps.asi`.

Retain a clear provenance/license notice for the bundled data where applicable.

## 2. Make PA GPS Independent of the Launcher

The Lua GPS implementation must operate without:

- `ExsellentGps.asi`.
- Launcher-specific GPS hooks.
- Launcher RakNet interception.
- The launcher's native route-rendering implementation.
- Unsafe memory patches.
- Unverified GTA `CPathFind` calls.

Continue using the established independent PA components:

- `pa26_navigation_roads.lua`
- `pa26_navigation.lua`
- `pa26_navigation_render.lua`

The supplied road graph is a data dependency, not an executable dependency.

Do not copy or execute the launcher ASI.

The normal PA installation must be sufficient for road-graph discovery and route calculation on supported standalone builds.

## 3. Correct Road-Graph Discovery and Priority

Update the existing `openRoads` implementation.

The current hard-coded path to `exsellent/gps/roads.bin` is no longer appropriate as the primary source.

Use the following deterministic priority:

1. Verified PA-bundled graph: `moonloader/resource/pa26/roads.bin`.
2. Compatible external graph explicitly selected by the user.
3. Existing launcher graph: `<GTA root>/exsellent/gps/roads.bin`.
4. Existing legacy graph: `<GTA root>/legacy/gps/roads.bin`.

The bundled PA graph must work by default without any configuration.

External paths remain optional compatibility fallbacks.

Resolve paths from verified installation directories, not untrusted working-directory assumptions.

Do not recursively scan unrelated directories.

Do not modify launcher files.

When a candidate graph is found, validate its format, size, structure, and supported version.

An invalid graph must be rejected safely. Continue to another permitted candidate when appropriate.

Preserve user-selected custom graphs separately from package-managed data. Upgrades must not silently overwrite unrelated user data.

## 4. GPS Compatibility With Different Installations

Support two principal operating environments.

### A. Exsellent Launcher Installation

PA uses its own bundled graph and independent route renderer.

The existing launcher GPS may also be running.

Ensure safe coexistence:

- Avoid duplicate navigation lines where possible.
- Keep separate radar and pause-map overlay controls.
- Do not fight the launcher for ownership of native waypoints.
- Do not introduce additional RakNet or D3D9 hooks.
- Do not patch `ExsellentGps.asi`.
- Preserve existing game and launcher files.
- Prevent repeated or unnecessary route calculations.

The existing PA destination-retention feature must remain available.

However, clearly distinguish retaining PA's last observed destination from restoring the native GTA red waypoint. These are not the same operation.

### B. Standalone GTA San Andreas / SA:MP Installation

PA must work using its bundled graph even when no launcher GPS files exist.

Verify compatibility with the actual supported runtime:

- GTA executable/build.
- MoonLoader.
- SA:MP APIs.
- Required PA dependencies.
- Map-projection signatures.
- mimgui rendering.

Do not assume universal compatibility with every modified GTA executable.

Unsupported builds must fail safely with understandable diagnostics.

The packaged graph must not depend on launcher directory structures.

### C. Missing or Corrupted Bundled Graph

If the installed resource is missing or corrupted:

- PA must continue starting normally.
- Other PA features must remain functional.
- Navigation must show a clear diagnostic.
- Unsafe route processing must not begin.
- An existing valid external graph may be used as a supported fallback.

Do not automatically download unknown files or silently patch the launcher.

## 5. Preserve the Primary GTA Waypoint Experience

The main navigation requirement remains unchanged.

The player must:

1. Open GTA's ordinary Esc → Map.
2. Place a standard GTA waypoint.
3. Have PA detect that waypoint.
4. See a road-following route directly over the still-open pause map.
5. Return to gameplay and see the corresponding route on the radar.

Moving or removing the waypoint must update the relevant PA navigation state correctly.

PA must not:

- Implement its own LMB/RMB map-click system.
- Simulate user mouse clicks.
- Replace GTA's waypoint controls.
- Delete the native marker as part of normal route calculation.

Use the established PA projection and clipping logic.

Keep navigation independent of the map-grid visibility setting.

**Do not report this requirement as complete until it has been verified in the actual game.**

## 6. Improve GPS Loading and Responsiveness

The current offline benchmarks show that cold graph preparation can require more than 400 processing slices.

At one slice per frame, the initial visible route may be delayed by several seconds.

Improve this experience.

### Requirements

- Prepare the bundled graph incrementally when navigation is enabled.
- Cache the validated graph for the current session.
- Avoid reparsing it for every waypoint.
- Separate graph loading from route search.
- Keep expensive work out of rendering and chat-input callbacks.
- Preserve bounded CPU budgets and memory limits.
- Cancel outdated searches immediately when the destination changes.
- Reuse prepared world geometry when only zoom or map position changes.
- Show an understandable loading status rather than appearing broken.

Measure and report:

- Initial graph-loading duration.
- First-route latency.
- Subsequent-route latency.
- Worst processing slice.
- Frame-time impact in GTA when measurable.
- Time from native waypoint placement to visible route.

Do not present offline CPU time as real in-game latency.

Do not sacrifice CEF responsiveness or gameplay smoothness for faster GPS calculation.

## 7. GPS Status and Settings

Improve the existing Russian-language navigation settings without introducing unnecessary new windows.

Display:

- `Дорожный GPS: доступен / недоступен`
- Graph source.
- Graph validation status.
- Loading progress.
- Current destination source.
- Road-route availability.
- Appropriate error information.

Users must not need to understand Lua paths or binary graph formats.

Preserve the existing navigation controls:

- Main feature switch.
- Native waypoint observation.
- Route overlay.
- Radar display.
- Pause-map display.
- Experimental routing settings.
- Destination retention.
- Route reset.
- Source arbitration.

The new bundled graph should be discovered automatically.

Keep potentially invasive or unverified behavior disabled by default.

## 8. Correct All Confirmed v0.45.0 Defects

Before preparing release artifacts, address the findings from the previous independent review.

### A. Complete Female RP Grammar Support

The current exact-template gender catalog contains incomplete conversions.

Some messages change one masculine verb while leaving other masculine verbs unchanged.

Audit every stock RP conversion and ensure all relevant verbs are correct for female characters.

Test complete rendered Russian sentences.

Preserve personal customized templates.

Support explicit gender variants in user text.

### B. Mandatory `/setmark` RP

Preserve and verify centralized mandatory RP enforcement.

Every PA-controlled entry point must follow:

**Explicit officer action → mandatory RP preparation → `/setmark ID`.**

This includes buttons, radial wheel, standard bindings, custom bindings, imported bindings, favorites, shortcuts, and supported manual command handlers.

No RP-less bypass.

No additional IC-justification, wanted-bulletin, or phone-number requirement.

Maintain target identity checks, cancellation, configured delays, and duplicate-preparation prevention.

### C. CEF Chat Compatibility

Investigate the reported clean-install Russian/English conversion problem.

The current launcher CEF hash differs from the previously verified contract.

Do not bypass hash validation.

Do not blindly approve a new launcher version.

Preserve the existing stable CEF chat implementation and input responsiveness.

Any necessary fix must be isolated, reproducible, and regression-tested.

Do not modify launcher DLL or `main.js`.

### D. Existing v0.45.0 Improvements

Preserve and verify:

- ESC closing F4/F9 before opening GTA's pause menu.
- Motorcycle-specific RP interactions.
- Gas station robbery response stages.
- Suspect-search radio reports.
- Colleague assistance workflows.
- Compact nearby selection.
- Pinned notes.
- Favorites ordering.
- Existing patrol, pursuit, Copilot, and radio behavior.

Do not remove established functionality to simplify the new release.

## 9. Installer and Updater Requirements

The bundled road graph must be treated as an official PA-owned runtime resource.

Update:

- Installation manifests.
- Update manifests.
- Relevant resource inventories.
- File-integrity checks.
- Packaging scripts.
- Installation documentation.

Test:

1. Fresh standalone installation.
2. Fresh Exsellent launcher installation.
3. Upgrade from v0.44.0.
4. Interrupted installation and rollback.
5. Missing or corrupted graph.
6. Existing user settings and personal data.
7. Correct graph availability after an update.

Do not overwrite profiles, user bindings, personal RP templates, contacts, notes, wheel layouts, or saved geometry.

Preserve existing atomic-save and backup mechanisms.

Keep `pa26_update_platform.lua` byte-for-byte unchanged with its protected SHA-256:

`995b131aa0250b7ea407915ad7d109de71a8e43cec088603bc99cc489e60565f`

The final package must contain the verified graph exactly once at its intended runtime location.

Avoid conflicting duplicate graph copies under different active paths.

## 10. Mandatory Verification

Run the complete available regression suite.

Add specific automated checks confirming:

- `roads.bin` is included in all required artifacts.
- Its packaged SHA-256 matches the verified source.
- Clean installation places it correctly.
- The runtime can discover it without launcher files.
- The graph loads successfully.
- A valid road route can be calculated.
- Corrupted files fail safely.
- External fallback paths behave correctly.
- Existing user files survive installation and update.
- CEF and protected components remain unchanged unless a separately verified fix is required.
- Mandatory `/setmark` RP cannot be bypassed.
- Female-character templates are grammatically correct.

Run bounded graph benchmarks and repeat the existing performance comparisons.

Mark real GTA scenarios `NOT RUN` until tested.

Required manual acceptance scenarios include:

- Launcher installed, launcher GPS active.
- Standalone build without launcher GPS.
- Missing and invalid graph.
- Native waypoint on the open Esc map.
- Radar route.
- Waypoint movement and removal.
- Long-distance routing.
- Repeated destination changes.
- Map zoom and pan.
- Chat input while a route is being calculated.
- Real FPS and frame-time comparison.
- All relevant regression scenarios from v0.44.0.

Never substitute synthetic test results for actual gameplay verification.

## 11. Final All-in-One Release Deliverables

Prepare the following local artifacts:

1. `Police-Assistant-v0.45.0.zip`
   - Complete PA installation.
   - All required PA runtime files.
   - Bundled `roads.bin`.
   - No dependency on `ExsellentGps.asi`.

2. `pa26-update.zip`
   - Correct updated PA modules.
   - Bundled road graph.
   - Compatible update manifests.
   - Protected-user-data behavior.

3. `Police-Assistant-v0.45.0-source.zip`
   - Complete corresponding source.
   - Required runtime resources.
   - Relevant tests and documentation.

4. `SHA256SUMS.txt`
   - Verified checksums for the release artifacts.

5. Updated documentation:
   - Installation guide.
   - Upgrade guide.
   - GPS compatibility notes.
   - Release notes.
   - Known limitations.
   - Manual acceptance checklist.

6. Final verification report:
   - Implemented features.
   - Changed files.
   - Automated test results.
   - Preservation results.
   - Performance measurements.
   - Remaining `NOT RUN` and `BLOCKED` scenarios.

Verify archive integrity and ensure that installation payloads match the tested source.

No personal user data may be included in public release archives.

## 12. Deployment Restrictions and Final Objective

**Do not push or publish anything to GitHub automatically.**

**Do not install into my active GTA installation.**

Prepare the final files so that I can review them, install the candidate for testing, and publish the release myself.

The final goal is:

**One download. One installation. A complete Police Assistant with its own road-graph data and independent GPS backend.**

No external GPS plugin.

No manual `roads.bin` copying.

No required Exsellent launcher.

No unsafe native routing calls.

No unnecessary CEF modifications.

No loss of existing v0.44.0 features or user data.

Compatibility must be verified on each supported game/runtime configuration, rather than assumed.

If an important live-game acceptance item cannot be tested in your environment, document it honestly and provide exact reproduction steps.

**Proceed with the local implementation, correct the identified defects, package the bundled road graph, run all available tests, and deliver the complete All-in-One v0.45.0 release candidate for my final review.**