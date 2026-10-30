# CODEX IMPLEMENTATION SPECIFICATION — Police Assistant 2026 v0.43.2

**Baseline:** the supplied `Police-Assistant-v0.43.1.zip`. **Objective:** implement a cohesive, stable v0.43.2 addressing live patrol bugs and adding event-aware police assistance. This is an implementation request, not a request for a high-level proposal. Inspect the actual source before editing, implement the work in coherent milestones, validate it, and deliver the changed source with a precise verification report. Do not publish to GitHub or install into the user's game without separate authorization.

## 0. Mandatory architecture, data preservation, and integration rules

1. Work on the provided v0.43.1 source. Do not assume that line numbers from older reviews still match; locate functions by name and inspect callers before changing them.
2. Preserve the behavior and byte contents of `moonloader/lib/pa26_update_platform.lua` (expected SHA-256: `995b131aa0250b7ea407915ad7d109de71a8e43cec088603bc99cc489e60565f`). Do not alter updater security, loading, signatures, install/recovery logic, or CEF contracts unnecessarily.
3. Preserve all existing user profiles, custom bindings, wheel layouts, saved settings, reports, notes, contacts and personal RP/radio templates. Migrate only unchanged stock templates; never replace customized text silently.
4. Preserve the architecture: native GTA/SA:MP/WinAPI interaction belongs in the established main/world observation and dispatch paths; pure state machines and ImGui views consume prepared state. Reuse the existing executor, `C:propose`/`C:accept`/`C:decide`, toast confirmation, text preparation, and `Y/N` infrastructure.
5. **Sending is not server acceptance.** Mark a command as sent after successful client-side emission, but never claim that the server accepted `/ud`, `/pt`, `/ticket`, `/su` or a radio command unless confirmed by an actual server event.
6. Maintain the existing identity checks for streamed vehicles (`id`, `handle`, `model_id`, `generation`) and players (`id`, nickname, ped/generation where available); never transfer cached incident data to a different player who inherited an ID.
7. No automatic fines, pursuit, wanted status, shootings, emergency codes, window opening, dialogue, or reports merely from speculative detection. Require the relevant officer confirmation.
8. No mandatory Patrol Session for the F4/Copilot **manual and quick radio actions** defined below. This does not bypass on-duty/radio/safe-game checks, target validation for target-dependent actions, or the user's own intent to turn Copilot off.
9. Where native chat events are unavailable or a third-party MoonLoader script bypasses observable hooks, provide a clear manual fallback. Do not misrepresent an unobservable action as detected.
10. Treat everything below as one cohesive design. In particular, Sections 5, 6 and 8 are linked: manual `/ud`, the approach/window dialogue, one-time stop reporting, departure and finish-vs-pursuit state must not interfere with one another.

## 1. Fix the non-functional F4 → Patrol → “Трафик-стоп и преследование” button

**Relevant files:** `pa26_patrol_ui.lua`, `police_assistant_2026.lua` and the existing F4/F9 navigation infrastructure.

In v0.43.1, `pa26_patrol_ui.lua` has a button that assigns `studio.partnerPage='vehicle'`. This does not reliably navigate to the intended F4 `assistPage='traffic'` or the equivalent F9 service tool.

Requirements:

- From `F4 → Патруль`, the button must open **F4 → Трафик и погоня** immediately.
- When this shared UI is used through F9, route to the existing F9 vehicle/traffic tool instead.
- Do not unconditionally jump from F4 to F9, open duplicate windows, or mutate both navigation stacks as a side effect.
- Use a context-aware callback if the same patrol UI is rendered in multiple hosts.
- Preserve focus, existing input state and navigation confirmation conventions. Test both entry points.

## 2. Preserve the final *actual movement direction* of the patrol cruiser

**Relevant files:** `pa26_vehicle.lua`, `pa26_vehicle_world.lua`, `police_assistant_2026.lua`, radio-value consumers.

`Vehicle:direction()` currently resets `self.directionValue` to the stationary label, producing malformed reports such as `Направление: На месте` or `двигаюсь на На месте`.

Requirements:

- Keep `self.lastDirectionValue`, updated only from a reliable movement vector with sufficient displacement and the existing age/tolerance checks.
- When the cruiser stops, preserve its last actual driving direction before stopping. Do **not** replace it with `На месте` and do **not** substitute an arbitrary default `Север`.
- Vehicle heading describes orientation, not necessarily the direction of its previous movement: do not replace the movement history with a heading as though it were observed travel.
- If there is no reliable previous movement, report the direction as unknown or omit the direction-dependent clause. Never render `двигаюсь на не определено`.
- Keep the last direction through the officer exiting the cruiser and through preparation of a stop/end-of-stop report; reset it appropriately on new session/character or truly different own vehicle.
- Ensure patrol, Copilot, vehicle, dispatch, alerts and radio-guard templates resolve direction consistently, without changing customized user wording unnecessarily.

## 3. F4 reports and dispatch controls work WITHOUT an active Patrol Session

**Relevant files:** `pa26_copilot.lua`, `pa26_copilot_ui.lua`, `pa26_copilot_settings.lua`, `pa26_dispatch.lua`, `pa26_patrol_session.lua`, `pa26_patrol_settings.lua`, `police_assistant_2026.lua`, and wheel integration where relevant.

### 3.1. Independent manual-report capability

The officer must be able to use F4 quick reports, all five dispatch categories and their follow-up reports, and `Продолжаю патрулирование · Код 4` even when:

- the user has not opened the Patrol page;
- `patrolSession.data.active == nil`;
- the formal Patrol Session feature is disabled/not started.

