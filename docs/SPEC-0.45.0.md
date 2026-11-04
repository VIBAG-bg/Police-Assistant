# CODEX IMPLEMENTATION SPECIFICATION — Police Assistant 2026 v0.45.0

## Native GTA Waypoint Road Navigation, Smart OOC Coordinates, Cruiser Assistance, Pinned Notes, Leadership Studio, and Compact Nearby Targets

**Project:** Police Assistant 2026 for SA:MP / Exsellent RP  
**Target release:** `0.43.5` (or the next unused version after confirming the actual repository version)  
**Reference baseline reviewed:** PA `0.43.2` source archive; subsequent `0.43.3` CEF fixes and `0.43.4` UX/icon work must be preserved if present in the working tree.  
**Status:** Implementation request, **not** proof that any feature is already operational in GTA.  
**Scope:** PD/EPD, FBI, and Prison Alcatraz; do not implement unrelated mafia, medical, news-agency or licensing systems.

> **Primary product rule:** When the player opens **Esc → Map** and places an **ordinary native GTA San Andreas user waypoint** with the game's normal map controls, PA detects that waypoint and draws a road-following route **directly over the still-open pause map**, then shows the same route on the gameplay radar. PA must **not** implement its own LMB/RMB map-click logic, inject clicks, simulate native waypoint controls, or replace the native user waypoint. This is the user's final, explicit choice and overrides earlier drafts.

### Required working method

1. Inspect the **actual current repository** before editing. Do not assume that `0.43.2` remains HEAD, that `0.43.3` CEF changes have landed, or that proposed `0.43.4` UI icons have shipped. Produce a short inventory of relevant existing modules and current integration points.
2. Reuse established settings, confirmation, command execution, data models, layout, profile persistence, event observation, and test infrastructure. Do not build parallel copies of working PA subsystems.
3. Implement in independently testable stages. Run regression tests after each stage. Avoid an enormous single unreviewed diff.
4. Preserve backward compatibility. Existing personal profiles, binds, radio templates, wheel layouts, notes, presets, contacts, knowledge edits, keys and sizing must survive **both** fresh installation and upgrade from older versions.
5. Do **not** install into the user's GTA, publish to GitHub, create a release, or modify live user configuration without a separate authorization.
6. PA remains a **context-aware officer's assistant, not a blind multi-step RP binder**. All consequential commands require an explicit officer action and the normal executor/preflight policy.

---

## 0. Hard safety and preservation gates (P0)

### 0.1. Frozen update platform

- `moonloader/lib/pa26_update_platform.lua` must stay **byte-identical**.
- Expected SHA-256 for the supplied `0.43.2` reference file: `995b131aa0250b7ea407915ad7d109de71a8e43cec088603bc99cc489e60565f`.
- Verify this hash on the current baseline; if the active working tree legitimately differs, report the discrepancy and avoid overwriting it. Never forcibly restore old files to satisfy the hash.
- Preserve existing update/install manifests and protected-user-data policies. Extend file lists only for PA-owned new modules after running packaging tests.

### 0.2. Preserve critical existing systems

- The `0.43.3` CEF chat input/selection latency fixes, including any later corrections. Never add per-keystroke, per-selection, per-mousemove or per-frame CEF input inspection for these new features.
- Existing `10-55` / `10-66` / `10-57` / completion logic, manual `/ud` observation, target identity checks, fine/wanted article selection, stolen-bulletin expiry, current radio templates and trusted knowledge database.
- Existing map grid, map projection, radar clipping, pause-map clipping, map-sector labels and bulletin-zone highlighting.
- Existing `pa26_nearby.lua` and the validated target selection mechanism.
- Existing F4/F9 architecture and any `0.43.4` redesign. New controls must feel like native members of PA, not bolt-on windows.

### 0.3. Correct architectural assumptions about the current code

The reference `0.43.2` code **does** perform a guarded map projection read from an `imgui.OnFrame` map callback using `sceneServices.mapAdapter:safeView(...)`. Do not incorrectly assert that all game-memory reads are already isolated into `main()`.

- New world observation, waypoint polling, route decisions, pathfinder calls and vehicle control mutations should occur in a bounded service update, not in UI widget callbacks.
- `mimgui` should draw **prepared, immutable route/view snapshots**, not initiate pathfinding or write game state.
- Preserve the existing verified map projection behavior. If moving its guarded read out of `OnFrame`, demonstrate that the pause-map transform is still captured at the correct point of the frame; the GTA front-end map transform can be transient.
- Render-specific bindings may execute in their required rendering callback. Never impose an impossible blanket ban on graphics calls; distinguish read-only snapshot preparation, drawing, and game mutations.
- Make all new services disposable/restartable and ensure cleanup on unload, reload, disconnection and game-session transitions.

### 0.4. No unsupported claims

- Synthetic/unit tests and 32-bit LuaJIT/mimgui simulations cannot establish the actual behavior of the Exsellent launcher, mouse, pause menu, game memory or FPS.
- Do not claim that `pcall()` makes FFI/native calls crash-proof.
- Do not invent official radio codes, penalties, rank permissions, `/gnews` syntax, RP timing rules or GTA API signatures. Verify against the current PA knowledge/source registry and supported in-game behavior. Mark unverified behavior as such.

### 0.5. Release-blocking performance and reliability contract (NEW, mandatory)

**The `0.43.3` CEF incident is the cautionary baseline.** A feature that passes correctness tests but makes typing, mouse selection, driving, map movement or aiming visibly less responsive is **not complete**. Do not solve a performance problem merely by making a polling loop less frequent; remove unnecessary work from hot paths.

**Before writing code:**

1. Establish the actual baseline by inspecting the current `0.43.3`/`0.43.4` code, CEF performance instrumentation, existing tick frequencies and native map readers. List every proposed new per-frame callback, timer, observer, FFI call, HTTP exchange, DOM operation and allocation; specify its trigger, maximum frequency and cleanup owner. Review the list before implementation.
2. Take reproducible *before* measurements wherever an executable test host exists. Do not invent an in-game baseline when GTA is unavailable. Keep the 0.43.3 chat adapter and its input/selection event paths unchanged unless there is a separately reproduced defect.
3. Use event-driven updates and immutable snapshots. No new CEF `input`, `selectionchange`, `mousemove`, `MutationObserver` on chat history, document-wide style scan, or per-keystroke HTTP/IPC. No new filesystem checks or policy reserialization from a typing handler.
4. No new unbounded loops, `wait()`/sleep in the main/render callback, growing event queues, repeated font loads, on-frame file reads, full-user-data scans, dynamic native memory allocations or per-frame rebuild of unchanged route geometry. Every cache and queue needs explicit size/TTL limits and invalidation rules.
5. Render callbacks draw prepared geometry; world polling, command emission, native pointer inspection and cruise-control decisions remain in their safe integration phase. If a graphics API specifically requires rendering-phase execution, pass validated immutable geometry to that phase, make the call bounded and document the exception.
6. No assumption that coroutine, Lua thread or `pcall()` makes an unsafe native path search asynchronous or crash-safe. A synchronous native call can block GTA's main thread and an access violation can terminate the process. Validate ABI/build first; refuse to activate without evidence.
7. Add a **single master switch** for the new 0.43.5 services, plus independently disableable navigation native pathfinding, route overlay, coordinate auto-observation, cruiser control, hazard rendering and pinned notes. Default to safe/non-invasive behavior. Turning a feature off must immediately stop its callbacks, inputs, vehicle key injection, temporary markers and expensive work; the rest of PA must continue.

**Measurement and release gates:**

- Profile with the existing opt-in `pa26_chat_perf` facilities or an equally lightweight monotonic-clock profiler. Record separate buckets for navigation observation, native pathfinding, route simplification/projection/draw, coordinate parsing, cruiser loop, marker cleanup, pinned-note rendering and UI. Sampling must be disabled by default, bounded, and contain no chat text, personal note contents, player identities, tokens, phone numbers or precise shared coordinates.
- Compare **the same warmed-up scene** with the last released PA and the candidate (ideally also PA disabled). Test at least three comparable runs per scenario; record FPS, frame-time p50/p95/p99, frames over 33 ms, worst relevant stall, memory growth and event/request counts. Describe hardware, FPS cap, resolution, route length, HUD/CEF state and sample duration. Do not pretend unrelated frame-time variance proves the new code caused or did not cause a spike.
- **Engineering targets (not automatically established facts):** with all 0.43.5 options disabled, overhead should be statistically indistinguishable from the baseline; with route and normal overlays active, aim for under **1 ms added p95 frame time** in matched steady-state play, no repeated correlated 33+ ms frame spikes and no perceptible CEF input/selection regression. If a target cannot be measured, mark it `NOT RUN`, not `PASS`. If it fails reproducibly, optimize or keep the responsible optional feature disabled for release.
- Path-search scheduling is **single-flight, coalesced and backoff-protected**. Measure each actual native call. If a verified call repeatedly produces unacceptable stalls, automatically suspend the native routing mode for the session with a clear reason; do not keep retrying in pursuit or while typing. A watchdog cannot interrupt a hung native call, so never claim this protects against all stalls/crashes.
- At 60 FPS, one frame is about 16.7 ms; sustained extra work in a frame-sensitive callback must be much smaller. Keep idle-service work near-zero, cap rendering segments and native calls, and instrument worst-case 2,000-node routes rather than measuring only short/empty routes.
- **Acceptance is two-layered:** machine/unit/native-simulation tests first, then real GTA/Exsellent acceptance by a human. A technically coherent but untested native GPS implementation may be delivered behind an **OFF** feature flag, not silently enabled and declared stable. The ordinary native waypoint + route-over-open-Esc-map requirement remains an unfulfilled acceptance item until observed in the actual client.

**Fault policy:** A malformed chat line, invalid saved note, absent SA:MP API, incompatible GTA executable, interrupted reconnect, stale target, missing font or failing native module may disable **only its affected feature** and show a concise diagnostic. None may send an unintended command, corrupt user state, leave the accelerator held, delete the user's native waypoint, block the CEF editor or crash other PA modules through an uncaught Lua exception. Distinguish Lua exceptions that can be caught from native faults that require opt-in/build gating.

---

## 1. Native GTA waypoint navigation (P0 / core feature)

**Suggested modules:** `pa26_navigation.lua` (state/source/priority), `pa26_navigation_world.lua` (native observations/actions), `pa26_navigation_path.lua` (optional road graph), `pa26_navigation_render.lua` (geometry preparation), plus minimal integrations in `pa26_map_adapter.lua`, `pa26_map_grid.lua`, `pa26_map_ui.lua`, HUD and main services. Names may vary if a simpler composition fits the codebase.

### 1.1. Exclusive user interaction: existing GTA Esc-map waypoint

1. A player opens **Esc → Map** and uses **GTA's own standard mouse control** to create, move or remove the game's user waypoint.
2. PA observes the native user-waypoint coordinates through the supported API (possibly `getTargetBlipCoordinates()` **after verifying its actual return-value signature in the installed MoonLoader/runtime**).
3. Creating or moving the user waypoint changes PA's active navigation destination. Changes within a small coordinate tolerance must not cause unnecessary redraws/path searches.
4. Removing the user waypoint clears the corresponding route. It must not delete unrelated marks or server checkpoints.
5. While the pause-map is still open, PA calculates and draws the road-following route directly over that map **without requiring Esc to close**.
6. On returning to normal gameplay, the route remains visible on the radar. Reopening Esc → Map shows the same route.
7. PA does **not** handle LMB/RMB map-click gestures, measure click durations, convert mouse clicks into a custom waypoint, consume GTA's mouse input, call `placeWaypoint` in response to map mouse clicks, or simulate the native user action.
8. PA does not change the existing way the player places a red waypoint. This must remain true for all keyboard/mouse layouts and clients.

**Acceptance scenario:** open Esc → Map, place an ordinary GTA user waypoint, observe a correctly projected road-route overlay while Esc stays open; move the waypoint and see the updated route; remove the waypoint and see the overlay disappear. Record this as **requires in-game verification**, even if all unit tests pass.

### 1.2. Robust native waypoint observation