Do not make the officer start a formal timer/session simply to transmit a radio report. Rework overly broad `require_patrol` checks **per action** so that manual/quick F4 reports are exempt, while preserving on-duty, radio-enabled, game-safety, selected-target and context restrictions for actions that actually need them. Distinguish a reporting action from starting/stopping a formal Patrol Session.

In `C:values()` (and wherever previews are built), populate the real-time values needed without an active patrol record: `{unit}`, `{crew}`, `{unit_crew_count}`, `{patrol_start}`, `{patrol_resume}`, `{patrol_finish}`, `{patrol_moving}`, `{patrol_available}`, `{city}`, `{area}`, `{map_square}`, `{direction}`, `{local_tag}`. Reuse `pa26_patrol_settings.crewCount`, `grammarDefaults()` and the existing current profile/colleague observations, but avoid inventing a second officer.

### 3.2. Dedicated confirmation window for EACH F4 radio report

Clicking any F4 radio/report button must open a **small, clear preview/confirmation window** before anything is sent, independently of Patrol Session. The user explicitly wants a simple workflow.

Suggested title: `Подтверждение доклада`.

Display relevant resolved fields, for example:

- `Юнит: 1-L-1` (or `1-A-1` when a verified partner is present; any user override takes precedence)
- `Экипаж: Victor Auditore` (or actual verified team composition)
- `Место: <город>, <район> (<квадрат>)`
- `Направление: <последний реальный курс / неизвестно>` when relevant
- `Вызов / объект / цель:` when relevant
- A **complete preview of the exact `/r`, `/f` or other radio line(s)** prepared for transmission.

Provide `Да · Отправить` and `Нет · Изменить данные / Отмена` (or equivalent existing UX):

- **YES:** send exactly the previewed, validated report via the normal executor; no second unnecessary modal and no Patrol Session dependency.
- **NO:** send nothing. Show a concise message such as `Измените маркировку юнита и состав экипажа перед отправкой`, with clear inline edit/navigation for `Юнит` and `Экипаж`; allow the user to cancel entirely or return to the updated preview.
- Do not discard changes if the user chooses to edit and return. Rebuild/revalidate the prepared lines after any edit, and require confirmation of the updated preview.
- If critical values cannot be resolved, show `Не задано` and ask for correction; never silently fabricate a partner, incident, target or unknown location.
- The same confirmation principle applies to each nested follow-up button and the stand-alone patrol-continue report.

This confirmation is a separate report-preview flow; do not confuse it with the `Y/N` gameplay suggestion to finish `10-55` or initiate `10-57`.

### 3.3. Five dispatch categories, three *nested radio-only* follow-up buttons each

Keep the existing **primary** dispatch button, which performs its current RP + radio workflow. Within each category's F4 group add exactly three subordinate buttons — `Прибыл / Работаю`, `Проверено / Завершено`, `Нужна подмога`. Use a compact expandable or clearly grouped interface, **not** one unstructured list of 15 buttons. The follow-up buttons send **radio only** (no duplicate terminal/PDA RP). Implement explicit `radioOnly` metadata/dispatch behavior so that merely adding actions to `dispatch.actions` cannot accidentally attach RP in `C:prepare()`.

All templates below are editable stock examples. Use real location, unit, crew and incident information. Respect the manual's definitions of Code 1 (officer in distress), Code 3 (urgent response), Code 4 (no assistance needed), Code 5 (exclusion area, only if actually declared), Code 6 (remaining on scene), 10-70 (request assistance), 10-99 (situation resolved), 211 (robbery). Do **not** claim that Code 1/5 is active merely because suspects are armed.

#### 9-1-1 (`dispatch_911`)

1. `dispatch_911_arrived` — `Прибыл на 9-1-1 · Работаю (Код 6)`:
   `{local_tag}{unit}, экипаж: {crew}, прибыл по вызову 9-1-1 в район {area} ({map_square}). Код 6, проверяю обстановку и опрашиваю граждан.`
2. `dispatch_911_clear` — `Вызов 9-1-1 проверен · 10-99 / Код 4`:
   `{local_tag}{unit}, вызов 9-1-1 в районе {area} ({map_square}) проверен, нарушений не обнаружено. 10-99, продолжаю патрулирование, Код 4.`
3. `dispatch_911_backup` — `На 9-1-1 нужна поддержка (10-70 / Код 3)`:
   `{local_tag}{unit}, по вызову 9-1-1 в районе {area} ({map_square}) требуется поддержка. 10-70, запрашиваю свободные экипажи, Код 3.`

#### Stolen vehicle (`dispatch_stolen`)

1. `dispatch_stolen_arrived` — `В секторе угона · Ищу (Код 6)`:
   `{local_tag}{unit}, экипаж: {crew}, прибыл в сектор поиска угнанного транспорта, 10-20: {area} ({map_square}). Код 6, осматриваю район.`
2. `dispatch_stolen_clear` — `Сектор проверен · ТС не обнаружено`:
   `{local_tag}{unit}, сектор поиска в районе {area} ({map_square}) проверен, угнанный транспорт не обнаружен. 10-99, Код 4, продолжаю патрулирование.`
3. `dispatch_stolen_backup` — `Угнанное ТС замечено · 10-70`:
   `{local_tag}{unit}, обнаружен транспорт {stolen_summary} в районе {area} ({map_square}); запрашиваю 10-70, свободные экипажи по Код 3.`

#### Business robbery (`dispatch_business`)

1. `dispatch_business_arrived` — `Прибыл к бизнесу · Периметр (Код 6)`:
   `{local_tag}{unit}, экипаж: {crew}, прибыл к бизнесу по тревоге в районе {area} ({map_square}). Код 6, проверяю объект и периметр.`
2. `dispatch_business_clear` — `Бизнес проверен · 10-99 / Код 4`:
   `{local_tag}{unit}, тревога бизнеса в районе {area} ({map_square}) проверена, ситуация урегулирована. 10-99, Код 4.`