- Inspect the real MoonLoader function's return tuple, including whether it returns a success boolean, 2D/3D coordinates or a different absent-state convention. Do not assume `(0,0,0)` always means no waypoint: `(0,0)` is a valid GTA world position.
- Treat a brief missing or unstable waypoint read as **unknown**, not immediate proof of removal. Use a bounded grace period/debounce, with fast reaction to a confirmed deliberate removal.
- Track observation timestamp, game/session generation, source type, last accepted coordinates, update serial and current destination intent.
- Validate finite coordinates and GTA world bounds; reject NaNs, infinities, malformed results, interior-only destinations and stale session data.
- If native waypoint polling cannot reliably detect changes while Esc is open, investigate a **read-only, version-verified native fallback**. Do not inject mouse actions or silently present an inaccurate result.
- Preserve the native GTA red marker. Arrival may complete PA navigation, but **must not remove the native waypoint by default**. A separate opt-in auto-clear setting may be offered only if supported safely.

### 1.3. Route source arbitration

Track multiple route **sources**, but show only one primary route unless the user explicitly selects otherwise:

| Source | Creation | Default behavior |
| --- | --- | --- |
| `waypoint` | Native GTA user waypoint in Esc map | Highest normal priority and **primary** user experience |
| `mark` | Explicitly accepted incoming OOC coordinates / manual coordinate input | Explicit acceptance may temporarily override current route; do not delete native waypoint; show a clear source label |
| `server` | Server set/race checkpoint observed via SA:MP events | Follow when no higher-priority user destination exists; never silently take over an explicit user route |
| `bulletin` | User requests route to approximate stolen-vehicle district | Only on click and confirmation; clearly mark **approximate area**, not the vehicle's exact location |

When a temporary `mark` expires or is cleared, restore a still-valid previous native waypoint route if appropriate. Do not accidentally clear or rewrite server-owned checkpoints. The `[ Сбросить маршрут ]` PA control stops PA guidance without silently deleting the GTA user waypoint; if that waypoint remains active, avoid instantly reactivating guidance until its coordinates change or the officer explicitly resumes it.

### 1.4. Pause-map rendering and lifecycle

- Reuse the verified `pa26_map_adapter` map view for GTA SA 1.0 US. Existing view calculations use the verified front-end map page `0xBA68A5 == 5`, its zoom/offset and a world-to-screen matrix. Do not introduce a second unverified projection.
- Extend `pa26_map_grid` or a dedicated pure geometry module with a backward-compatible route-polyline input; **do not break existing function signatures, other consumers or map-grid tests**.
- Project every road node with the existing `M.project(v, x, y)` and clip each segment with `M.clip(...)`. The existing clipping supports a pause-map rectangle and radar ellipse; retain both behaviors.
- Draw an accessible amber/orange, contrasted line with a dark shadow or outline. The line must stand out from the white/blue/gold grid, without obscuring road names, police highlights or the standard GTA marker.
- Cache/simplify the world polyline (e.g., tolerance-based geometry simplification) and cap rendered segment count. A 2000-node calculation does **not** justify rendering 2000 costly line segments every frame.
- Reproject cached world-route nodes on map zoom/pan/view changes; **do not call native pathfinding on zoom or pan** if only the view transform changed.
- The route must remain visible even if grid labels are disabled. Decouple navigation-enabled from `map_grid.enabled` and from the current `mapFrame` predicate, which previously rendered only when the grid was enabled. Disabling the grid must not involuntarily disable GPS.
- Do not rely on new temporary GTA blips for the road polyline; draw clipped vector geometry in the PA overlay. A single optional destination marker is acceptable for OOC marks only; never duplicate the native user waypoint.
- If actual GTA front-end ordering or frame scheduling prevents rendering over Esc → Map, report that specific blocker and provide a tested fallback **without claiming the key requirement was met**.

### 1.5. Bounded recalculation

- New destination: enqueue one prompt high-priority path calculation and refresh on the next safe service/render cycle. Do not start multiple concurrent native path searches.
- Same destination: calculate again only after at least 20 GTA units of movement and a minimum 1500 ms interval. Use monotonic timer time, not wall clock.
- Prevent repeated searches when no graph nodes are returned: cache a failure/empty-result state and apply a retry backoff (for example 3–5 seconds), unless the destination changes.
- Throttle changes during native waypoint drag/update bursts; coalesce into the newest target. Do not delay an ordinary finalized user click unnecessarily.
- Refresh overlay projection independently from route calculation so map movement is smooth.
- Distance: show actual road distance **only when a verified successful route reports it**; otherwise label the value as straight-line distance (`по прямой`). Never silently relabel Euclidean distance as road distance.
- Support map pause without taking exclusive control of player input, changing pause flags or unpausing the game.

### 1.6. Experimental CPathFind binding — opt-in and guarded

Competitor implementation serves only as **design reference**, not a safe ABI guarantee. Its fixed addresses (`0x4515D0`, `0x96F050`, `0x583480`, `0x583530`) must not be blindly transplanted.

1. Require positively identified supported 32-bit GTA SA executable, verified PE metadata and **exact relevant code/data signatures** for the pathfinder and every other native function used. The current PA adapter already verifies its existing radar functions, but that does not prove the pathfinder ABI.
2. Confirm calling convention, `this` pointer, FFI structure sizes/alignment, node representation, maximum node count, output buffer sizes, graph layout, area count and memory ownership against independent evidence or controlled native tests.
3. **Known baseline issue:** existing `r:range(addr, n, ...)` rejects `n > 512`; therefore `r:range(0x96F050, 0x840, false)` from the Gemini draft is invalid and will always fail. Implement separate bounded, purpose-specific pointer/range checks, leaving the existing map reader's invariants intact. Heap allocations must not be incorrectly rejected merely because their allocation base is not `0x400000`; alternatively do not dereference them if they cannot be checked safely.
4. Validate each pointer/read individually, including access protection, committed state, address bounds, array indices, finite node coordinates and destination. Never read an entire structure through a single unchecked FFI cast.
5. Path node result cap: **no more than 2000 nodes**, or a smaller verified ABI limit. Validate count before iterating; deduplicate invalid/degenerate nodes and reject impossible distances.
6. Create and flush a `gps.lock` sentinel **before** the first native path-search call in a session, remove it only after completing an orderly first-call verification, and disable route-native mode on next start if the sentinel was left behind. Treat a stale lock as a suspicion, not proof of the cause of the last crash.
7. `pcall()` does not catch all native access violations. FFI pathfinding remains **experimental**, must have an in-game-off switch and must fail closed on unsupported builds.
8. If real GTA validation is unavailable, ship/test the non-native coordinate/UI parts and mark road-pathfinding as unverified/disabled rather than pretending the feature is safe.

### 1.7. HUD and control surface

- Compact, unobtrusive readout: `Навигация · Метка GTA · 1,45 км` or `350 м (по прямой)`; clear source and status labels.
- The route may be shown in F4 traffic/patrol and existing Map Settings, but **no patrol session is required** merely to use navigation.
- Settings should include: route overlay enabled, road-navigation experimental enabled, radar, pause-map, line style/opacity, source behavior, waypoint auto-clear (default off), mark TTL, and user-visible compatibility status.
- Keep route overlay optional and visually separate from Copilot's urgent 10-55 prompts. Never cover the GTA chat, active input, health/armor, vehicle radar or important toasts.

---

## 2. Smart OOC coordinate sharing (P0/P1)

**Suggested module:** `pa26_coord_share.lua` with pure parser/formatter/offer state; native/radio integration through existing main services and executor.

### 2.1. Outbound share

- F4 → Patrol and F4 → Traffic/Pursuit: compact `Координаты (OOC)` control. Also expose a user-assignable PA shortcut and optional wheel action without changing old shortcuts.
- Supported **only when verified on this server**: `/rn`, `/fn`, `/ln`, and `/sms` with numeric phone number. Do not add channels unsupported by current server permissions.
- Compatible payload pattern: `Мои координаты: X Y Z (Area, квадрат H-18)`. The three **first numbers after the fixed prefix** must be X/Y/Z. Preserve compatibility with the competitor's simpler `(Area)` suffix.
- Example: `/fn Мои координаты: -1984 442 35 (Doherty, квадрат H-18)`.
- SMS: `/sms 556677 (( Мои координаты: -1984 442 35 (Doherty, квадрат H-18) ))`.
- Source coordinates from the local player in the main world service, validated as finite, in-world and non-interior if appropriate. Cache before opening confirmation; revalidate session/identity and staleness before execution.
- The channel, complete encoded command, phone number (when relevant), and OOC warning appear in the **existing PA preview + Y/N confirmation**.
- Use the established command executor with full post-variable CP1251 byte-length preflight and command validation. No silent truncation, automatic retries or blind sends.
- Remind the user: OOC coordinates must not be treated as IC knowledge unless legitimately transmitted IC. Do not automatically create an IC `/r` report or invent an official code.

### 2.2. Incoming auto-offer

- Reuse `sceneServices.observeMessage(text, source, now)` and its current native/CEF deduplication; do not add new CEF input handlers.
- Parse **incoming** server messages only; suppress local echoes when reliably identified. Match the distinct `Мои координаты:` phrase, then parse the following coordinate tuple, including optional comma separators and a trailing `(Area)` or `(Area, квадрат ...)` description.
- Avoid the competitor parser's failure mode of using the first two/three numbers anywhere in a full chat line. Extract only numbers directly following the deliberate payload marker.
- Strictly validate finite X/Y/Z, supported map bounds, optional missing Z, length, malformed Unicode, separators and extra digits. Ground-Z resolution is a native world operation; do not assume remote terrain collision is loaded when another player is far away. Use a validated safe default or road-graph destination approximation and label limitations.
- Parse sender nickname from a **verified known server chat layout** only. If uncertain, display `Отправитель не подтверждён`, not an invented name or a spoofable arbitrary suffix.
- Reject normal prose mentioning coordinates, spoofed commands masquerading as chat lines, malformed channels and stale messages where possible. Chat text alone is not authenticated proof of the sender's role or IC location.
- Deduplicate cross-backend deliveries, rate-limit per sender and globally, and avoid creating multiple competing toast offers. Preserve the user's existing higher-priority Copilot confirmation state.
- Offer a non-modal Y/N toast, for example: `OOC-координаты от John_Smith · Garcia [K-12] · 1,2 км. Поставить временную метку и маршрут?`.
- **Y:** create/update a temporary PA-owned mark and set navigation target `mark`, without modifying or deleting the native GTA user waypoint. **N:** discard with no game-state changes.
- On acceptance of a new mark while another destination is active, clearly indicate temporary override. Preserve the previous native waypoint so it can be restored afterward.
- TTL default 5 minutes, configurable, and optional auto-clear on arrival within approximately 15 2D GTA units (do not mistake different interiors/elevations for actual arrival). All PA-owned markers and routes must be cleaned safely.
- Provide manual paste `X Y Z`, `[ Показать на карте ]`, `[ Убрать OOC-метку ]`, for cases where the chat format could not be observed.

### 2.3. Example behavior

1. Officer A shares coordinates through verified OOC radio with a PA Y/N preview.
2. Officer B, using PA, receives one deduplicated offer without copy/paste.
3. Officer B presses Y while **not typing in chat**; PA temporarily navigates to A's coordinates.
4. Officer B may still open Esc → Map and set an ordinary GTA waypoint, which takes priority according to an explicit, predictable source policy.
5. TTL/arrival removes only the temporary OOC state. No native user waypoint or server checkpoint is deleted.

---

## 3. Cruiser assistance: cruise control, turn signals, hazards (P1; default off)

**Suggested module:** `pa26_cruiser_assist.lua` (pure state) plus optional world/render adapter; integrate with verified PA vehicle identity and settings.

### 3.1. Cruise control

- Enabled only after user opts in; unassigned hotkey by default. Offer capture-validated keys, current-speed activation and target-speed activation, and ±5 km/h adjustment.
- Determine the actual supported speed units and the native meaning of `setGameKeyState` in this client **before hardcoding throttle/brake states**. Competitor values are not proof of a portable API contract.
- Only for living, focused local driver in a valid car; exclude bicycles/motorcycles/aircraft or other unsupported models unless verified.
- Immediate safe disengagement when braking, using handbrake, exiting/switching vehicles, losing driver seat, death, pause, typing in native/CEF chat, dialog, modal, loss of focus, script reload or failure.
- On disengagement ensure all simulated control states are released and do not interfere with physical keyboard input. Do not inject acceleration while chat input or any GUI modal is open.
- Respect manual steering and driver control; do not implement automatic driving, unsafe braking or pursuit automation.
- Clearly mark cruise speed as GTA-derived or calibrated km/h; don't invent exact km/h precision.