3. `dispatch_business_backup` — `Бизнес · 211 / 10-70, поддержка`:
   `{local_tag}{unit}, код 211 у бизнеса в районе {area} ({map_square}), требуется поддержка! Запрашиваю 10-70, свободные экипажи по Код 3.`

#### Gas station robbery (`dispatch_gas`)

1. `dispatch_gas_arrived` — `Прибыл к АЗС · Работаю (Код 6)`:
   `{local_tag}{unit}, экипаж: {crew}, прибыл по тревоге на АЗС в районе {area} ({map_square}). Код 6, контролирую обстановку.`
2. `dispatch_gas_clear` — `АЗС · Ситуация завершена (10-99)`:
   `{local_tag}{unit}, ситуация на АЗС в районе {area} ({map_square}) урегулирована, 10-99. Продолжаю патрулирование, Код 4.`
3. `dispatch_gas_backup` — `АЗС · Вооружённые / 10-70, Код 3`:
   `{local_tag}{unit}, вооружённые лица на АЗС в районе {area} ({map_square}), требуется поддержка! 10-70, свободные экипажи по Код 3.`

Keep the existing `gas_order` action distinct. Add a `Code 5`/clear-Code-5 report only if the officer expressly chooses that state; never insert it automatically into a generic arrival or clear template.

#### Bank robbery (`dispatch_bank`)

1. `dispatch_bank_arrived` — `Прибыл к банку · Работаю (Код 6)`:
   `{local_tag}{unit}, экипаж: {crew}, прибыл к банку по тревоге в районе {area} ({map_square}). Код 6, контролирую периметр.`
2. `dispatch_bank_clear` — `Банк · Ситуация завершена (10-99)`:
   `{local_tag}{unit}, ситуация у банка в районе {area} ({map_square}) урегулирована, 10-99. Код 4.`
3. `dispatch_bank_backup` — `Банк · 211 / 10-70, Код 3`:
   `{local_tag}{unit}, код 211 в банке, район {area} ({map_square}), запрашиваю 10-70, свободные экипажи по Код 3!`

Require the officer to validate what actually happened before sending any definitive `всё спокойно`, `обнаружен`, `вооружённые` or `ситуация урегулирована` statement. A radio template is an officer-chosen report, **not** an inference from mere proximity.

### 3.4. Stand-alone “Продолжаю патрулирование · Код 4”

Add `patrol_continue` to the F4 quick actions and configurable service wheel where appropriate. It must work even if no Patrol Session exists. Default report:

`{local_tag}{unit}, {patrol_resume} в {city}, район {area} ({map_square}). Экипаж: {crew}, {patrol_moving} на {direction}. Код 4, {patrol_available}.`

If actual direction is unknown, use a grammatical variant without `на {direction}`. Preview and confirm like other reports. Do not implicitly create a Patrol Session or change its timer.

## 4. Stolen-vehicle bulletin parsing, current map highlight, fast `/pt`

**Relevant files:** `pa26_dispatch.lua`, `pa26_hud.lua`, `pa26_map_grid.lua`, `pa26_map_adapter.lua` only if necessary, `pa26_copilot.lua`, `pa26_copilot_ui.lua`, `pa26_wheel.lua`, `pa26_vehicle_settings.lua`, `police_assistant_2026.lua`.

### 4.1. Read actual server stolen-vehicle bulletins

Example observed server message:

`[Внимание] Угнан транспорт Bobcat (Цвет: Бордовый). Последний раз замечен в районе Garcia (Неизвестное место)`

Create a bounded, read-only parser, e.g. `dispatch:observeServerMessage(line, now, gridCfg)`, and connect it to the **existing** `sceneServices.observeMessage`/chat observation path. It must operate whether the chat comes from the native SA:MP handler or the existing CEF bridge; retain deduplication across both sources. Critically, the native `onServerMessage` currently has an early return when certain chat-observation features are off: include the enabled stolen-bulletin observer in that gate, or it will never see messages on some configurations.

- Strip `{RRGGBB}` color codes and normalize whitespace safely.
- Match the actual server announcement, not arbitrary player chat mentioning a stolen car; accept reasonable punctuation/format variation.
- Extract and validate the model (`Bobcat`), color (`Бордовый`), target district (`Garcia`) and optional place (`Неизвестное место`). Bound field lengths; use codec-aware UTF-8 decoding.
- Store latest valid bulletin with arrival time and a configurable ~10-minute TTL, plus explicit clear/override controls.
- Expose `{stolen_model}`, `{stolen_color}`, `{stolen_area}`, `{stolen_square}`, `{stolen_summary}`, `{stolen_location}` to the appropriate template validation and value providers. Missing data gets honest generic wording, not fabricated fields.
- Permit the user to correct the model/district manually in `F4 → Трафик и погоня`. Edits require a fresh preview.
- Replace the unchanged **stock** `stolen_car` text (without overwriting custom text) with:

  `{local_tag}{unit}, {gender:принял|приняла} ориентировку по угону {stolen_summary}, выезжаю на поиск в район {stolen_location}. Моё 10-20: {area} ({map_square}), последний курс {direction}, Код 2.`

  If direction is unknown, omit that clause. Distinguish the bulletin's target district from the officer's own current district. Avoid duplicating county names (`в Флинт-Каунти, район Flint County`) in the output. The template must render even with no active Patrol Session.

### 4.2. Highlight the target on the EXISTING game map grid

Preserve the current `pa26_map_grid.lua` coordinate system, labels, settings, radar and pause-map integration. The user's existing squares are correct for their configured grid; **do not redesign it**.

- Resolve a bulletin district to a map cell only if a verified district position/bounds lookup is available (add a GTA SA zone lookup if necessary). A district name alone is not an exact point; distinguish approximate district-sector highlighting from a precise last-known coordinate.
- Compute the resulting cell with the existing `mapGrid.cell` and **current user grid settings**; do not hard-code a guessed example such as `Garcia = J-9`.
- Add `targetCell`/target label to existing `geometry` and `draw` safely. Highlight on radar and pause-map with an amber/crimson border, distinct from the current-player cell.
- Show something like `УГОН: Garcia [<computed square>]`, only when resolvable, current and enabled; otherwise show the district text without pretending to have a precise map square.
- Handle expiration, changed map settings, unloaded maps, no adapter, unknown district and feature-disabled states cleanly. No new game-memory writes, hooks or alternate map implementation.

### 4.3. Fast, non-modal `/pt` within 50 meters

Add action `fast_pt` (`Быстрый /pt рядом`) to F4 → Traffic and Pursuit, an optional configurable shortcut, and the applicable in-car/on-foot service/wanted wheel slots.

Target resolution, **in this exact priority**, always within 50m and validated for current identity:

1. Current active pursuit/stop driver if available.
2. Explicitly selected player (`workspace.selectedTarget`) if available.
3. Selected vehicle's validated driver.
4. **Closest visible non-colleague player within 50m** — this fallback is intentional and explicitly requested by the user given the server population and `/pt` restrictions.

The server is expected to reject an ineligible `/pt`; do not claim client-side certainty that a person is a criminal. Show nickname, ID, distance and how the target was selected in a fast `Y/N` toast: `Пометить /pt Nick_Name [ID 42]?`.

On `Y`, revalidate player identity/generation, distance and command availability, then issue **only** `/pt <ID>` once, using the normal sending path. No modal wizard and no unrequested `/su` or RP. On `N`, send nothing. If no valid target is present, show a concise failure/manual-ID suggestion rather than guessing beyond 50m. Respect the server's result and avoid automatic retries.

## 5. Stop-report idempotency and recognizing an officer's own manual `10-55` report

**Relevant files:** `pa26_copilot.lua`, `police_assistant_2026.lua`.

The current `C:tick()` clears `stopReportOffered`, `done.stop` and `dismissed.stop` whenever a momentarily stationary target moves by `stationary_delta` (default 0.4m), so the radio report prompt reappears after the stop has already been reported.

- Once an actual start-of-stop report is sent during a specific `10-55`, set `self.done.stop=true`, keep `self.stopReportOffered=true` and never clear them due to minor target motion.
- Reset this state only on a genuinely new incident/stop or the appropriate incident phase transition.
- Detect the local officer's **own** outgoing manual `/r` or `/f` radio line reporting `10-55`/`провожу остановку`, and mark the stop report done for the current stop even if Copilot did not send it.
- Use the existing native/CEF outgoing-command hooks and executor `sent_line` events. A server echo can supplement evidence **only if it belongs to the local officer**. Do not credit another officer's `[R]`/`[F]` message.
- Ignore `10-55` text spoken as commentary, cancellation, a historical situation, a `10-99` completion, or unrelated radio traffic. Do not create a `10-55` phase merely because a chat line contains the digits `10-55`.
- Dismiss any pending start-of-stop offer after recognizing the completed report; do not spam it again. Preserve explicit manual user controls.

## 6. Durable `10-55`, detection of manual `/ud`, completion-before-pursuit `Y/N`

**Relevant files:** `pa26_copilot.lua`, `pa26_copilot_settings.lua`, `pa26_vehicle.lua` only as necessary, `police_assistant_2026.lua`.

This section **replaces** the original older Section 6 and all earlier variants. Implement the following unified behavior, not two competing state machines.

### 6.1. Preserve incident identity and last known stop context

The current `C:tick()` resets on `selected==nil` outside a limited pursuit-retention path, and `finish` is not in `carFree`, causing `Сначала выберите видимую машину` after the stopped driver departs.

- When the active target is valid, preserve `lastCar=model.copy(self.car)` together with a stable incident identity (vehicle `id`/`handle`/model/generation, driver identity if known), initial stop location/area/map square and last trustworthy movement observation.
- When the target becomes unstreamed or is cleared while the same incident remains active, **do not automatically reset** the `10-55`; retain a stale snapshot marked `stale=true` until explicit completion/incident change. Do not extend stale retention across a different player/vehicle ID generation.
- Changing to a genuinely different explicitly selected vehicle should close/reset or explicitly replace the old incident as the existing UX requires, but **transient stream-out is not a new stop**.
- `finish` must be allowed without a currently streamed car (`carFree.finish=true` or equivalent carefully scoped exception). In `C:values`/prepare/validate use the same incident's cached `lastCar` and **stop** area/map square for the stop-completion report; fall back to an honest generic description if missing.
- The existing `C:tick()` early return for `c.stale` must still process completion decisions and cached offers; do not strand the user in a state where `finish` never appears.
- Maintain existing pursuit retention, driver ID collision protection and unrelated phases (`10-66`, `10-57 VICTOR`, `10-57 FOXTROT`). Do not globally make every stale vehicle action available.

### 6.2. Detect a sent `/ud` independent of the Copilot ground window

Add a pure Copilot method such as `C:observeManualCommand(line,source)` and connect it to **both**:

1. the existing outgoing `sceneServices.observeCommand`/`onSendCommand` paths for a manually typed `/ud` (including observable external bind scripts), and
2. the shared executor's **actual `sent_line` event** for the user's PA bindings (PA-owned sends are treated separately by the outgoing command handler).

Never count a demo/preview line. Deduplicate if two hooks see one emission. Recognize `/ud` as a complete command token, case-insensitive, with optional target ID; `/udfoo` and incidental text must not count.