### 3.2. Turn/hazard lights

- Optional client-local visual indicators; default disabled. Configurable bindings with conflict detection.
- Prefer explicit left/right toggles plus hazard toggle, with configurable automatic cancellation only if verified. Avoid interpreting every ordinary steering key as a signal while the player is typing.
- Render amber lights in vehicle-local positions using verified geometry, model/offset checks and bounded draw cost. No per-frame heap allocations or unsafe native calls for unsupported models.
- Show `Аварийка: ВКЛ` and/or `Круиз: 60 км/ч` unobtrusively in Copilot/HUD.
- Optional `auto_hazard_on_10_55=false`, **off by default**, and only if it cannot conflict with the player's current vehicle state.
- Explicitly tell the user that these visuals are **local only** unless networking/synchronization has been demonstrated. Never imply other players can see them.

---

## 4. Pinned floating notes (P1)

**Suggested module:** `pa26_pinned_note.lua` with integration into current note models and F9 Studio.

- Add `[ Закрепить поверх игры ]` to an existing saved note; do not create a second notes database or duplicate F8/F9 note implementations.
- One small overlay at a time, displaying title and readable, wrapped text. Optional switching between saved notes from a controlled edit mode.
- Default gameplay mode must be click-through and non-focusable (`NoInputs`, `NoMove`, `NoNav`, `NoFocusOnAppearing`, where supported), not blocking aim, camera, typing, chat selection or vehicle controls.
- Allow moving/resizing/opacity changes **only in an explicit PA editing mode** (e.g. with F9 open), not merely because Alt is held during gameplay.
- Save note ID, normalized or resolution-safe placement, dimensions, opacity and visibility through existing validated settings, with safe migration and bounds checks.
- Clamp to screen after resolution change and provide a clear recover/reset-layout action.
- Avoid per-frame copying or reparsing long notes; reuse prepared text.

---

## 5. Leadership Studio: `/gnews` and verified briefings (P1/P2)

**Suggested module:** `pa26_leadership_ui.lua` plus existing Studio, bindings and safe executor. Design for PD, FBI and Alcatraz senior personnel; no new support for unrelated factions.

### 5.1. `/gnews` composer

- First verify the current Exsellent RP command syntax, permission requirements and maximum encoded wire length using the project knowledge/source registry and server evidence. The draft's `/gnews <Tag> | <Text>` is a **proposed preview example**, not a confirmed server command contract.
- Offer one-line and three-line composition only if the server actually supports both workflows. Keep drafts and saved presets as editable user content.
- Per-line live **post-expansion CP1251 byte** count including exact slash-command prefix, tag, separators and spaces. Reuse established PA wire limits and executor instead of introducing an inconsistent magic `128`. A server-reported character limit may differ from a wire byte limit.
- Preflight the complete multi-command sequence **before** sending any part; no midword truncation, hidden partial automatic sending, or unsupported retry.
- Always show exact commands + editable tag/department/line content in a confirmation preview, followed by deliberate Y/N.
- No auto-claims about factually unsupported announcements. Add optional presets such as technical notices only if they are neutral, user-edited and appropriate to verified permissions.
- Saving, editing, cloning and deleting presets must preserve user data, recover from malformed storage and maintain clear ownership.

### 5.2. Briefings and lectures

- Provide a search/filterable, optionally favorited library of editable briefings, grouped by PD/FBI/Alcatraz and role.
- Only ship **verified** stock material from the project's authoritative up-to-date police source registry, with source labels and optional last verification timestamp; otherwise clearly mark a template as `Пользовательский / Не проверено`.
- Topics can include radio discipline, traffic stops, high-risk stops, pursuits, Miranda/legal rights, force/taser rules and prison operations — but do not fabricate statutes, arrest times, Miranda/call durations, rank rights, internal commands or penalties.
- Use current server terminology (`10-55`, `10-66`, `10-57 VICTOR/FOXTROT`, etc.) **only where documented by authoritative current sources**; never copy the competitor's `10-38`/`10-80` uncritically.
- Lectures are an *officer-controlled presentation aid*. Show a line-by-line preview and progression; no unattended mass chat spam. Existing send limits, pauses and cancel controls apply.
- Estimate presentation duration conservatively and label it as an estimate rather than a factual server requirement.

---

## 6. Inline compact nearby target bar + non-destructive favorites (P1)

### 6.1. Reuse the existing `pa26_nearby.lua`

The current PA already has `Nearby:view()` with rows, selection revision, and identity-aware two-stage revalidation. **Do not add a second native player scanner or independent target registry.**

- Build a compact one-line presentation of the current validated nearby snapshot (up to 6 closest visible people, or fewer based on width), within F4 traffic/pursuit and eligible procedure windows.
- Example: `Цель: John_Smith [42] · 6,2 м` plus `[ Сбросить ]` and compact `[ Nick_Name [ID] · 4 м ]` chips.
- Reuse existing `Nearby:request(...)` / `requestId(...)`, session/identity/generation checks, and main-loop revalidation. Clicking selects a target; it **never** sends `/pt`, `/su`, `/ticket`, `/ud` or another server command automatically.
- The existing nearby `safe(state)` predicate requires `nearbyOpen == true`; update its visibility flag only for supported F4/procedure contexts, and clear it promptly when those contexts close.
- Ensure layout adapts to available width and does not obscure important Copilot prompts or reduce minimum supported resolution usability.

### 6.2. Favorites

- Add an optional `favorite=false` attribute only if it can be migrated and round-tripped through all actual binding schemas, profiles, exports/imports and current UI editors without deleting unknown custom fields.
- Display favorite binds first **in the quick-launch presentation**, but do not destructively reorder the user's persisted bind list, wheel sectors or keyboard assignments.
- UI: unobtrusive star pin in F8 quick access and F9 binding library, with keyboard-friendly accessible label and save feedback.
- Don't add a duplicate favorites feature if a newer 0.43.4 UI version already contains a compatible mechanism.

---

## 7. Consistent PA UX and visual design (P1)

- Respect existing UI/branding themes and any shipped 0.43.4 icon system; no separate unrelated `fAwesome5` dependency unless explicitly required after checking installed font resources and licenses.
- Place controls where officers naturally expect them: navigation in Map/HUD and F4, OOC coordinates in Patrol/Traffic, cruiser in Transport, leadership tools in Studio, pinned notes beside current notes, nearby chips adjacent to procedure target selection.
- Keep F4 tactical and brief; F9 for detailed configuration. Don't add extra mandatory RP windows.
- Support 640×480 through 2560×1440; typography legible in Cyrillic, keyboard interaction safe, dynamic widths/clipping responsive, overlays outside chat input, no flickering/duplicate labels.
- Every button has a meaningful enabled/disabled state and a short reason when unavailable. Preview exact effects and source provenance (native waypoint vs OOC mark vs server checkpoint vs approximate bulletin).
- Do not create unsolicited popups every time the user passes a checkpoint or enters a vehicle. Non-critical suggestions should be throttled and dismissible.

---

## 8. Settings, migration and persistence (P0)

- Prefer a `navigation`/`coordinate_share`/`cruiser_assist` settings group over inflating the current map-grid schema indiscriminately. Existing grid settings retain their meaning, especially `enabled`, `radar`, `pause_map`, `highlight` and `auto_square`.
- New experimental features default off, except safe read-only native-waypoint observation if it has no performance/compatibility costs. Route overlay enablement and low-level native road-pathfinding enablement are **different toggles**.
- Offer non-native straight-line direction and native GTA waypoint support when road routing is unsupported.
- Validate every new persisted setting, restore documented defaults on invalid values, and preserve previously valid values. Ensure migration idempotency and byte-for-byte preservation of unrelated custom data.
- Store OOC mark source/TTL as volatile gameplay state unless there is a compelling validated requirement to persist it; do not restore stale coordinates from a previous server session.
- Do not weaken existing backup, atomic-save, update, rollback or user-file protection mechanisms.

---

## 9. Verification and acceptance matrix (P0)

### 9.1. Pure deterministic tests

Create focused tests in existing `tests/` style; small modules and multiple focused test files are preferred over one huge test file. Ensure tests are actually run and report real counts; do not manufacture passing results.

**Navigation/state:**
- Native waypoint create/move/remove; missing readings; `(0,0)` is valid; finite/bounds validation; rapid changes; session changes; target ownership/priority; temporary mark override and restoration; clear PA route without clearing native marker.
- One calculation on target change; 1500 ms / 20-unit movement throttle; empty-route backoff; disabled pathfinder; straight-line distance clearly labeled.
- Server checkpoint set/remove and race checkpoint set/remove; server checkpoint never erases native user waypoint; no stale source after server disconnect.
- Bulletin route to approximate district only on explicit user action; label it as approximate.

**Map geometry:**
- All supported view geometries, projection and clipping against both map rectangle and radar ellipse; no route segments outside view; zoom/pan reprojection without calling pathfinder.
- Existing map-grid and stolen-bulletin visuals intact with route on/off, grid on/off, long routes and tiny maps.
- No custom mouse handlers; native GTA click behavior untouched.

**Native pathfinder:**
- Adapter rejection on unsupported PE/signature, missing/invalid heap pointers, excessive nodes, invalid distance, NaN and overflow; `r:range` 512-byte restriction explicitly tested and never bypassed unsafely.
- Simulated stale `gps.lock` forces fail-closed mode; removal only after completed first-call guard; settings remain recoverable.
- No claim of native call safety based solely on `pcall` or the simulation.

**OOC coordinates:**
- `/fn`, `/rn`, `/ln`, `/sms` formatting, command prefix length, encoded CP1251 preflight, invalid phone numbers, echo suppression, duplicate native/CEF messages, unknown sender, spam floods, malformed numeric input, unrelated chat numbers, negative coordinates, missing Z, TTL and arrival.
- Non-interference with chat input, existing high-priority toast, manual `/ud` and Copilot; no unintended server sends after cancellation.

**Cruiser:**
- Activation/deactivation, user keys, speed source, driver seat, changing vehicle, brake/handbrake, death, CEF/native chat open, pause, focus loss, reload; ensure no stuck throttle/brake state.
- Local-only signal visual handling; unsupported vehicle geometry uses safe fallback.

**UI/data:**
- Pinned note click-through and explicit edit mode; resolution changes; preset round-tripping; `/gnews` complete byte-length checks; three-line preflight; favorite ordering without altering wheel order; nearby target generation/revalidation; old settings and user data preserved.

### 9.2. Performance tests and in-game test plan

- Re-run the complete established test suite and relevant native x86 LuaJIT/mimgui tests. Include actual GUI tests for 640×480, 1024×768, 1920×1080 and 2560×1440, plus non-default DPI where possible.
- Compare CEF typing, text-selection, copy/paste, and mouse input to the **actual 0.43.3 performance baseline**. No work in the CEF keystroke hot path is allowed for this release.
- Check FPS/frame-time in ordinary driving, active pursuit, Esc map open, repeated zoom/pan, distant waypoint route, pathfinder failure, spammed coordinate messages, multiple active overlays, and with all new optional features disabled.
- The following are **mandatory real-game acceptance checks**, not satisfied by simulation alone:
  1. Standard Esc-map waypoint appears normally with no custom mouse input interception.
  2. The road route becomes visible **while Esc → Map is still open**, not only after closing Esc.
  3. Changing waypoint while Esc stays open updates the route, with no flicker or unwanted native waypoint removal.
  4. Removing the native waypoint removes PA navigation only.
  5. The same route correctly displays and updates on the ordinary gameplay radar.
  6. Ordinary CEF chat typing and mouse text selection remain smooth.
  7. Unsupported GTA builds disable only experimental navigation, never the rest of PA.
  8. OOC coordinate offers are deduplicated and never send commands without confirmation.
- If actual GTA is unavailable, **do not report these eight as passed**. Include an explicit user-facing manual test checklist and identify any unverified requirements.