Only register it when:

- the current incident is active `10-55`;
- the officer is on foot;
- the stopped car/driver is within `approach_distance` plus a small tolerance;
- if `/ud <ID>` provides a target and the driver's ID is known, the ID matches that incident's driver; and
- player/vehicle identity and stop generation are current.

Set `self.manualUdDone=true` for this incident. The officer can use a built-in PA binding, a third-party observable binding or manual chat input; **no Copilot ground window is required**. Ordinary chat, `/me`, `/do`, `/s`, `/ticket`, merely standing beside the car, and generic bind execution **do not count as `/ud`**.

Keep `manualUdDone` separate from `done.explain_stop`: sending ID establishes contact, **not proof that the entire explanation/traffic stop is complete**. Existing built-in `explain_stop` continues to work and still counts as an interaction when actually sent. Clear the manual flag only when the incident genuinely changes/finishes.

### 6.3. Ask whether the stop finished — before assuming flight

Add setting `finish_offer=true` (`Предлагать завершение 10-55 после контакта с водителем`). The officer has interacted if `self.manualUdDone==true OR self.done.explain_stop==true`.

If interaction has occurred and either:

- the officer returns to **their cruiser** after being on foot; or
- the stopped vehicle **actually drives away**, supported by observed target movement, not just an increased player-to-target distance or arbitrary stream-out;

show the standard `Y/N` toast:

`10-55 завершена? Доложить 10-99 / Код 4?`

`Y · Доложить` prepares/sends `finish` through the normal executor and closes the stop **only after completion of that send**. `N · Остановка не завершена` records a declined finish and routes to the next decision below. If the officer enters an unrelated vehicle, do not treat that as returning to the cruiser. If the prompt expires or is deferred, retain a safe manual F4 finish option; no repeated nagging.

Default **stock-only** finish template:

`{local_tag}{unit}, 10-99 по остановке {vehicle_description} в районе {stop_area} ({stop_map_square}), {stop_outcome}. Продолжаю патрулирование, Код 4.`

Define `{stop_area}` and `{stop_map_square}` from the saved stop context, with clearly documented fallbacks. Do not claim the officer's current location is where the stop took place after they drive away. `stop_outcome` remains editable.

### 6.4. `N` to finish routes to pursuit only when there was departure/flight

On an explicit `N` to `finish`:

- If the suspect car has already driven away/fled according to reliable incident movement evidence, offer **the existing** `pursuit` action in a *second* toast: `Нарушитель скрылся? Начать 10-57 VICTOR?`.
- If the car is still stationary, leave `10-55` active; do not start a nonsensical chase just because the officer declined closure.
- If no reliable movement can be observed because of stream-out, preserve an explicit choice/manual pursuit path using cached details where defensible; never silently claim a pursuit began or that current target coordinates are known. If pursuit genuinely cannot be established, preserve manual continuation/`lost` handling.
- The transition must work with a stale cached target: update `C:propose`, `C:valid` and offer behavior **for this validated incident transition** rather than blindly making all pursuit actions `carFree`.
- Reuse all existing `10-57 VICTOR` templates, warning counters, driver identity checks, radio TAC logic and related workflow. Do not duplicate pursuit implementation.

If interaction **did not** occur (`manualUdDone` false and `done.explain_stop` false), and the suspect visibly flees, preserve the original direct `pursuit` offer instead of asking if a conversation that never happened was completed.

### 6.5. Offer exclusivity, idempotence and lifecycle

- A pending `finish` offer outranks `pursuit` after interaction. Never show both simultaneously.
- `N` on `finish` is a semantic decision, **not** the generic `Позже` dismissal in the current `C:decide`. The second pursuit offer must be queued only after the first decision closes.
- Do not repeat `finish` on every tick or re-offer it immediately after `N`.
- Do not run `finish` twice, send duplicate `10-99` or lose the stop due to `self.car=nil` after stream-out.
- Keep manual `finish` available through F4 when appropriate, including when a Copilot suggestion was dismissed.
- Do not let a cached old driver/vehicle affect a new incident; clear all finish/pursuit/manual-contact flags at correct lifecycle boundaries.
- If `explain_stop` has already been done through the original ground UI, don't nag the officer with another introduction just because the new window-RP workflow was skipped. Keep manual RP usable throughout.

## 7. Natural speech, a single scrollable list of traffic-stop reasons, and correct legal references

**Relevant files:** `pa26_operational.lua`, `pa26_ground_window.lua`, `pa26_copilot_settings.lua`, `pa26_copilot.lua` and current sanctions/knowledge lookups.

### 7.1. Replace four-per-page buttons with one scrollable list

Currently the reason form displays four entries with `Предыдущая`/`Следующая`. Replace this paging UX with **one scrollable selection list** inside the same F4/ground window. Preserve the current search, selected branch/part, legal details, action buttons and user settings.

- Display frequent traffic reasons at the top by a sensible default ordering: speeding, red light, driving into oncoming lane, parking, junction, registration, insurance, mechanical defect; then other verified relevant stop reasons.
- Show each reason's legal reference (`АК ст. ...`, relevant `УК ...`, Police Manual, or `Без отдельной статьи · беседа`) beside its name.
- If convenient, record actually used recent reasons for stable priority, but do not reorder the list unexpectedly while the user has it open, and do not require a new database merely for sorting.
- Keep one list, scrollbar, keyboard-friendly search, current selection highlighting and enough room for the full selected reason and its editable sentence.
- Use the existing AK/UK/Police Manual source files and sanction mapping. Include relevant legal grounds **only where verified**. Do not map every Criminal Code article to a traffic stop or invent a law from a similar-sounding offense.
- A selected reason is not itself proof of guilt, a fine, or a server-enforced sanction. Preserve manual decision-making.