### 9.3. Adversarial edge cases, fault injection and long-running stability (NEW, mandatory)

**Test each failure at the precise state transition, not just with static invalid data.** For every scenario, assert the resulting state, resource cleanup, lack of accidental server commands, preservation of the active GTA waypoint and absence of stale Y/N prompts. Run pure model tests and mocked-native tests first. Never inject unsafe addresses, malformed bytes or forced crashes into the user's live GTA process.

**A. Navigation lifecycle and native API boundaries**

1. Start with no waypoint; create/move/remove the **native GTA waypoint** while Esc → Map is open; create `(0, 0)`; set the same coordinate twice; rapidly move it 50 times; close Esc in the same tick as the change; resize screen or change radar zoom mid-route; temporarily lose focus. Exactly one latest destination should win, without duplicate paths or map-click interception.
2. Distinguish native waypoint absence from an API that returns `false`, `nil`, zero-like values, a tuple with optional return flag, a missing Z, invalid coordinate or an unsupported runtime. **Verify the real function signature before interpreting values.** Do not treat `x == 0` or `y == 0` as absence. Unknown ground height must not lead to unsafe scans or made-up road routing.
3. Test user waypoint, server checkpoint, race checkpoint, timed OOC mark and bulletin source arriving/replacing/expiring in different orders. A lower-priority source must not clear the higher-priority source; switching back must not resurrect expired destinations. Clearing an overlay does **not** erase the game's own red waypoint by default.
4. Validate pause-page detection against non-map Esc screens, pause activation/deactivation races, nonstandard resolution, aspect ratio, DPI, zoom extremes, map offsets, transformed coordinates, clipping, discontinuities, zero-length routes and paths crossing the map border. The visible line may be clipped; the original route must remain intact for future zoom/pan.
5. Pathfinder output adversaries: no path (water, inaccessible road, islands), one node, 2,000 nodes, >limit count, repeated/cyclic nodes, reversed order, non-finite coordinates, non-monotonic distance, graph pointers becoming invalid, uninitialized areas, unsupported EXE/ASI mod, and an elapsed native call longer than the frame budget. Reject invalid results and fall back to an explicitly labeled straight-line distance or no route, not a fake road path.
6. A new target arriving during path computation must invalidate the old result by **request generation/token**; the old result must never overwrite the new target even if callbacks complete out of order. Coalesce rapid updates, cache negative results briefly, and bound every route, blip/marker, closure, geometry and queue. No unbounded per-frame allocation growth.
7. Exercise start/restart/reload/unload/quit and a stale `gps.lock`. Verify clean recovery and an understandable disabled-mode notice. `gps.lock` must not overwrite unrelated files, and a stale lock is not proof that GPS caused a previous unrelated GTA crash. Never claim native memory safety from Lua unit tests.

**B. Chat, OOC parsing and confirmations**

1. Feed the pure parser empty text, huge lines, UTF-8/CP1251 Cyrillic, timestamp/ID prefixes, whitespace variants, comma/dot decimal forms, signs, 2D/3D coordinates, zeros, NaN/Infinity-like strings, scientific notation, overflow, 10,000-digit numbers, bogus map bounds, nested brackets, unrelated GPS-like digits and command-injection text. Fail safely and in bounded time without copying arbitrary chat text to a command.
2. Test duplicate native + CEF sightings in either order, own echo, same coordinates from different senders, a disconnected sender whose ID is reused, messages from unsupported channels, quoted third-party text and apparent coordinates written by a random user. A received text line is **untrusted**, even if it resembles a radio message. Display origin uncertainty; do not automatically assume verified officer identity or IC evidence.
3. Flood the observer with at least 1,000 synthetic coordinate-like messages while Copilot, Y/N, the chat editor and other notifications are active. Rate-limit by sender/channel and globally, coalesce duplicates, cap pending offers, give existing higher-priority police alerts precedence, and ensure normal frames remain responsive. Accepting an old toast after its sender/target/source changed must fail preflight.
4. Test Y/N while typing native or CEF chat, editing a modal, pressing Y to type a word, holding keys, focus loss and a paused game. No global confirmation should fire. Sending coordinates requires explicit preview/approval and the existing protected executor; commands must be CP1251/byte validated. A failed or uncertain send must not be marked server-accepted.
5. When an OOC mark expires or reaches its destination, clear **only PA-owned** blips/checkpoints/route state. Late timer callbacks must not remove a newer mark or a native GTA waypoint. Never turn OOC coordinates into an IC location assertion.

**C. Cruiser input and rendering fail-safes**

1. Exercise cruise engage/disengage while parked, accelerating, braking, reversing, switching driver/passenger seat, entering/exiting different vehicles, being ejected, dying, teleporting, changing game focus, entering pause, opening CEF/native chat, opening a modal and reloading PA. Treat uncertain input ownership or vehicle identity as a reason to disengage; **release all injected keys on the very same service transition**, including error cleanup and script termination.
2. Distinguish user-held accelerator/brake from PA-injected state; do not issue a fighting accelerate/brake loop, duplicate a held key, or unexpectedly resume acceleration after closing chat, unpausing or alt-tabbing. Cruise must require a new conscious activation after a safety disengagement. No unverified vehicle physics memory writes or unrealistic speed guarantee.
3. Test turn signals/hazards on vehicle model extremes, missing model dimensions, damaged/destroyed vehicle, invalid offset calculations, odd camera distances and variable FPS. Local render effects must be bounded (normally four signal positions), visually optional, cleaned up on vehicle changes and must not impersonate synchronized/server-visible vehicle lights.

**D. Overlay/UI, leadership and existing PA regressions**

1. Pin a very long note, malformed/empty note, deleted or renamed note; reopen across F4/F9 switching, resolution/font scaling, pause, CEF focus and restart. Normal gameplay must always be click-through; editing mode must never steal CEF typing or leave input captured after an exception. Cache layout and text shaping; do not remeasure unchanged thousands of characters every frame.
2. `/gnews`: 0/1/3 lines, long Unicode, CP1251 boundaries, edited tags, template variables, changed permission/rank, failed partial sequence, server rate limit, reconnect between lines and a user cancelling after line one. Before **each** send recheck preconditions; report partial completion honestly, never silently retry an already-emitted line and never bulk-send without explicit confirmation.
3. Nearby player bar: ID reuse, name change, player death, ped stream-out, dimension/interior change, two players at the same distance, a stale UI snapshot and a click during a server reconnect. Revalidate name/ID/generation/visibility/action preflight at execution, never command a new occupant of a recycled ID.
4. Favorites, presets, icons and migrations: duplicate favorite keys, invalid JSON, truncated config, missing optional icon/font resource, legacy settings with unknown fields, upgraded/downgraded profiles and an interrupted save. Preserve existing profile and wheel order; use the established atomic/backup mechanisms, not a new destructive store. Missing optional resources must fall back to text-only UI.
5. Interoperation: high-priority Copilot 10-55/10-57/10-66 while GPS and cruiser aids run; stolen bulletin disappearing during route display; manual `/ud` and coordinate toast in the same frame; all new features turned on; all turned off; default native SA:MP chat instead of launcher CEF. Recheck existing regressions fixed in 0.43.3: unknown direction, civilian passengers, stream-out finish offer, per-reason edited speech.

**E. Soak, property and recovery tests**

- Use **deterministic seeds** and record a minimal repro for every failure. Property/fuzz-test the pure parsers, route arbiter and geometry (finite inputs, bounded outputs, no unowned side effects); do not fuzz actual process memory or issue server commands.
- Run a synthetic soak of at least **30 minutes** with repeated waypoint changes, map zoom, reconnects, coordinate floods, cruise toggles, note switching and a long chat history. Record heap/memory trend, number of outstanding timers, markers, hooks, queues and FFI handles; assert they return near baseline after cleanup. Numbers of assertions are not a substitute for distinct scenarios.
- Simulate dependency absence (`getTargetBlipCoordinates`, `mimgui`, `ffi`, `getModelDimensions`, CEF bridge, optional icon font), handler exceptions, invalid settings, mid-transaction interruption and cancellation. Each should produce a bounded failure, preserve old user data and leave previously working PA functions available.
- Verify with release/package update simulation that every new module and asset is in manifests with correct hashes, and no extra `onWindowMessage`, chat listener, heartbeat, UI frame hook or loopback service is duplicated by reload. Compare actual shipped files, not only repository files.

**Required edge-case report format:** for each subsystem show `scenario → expected state → test type (pure/mock/native/game) → observed result → PASS/FAIL/NOT RUN/BLOCKED → risk/next action`. Separate P0 crash/input/safety/data-loss defects from P1 wrong-target/duplicate/UX faults and P2 cosmetic issues. **Any unresolved P0 blocks release**, and native pathfinding stays disabled until explicitly verified in real GTA.

### 9.4. Deliverables from Codex

1. Concise inventory of current code, existing features reused, new files added and preserved subsystem contracts.
2. Completed implementation **only for stages that can be verified safely**; the experimental road pathfinder may remain behind a clearly disabled feature flag if in-game/ABI verification is unavailable.
3. Clear migration notes and safe settings defaults.
4. Focused regression/unit tests plus real command/test output, no fake performance or test claims.
5. Detailed manual GTA/Exsellent RP acceptance checklist with expected results and rollback guidance.
6. Honest remaining-risk report, including native FFI crash risk, game-build compatibility, pause-map rendering timing, CEF latency and unsupported server command syntax.
7. No changes to protected updater, no unsolicited release/publish/install, no user-data loss.
8. `docs/PERFORMANCE-0.43.5.md`: measured baseline-versus-candidate timings and memory/queue counters, with environment, repeated trials, opt-in profiler methodology, disabled-feature parity and explicit unmeasured cases.
9. `docs/EDGE-CASES-0.43.5.md` (plus machine-readable results if practical): the matrix above with minimal repro inputs, risk levels, PASS/FAIL/NOT RUN status and cleanup checks. Do not substitute one giant check count for evidence of separate edge-case coverage.

---

## 10. Recommended implementation order

Work in these stages and report results after each. Prefer an individually testable change over shipping unverified features together.

1. **Baseline and preservation:** inspect actual current repository, pending changes, 0.43.3 CEF and 0.43.4 UI state; freeze/test updater and user data.
2. **Native waypoint state:** implement read-only observation and source arbitration; prove native map controls remain untouched.
3. **Pure route presentation:** map/radar vector geometry, grid coexistence, distance/HUD and pause-map render scheduling. Use a mock route polyline initially.
4. **Optional road routing:** separate pathfinder ABI verification, feature flag, crash guard, cache/backoff and fail-closed fallback; retain in-game verification gate.
5. **OOC coordinates:** compatible outgoing preview and robust incoming Y/N offers; temporary marks and TTL.
6. **Cruiser:** optional safe cruise control, then visually verified local hazard/turn lights.
7. **Pinned notes, leadership studio, compact nearby chips and favorites:** reuse existing user data and UI systems.
8. **Regression, performance, package review:** native x86 checks, three matched A/B performance runs where available, fault/soak matrix, actual shipped-file hashes and explicit list of real GTA tests that still need the user. If the changes cause reproducible input or frame-time regressions, disable the responsible optional feature and report the blocker.

**STOP CONDITION:** If fulfilling the requested immediate Esc-map road-route behavior would require unknown native ABI assumptions, unsafe memory writes, unverified mouse interception, or disabling essential PA safeguards, stop that component and report the blocker. Do not covertly weaken guardrails or substitute an inaccurate feature while claiming completion.

---

## Final non-negotiable acceptance definition

**User experience:** I open the ordinary GTA **Esc → Map**, create a normal GTA user waypoint using the game's built-in control, and immediately see PA's road-following route over the map **without closing Esc**. Closing Esc displays the same route on my radar. Moving/removing the ordinary GTA waypoint updates/removes the corresponding PA route. The native waypoint remains the game's own object; PA never creates a competing LMB/RMB marker mechanism. OOC marks and server checkpoints are supplementary, correctly prioritized and never destructive.

**Quality:** No CEF typing/input regression, no native-call bravado, validated user data preserved, no blind server commands, and clear reporting of what was actually tested in GTA versus what remains to be verified.