Add this special reason to `M.stop`:

`id='wrong_way', title='Выезд на встречную полосу · профилактическая беседа', article=''`

It is intentionally available **without a specific article**, with a natural example: `Вы выехали на полосу встречного движения. Я остановил вас, чтобы выяснить обстоятельства.` Do not automatically claim that the driver endangered others or committed a separately codified violation unless supported by the actual facts and source.

### 7.2. Natural, fully editable officer speech

Add a complete-sentence field (`ground_speech`/`stop_speech_line` or equivalent) for the selected stop, initialized from a natural, appropriate example for each existing reason. Examples:

- Speed: `Я остановил вас, поскольку вы превысили установленную скорость движения.`
- Signal: `Я остановил вас, потому что вы проехали на запрещающий сигнал светофора.`
- Junction: `Я остановил вас, чтобы уточнить обстоятельства проезда перекрёстка.`
- Parking: `Причина остановки — нарушение правил остановки или парковки.`
- Wrong-way: `Вы выехали на встречную полосу. Давайте уточним, что произошло.`
- Registration: `Я остановил вас для уточнения регистрационных данных транспортного средства.`
- Sobriety check: `Манера управления вызвала у меня вопросы. Мне необходимо уточнить обстоятельства и проверить документы.`
- Bulletin: `Ваш автомобиль похож на транспорт из поступившей ориентировки. Мне нужно уточнить данные.`
- Custom: use the user's complete custom wording.

Apply the officer's configured grammatical gender (`Я остановил`/`Я остановила`) when generating a default. Never modify a sentence the officer manually edited.

In `pa26_ground_window.lua`, immediately after choosing a reason/branch, show a multiline field titled `Что вы скажете водителю? (можно изменить своими словами)`, populated with a **complete sentence**. The final `explain_stop` sends exactly this validated edited line; do not prepend `Вы остановлены: {причина}`, duplicate the beginning, or append `Основание: ` followed by an empty article. Preserve introduction, optional `/ud`, rights and document-request settings.

Keep this per-situation draft separate from persistent stock defaults. Ensure `C:prepare`, `C:previewTemplate`, template validation and navigation/ground-context snapshots all use the same effective text. Rebuild preview after edits and respect configured chat channel (`/s` or ordinary speech). Update unchanged stock templates only; preserve user customizations.

## 8. Event-driven traffic-stop window RP — NO 7-second timer and NO forced knock

**Relevant files:** `pa26_copilot.lua`, `pa26_copilot_settings.lua`, `pa26_ground_window.lua`, `police_assistant_2026.lua`; change `pa26_executor.lua` only if truly required by existing sending behavior.

### 8.1. Explicitly REMOVE the earlier timed proposal

Do **not** implement the old `approach_window_delay_ms=7000`, a `wait` step for walking to the driver's door, or automatic `/me постучался` after a timer. Do not relax executor safety checks to support a wait step that is no longer required.

The officer should move freely; Copilot observes actual proximity and offers the next RP action.

### 8.2. Stage A — taillight/flashlight inspection remains

Keep the existing officer-confirmed `approach` action near the stopped car:

- Day: `/me подходя к автомобилю, коснулся ладонью задней левой фары, оставив отпечаток, и осмотрел салон.` (gender-aware stock variation)
- Night: retain the existing flashlight variant.
- `/do Мог ли {my_firstname} увидеть оружие или запрещённые предметы в салоне автомобиля?`
- Optional existing `/n Ответьте в /do на мой вопрос (например: /do В салоне оружия нет.)`

Mark `done.approach=true` when the actual action is completed by the executor. No automatic follow-up knock, no timer, no assumption that a driver answered the cabin question.

### 8.3. Stage B — on-foot proximity to the driver triggers ONE window-question toast

After inspection, detect the officer approaching the **current stop driver** on foot. Use current driver/player observations and a configurable `window_interaction_distance` (reasonable default around 4m), with identity and current stop validation. The officer must be on foot, `phase=='10-55'`, within the configured distance and not in a pending incompatible action. If side-of-vehicle geometry is unavailable, a validated near-driver distance is sufficient; do not fabricate exact window-side detection.

Show once:

`Вы у окна водителя · Спросить, открыто ли окно?` — `Y / N`.

`Y` prepares and sends, with the normal executor and safe intervals:

1. `/do Окно водительской двери открыто?`
2. `/n Ответьте в /do: например, /do Окно открыто. или /do Окно закрыто.`

`N` sends nothing, dismisses this suggestion for the current attempt and permits entirely manual interaction. Do not nag every tick.

### 8.4. Stage C — recognize the actual driver's server chat response

**Known, expected format on this server:** RP messages appear with the speaker's nickname at the end, e.g.:

`Окно открыто. ( Nick_Name )`

The user expects Copilot to use the **existing** chat-reading capabilities. Extend the existing `sceneServices.observeMessage` (native SA:MP + CEF bridge, deduplicated) with a bounded, pure window-response observer. Once the window question was **actually sent**, enter `awaitingWindowReply` with the current incident ID, driver ID/name/generation and time.

While this state is active:

- Strip server color codes and normalize Unicode/CP1251 conversion, spaces, punctuation and letter case.
- Parse the **trailing** speaker identification such as `( Nick_Name )`, `(Nick_Name)` or the verified actual server variant; resolve `Nick_Name` against the captured current driver's nickname. Preserve underscore conventions and case-insensitive comparison.
- Accept only an answer attributable to **that specific current driver** in the current `10-55`. Never accept a nearby bystander's identical `/do`, officer's own echo or a response from an old player who inherited the same ID.
- An unambiguous `Окно открыто`, `Да`, `Да, открыто`, `Открыто` from that driver means **open**.
- An unambiguous `Окно закрыто`, `Нет`, `Нет, закрыто`, `Закрыто` from that driver means **closed**.
- Interpret a bare `Да`/`Нет` only because the current pending question is specifically `Окно открыто?`. Do not accept `нет` buried in unrelated text (`В салоне оружия нет`) or a message containing conflicting terms.
- Ignore messages received **before** the question is sent, ambiguous formats, wrong nicknames and stale stop identities.
- Stop waiting after a valid interpretation; deduplicate native/CEF copies of the same chat line. Do not repeat the question/toast in a loop.

**If the actual server format does not expose a trustworthy driver nickname**, do not silently infer that the nearest player's `/do` is the answer. Offer a manual fallback (`Водитель ответил: Открыто / Закрыто / Ответа нет`) and leave the scene interactive. Inspect the project's existing chat parsing conventions and add test fixtures for the exact example `Окно открыто. ( Nick_Name )`.

### 8.5. Branch when OPEN

On a valid open answer, set `windowReply='open'`, `awaitingWindowReply=false`, then offer the **existing Copilot ground navigation**:

`Окно открыто · Представиться и назвать причину 10-55?` — `Y / N`.

`Y` opens the usual `explain_stop` ground window, now with the **single scrollable reasons list** and **editable natural speech** from Section 7. This remains a confirmed officer action; do not auto-send introduction, `/ud`, speech or fine. `N` lets the officer keep chatting manually.

### 8.6. Branch when CLOSED — explicit knock, then OPTIONAL normal reason offer

On a valid closed answer, set `windowReply='closed'`, `awaitingWindowReply=false`, then show:

`Окно закрыто · Постучаться в водительское окно?` — `Y / N`.

- `Y` sends `/me постучался в водительское окно.` **once**; never send it automatically from proximity, elapsed time or the driver's reply alone.
- `N` sends nothing and leaves manual interaction available.
- After the confirmed knock has been sent, the officer must **not** be trapped in an endless wait for the window to open. The Copilot may immediately offer the familiar `Представиться и назвать причину 10-55?` toast as a voluntary next action, while continuing to recognize a later explicit `Окно открыто. ( Nick_Name )` response.
- Never assert that the window is physically open without a corresponding response/confirmation. The reason/introduction form itself can be offered as a next action after knocking; the officer decides whether speaking is appropriate. No duplicate introduction offer if one is already pending or the officer has already used manual `/ud`.
- A later valid open answer updates the window state; do not repeat knock automatically.

### 8.7. No reply, missing target, changed scene, and manual overrides

- No answer is a legitimate outcome. Never auto-choose open/closed because a timeout elapsed.
- Show an unobtrusive `Ожидается ответ водителя` status; allow `Повторить вопрос`, `Открыто`, `Закрыто`, `Пропустить` as explicit controls where needed.
- If the driver changes, moves away, leaves stream, or the selected stop ends, stop parsing further chat as their answer; avoid ID reuse contamination.
- A driver leaving after an interaction must use the stop-completion/pursuit flow in Section 6, not restart the window process.
- If the officer manually sends `/ud`, retain Section 6's manual-contact recognition and suppress duplicate mandatory introduction offers; never require clicking every window step to complete `10-55`.
- Keep all features configurable and consistent with the existing toast/ground input, not a second independent RP bot.

## 9. Correct LINCOLN (`1-L-1`) and ADAM (`1-A-1`) determination in preview and actual reports

**Relevant files:** `pa26_patrol_settings.lua`, `pa26_patrol_session.lua`, `pa26_colleagues.lua`, `police_assistant_2026.lua` and live F4 preview consumers.

Existing `crewCount(state,crew)` uses `c.patrolOccupants` in a vehicle and can return 1 even when a legitimate, user-selected partner is sitting in the same cruiser but was not recognized by the player scan. `patrolSession.readScene` also consults only saved crew under certain conditions, and a line-of-sight check can fail for a player inside the car roof. Correct the observations rather than unconditionally assuming the planned crew is present.

Requirements:

1. **Distinguish planned roster from observed physical crew.** A partner checked in `Состав следующего патруля` is a planned teammate, but is **not automatically aboard the car**.
2. Improve recognition of real connected, non-NPC players in the same vehicle using char-handle/vehicle checks, correct nickname decoding and selected contact/crew identity. Do not reject genuine in-car teammates just because a camera raycast hits the vehicle roof.
3. Use unsaved `studio.patrolSessionDraft.crew` where appropriate for **preview**, without requiring a saved/active Patrol Session or enabled timer.
4. For real sent reports, use actual verified on-board teammate count and identity. **Never simply `return math.max(roster,patrolOccupants)`** if roster includes an absent/offline teammate.
5. With one officer physically in the cruiser, the default automatic unit is LINCOLN (`1-L-1` for LSPS); with a verified teammate aboard, it is ADAM (`1-A-1`). Preserve station prefix, user-configured unit number and explicit manual callsign override.
6. Correct singular/plural patrol grammar (`начинаю` / `начинаем`, `двигаюсь` / `двигаемся`, `доступен` / `доступны`) in F4 preview and exact sent lines.
7. Recompute preview immediately when the user changes crew selections or when real crew observation changes. Do not require starting the formal Patrol Session.
8. Do not classify random passengers or NPCs as police teammates merely because they occupy a seat. Preserve existing positive colleague/contact checks.

## 10. Required verification: automated tests AND live-game limitations

Create focused regression tests using the actual project test conventions if present; the supplied release ZIP contains verification documentation but does **not** itself include a runnable tests folder. If a suite/toolchain is unavailable, say exactly which checks could not be run. Do not invent a test count or claim 100% verification without evidence.

**Core tests:**

1. F4 Patrol traffic button navigates correctly, without unexpectedly opening F9; F9 counterpart also works.
2. Stationary car reports last real motion direction, never `На месте`; unknown motion is handled grammatically.
3. F4 `dispatch_911`, stolen, business, gas, bank, all 15 nested follow-up reports and `patrol_continue` are available with `patrolSession.data.active=nil` and `patrol_session.enabled=false` when ordinary on-duty/radio requirements hold.
4. Every F4 report opens the same clear confirmation preview with correct `Юнит`, `Экипаж`, place, available context and exact final command; `YES` sends once, `NO` sends nothing and exposes the edit/cancel choice; editing forces a new preview.
5. Radio-only follow-ups do **not** send extra `/me`/`/do`, while primary dispatch actions retain their configured RP.
6. Own stale or incomplete values never create an invented partner, incident, square or movement direction.
7. Stolen bulletin `Bobcat / Бордовый / Garcia` parses from native chat and CEF bridge, deduplicates, honors expiration and manual override; target and current officer locations remain distinct.
8. Existing map grid remains unchanged and target highlight uses its validated user-configured cell; unknown district never gets a guessed precise square.
9. Fast `/pt` resolves all four priority levels including closest non-colleague fallback (50m), previews nickname/ID, revalidates identity on `Y`, sends only once and never silently sends `/su`.
10. Jitter of the stopped car by 0.4m does not re-offer a completed 10-55 report; current officer's own outbound report counts, other players' radio traffic does not.
11. Manual `/ud <driverId>` through chat and through a PA binding marks `manualUdDone`; demo and unrelated commands do not; external observable bind can be recognized; double-hook observation is deduplicated.
12. `/ud` to a different player, in a cruiser or outside the stop's interaction range does not mark contact.
13. After `/ud`, officer returns to their own cruiser: show `10-55 завершена?` exactly once; `Y` executes 10-99/Code 4 even when the stopped car is no longer streamed.
14. After `/ud`, target actually departs: offer finish **before** pursuit; `N` offers 10-57 if flight is supported; `N` while the car is still stationary keeps 10-55 active.
15. Without `/ud`/completed explanation, target flees: offer original pursuit directly. Stale stream-out alone is not falsely equated to fleeing.
16. Cached last car and stop location survive stream-out without adopting a new target using a recycled ID; manual finish remains possible.
17. Only one finish/pursuit toast at a time, no infinite prompt loops, no duplicate 10-99.
18. Ground form displays all reasons in a single scrollable list, search and article/branch details still work, `wrong_way` has no fabricated article, custom speech survives preview and sends verbatim.
19. Approach at rear lamp sends existing inspection/question, with no seven-second wait and no automatic knock.
20. Moving near the correct driver after approach offers the window question once. Merely standing at the rear or interacting with a different vehicle does not.
21. The response `Окно открыто. ( Nick_Name )` from the captured driver opens the introduction/reason offer; `Да` works in the pending-question context. `Окно закрыто. ( Nick_Name )`/`Нет` offers the **officer-confirmed** knock.
22. Another player's `Окно открыто`, old driver name, a conflicting answer, own echo and unrelated cabin `/do ... нет` do not change the window state.
23. After `Y` on knock, `/me постучался` sends once and Copilot offers optional continued introduction without requiring another automatic timer. No answer/manual override never deadlocks.
24. A manually sent `/ud` does not force completing every ground-window step and remains compatible with finish-vs-pursuit.
25. Crew planned-but-absent remains LINCOLN for real reports; verified partner aboard gives ADAM and correct plural grammar; UI preview reacts to draft changes and current physical crew.
26. Existing user data, customized templates, wheels, other Copilot phases, automatic updater SHA-256 and old report actions remain intact.

Where available, execute Lua/LuaJIT syntax and unit checks, CEF/JS checks, PowerShell/setup checks and native 32-bit ImGui compatibility checks **without** asserting those suites exist if they are not present. Explain which scenarios require manual in-game verification on the user's actual SA:MP/CEF client and server, especially server `/do` nickname formatting and external binder hooks.

## 11. Implementation sequence and deliverables

Implement in three internally verified milestones (all belonging to the same requested v0.43.2 release):

1. **Stability first:** F4 navigation; true last movement direction; stop-report idempotence; manual `/ud`; cached incidents and finish/pursuit decisions; actual-crew LINCOLN/ADAM.
2. **Interaction and radio UX:** session-free F4 report confirmation; five groups of radio-only follow-up buttons; patrol-continue report; scrollable legal grounds; natural editable speech; event-driven window RP.
3. **Enhanced observations:** stolen-vehicle bulletin parser; existing-map target highlight; fast `/pt`; integration and regression checks.

Run relevant validations after each milestone. Keep backwards compatibility for existing settings. Avoid broad rewrites of unrelated modules. Show concise interim implementation notes if a design assumption is blocked by the actual game/server APIs, then apply the safest workable fallback rather than inventing events.

**Deliver at the end:**

- The completed, updated project source at version **0.43.2**.
- A concise changelog and migration/compatibility notes.
- A file-by-file implementation summary.
- Actual test commands/results and explicitly untested in-game scenarios.
- An explanation of any limitation on detecting external `/ud` or associating server `/do` with the current driver's nickname.
- Explicit confirmation that the updater file checksum is unchanged and personal settings/templates remain preserved.

**Final product principle:** PA is an **officer-controlled assistant**, not a binderbot. It observes the patrol scene, detects reliable server/player context, offers the next appropriate action and waits for informed `Y/N` confirmation. It never fabricates legal grounds, location, driver responses or police reports, and it does not require a formal Patrol Session merely to use F4 radio controls.


