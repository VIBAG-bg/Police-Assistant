# Предоставленное задание Copilot 0.41

Исходный текст пользователя. Основа реализации обновлена до 0.40.3; уточнения и фактические проверки перечислены в [отчёте](COPILOT-041-VERIFICATION.md). Этот документ не является официальным источником правил.

Держи полный, детально проработанный **мега-промпт на техническом английском языке** специально для Кодекса!

Все архитектурные инструкции, логика автоматов состояний, названия функций и алгоритмы написаны на компактном техническом английском (это сэкономит тебе максимум токенов лимита и ускорит парсинг задачи моделью), а все внутриигровые тексты, кнопки интерфейса и RP-отыгровки оставлены внутри кавычек на чистом русском, чтобы Кодекс перенёс их в код побайтно без кривого автоперевода.

Копируй весь блок ниже и отправляй Кодексу:

```markdown
# MEGA-PROMPT FOR CODEX: "PA Copilot" Architecture (Tactical 10-55 / 10-66 / 10-57 Console, Colleague Radar, Streamlined Vehicle Wanted Chain, Cadet Rule Guardrails, and Smart F8 Archiver) on top of PA 0.40.0

You are working on the **Police Assistant v0.40.0** codebase (branch `ux-0.40.0` -> target release `0.41.0`).
Your objective is to implement the **PA Copilot** system: an intelligent, state-driven tactical assistant that guides officers (from first-day cadets to supervisors) through traffic stops (`10-55`), high-risk stops (`10-66`), vehicle/foot pursuits (`10-57 VICTOR / FOXTROT`), colleague coordination, rule compliance, and automated screenshot evidence management.

---

## SECTION 0. STRICT ARCHITECTURAL INVARIANTS (READ FIRST)

1. **100% Data & Schema Preservation:**
   - Preserve all 1,175 existing configuration leaf paths (`CONFIG_LEAF_INDEX.csv`) and full backwards compatibility with `police_assistant_2026.ini`, `police_assistant_2026_binds.json`, `police_assistant_2026_notes.json`, and `police_assistant_2026_settings.json`.
   - Any new settings fields must have safe defaults in `defaults()` and non-destructive migration in `validate()` so existing user profiles load seamlessly.
   - **DO NOT** modify `moonloader/lib/pa26_update_platform.lua` (its SHA-256 `995b131aa0250b7ea407915ad7d109de71a8e43cec088603bc99cc489e60565f` must remain byte-identical).
   - **DO NOT** overwrite or alter the user's personal bind library (`police_assistant_2026_binds.json`) or the 6 default binds in `pa26_core.lua` / `pa26_bindings.lua`.
2. **MoonLoader / mimgui Thread & Execution Safety:**
   - Never call native GTA / SA:MP APIs or send chat/RPC packets from inside `mimgui` render callbacks (`OnFrame`).
   - All world observations (`getAllChars`, `getAllVehicles`, `getCharModel`, `getDriverOfCar`, `getNumberOfPassengers`, `getCurrentCharWeapon`, `isLineOfSightClear`, `processLineOfSight`, WinAPI directory scans) must execute strictly inside `main()` (`updateGame()`), passing plain Lua state tables to UI renderers.
   - Never send chat lines or server commands without explicit user action (clicking a button or confirming `Y / ДА`), and always route execution through `workspace.executor` / `runtime`.
3. **UI Layout & Small-Screen Compatibility (`640×480` .. `2560×1440`):**
   - Use only verified `mimgui` APIs present in this repository (e.g., paired `PushItemWidth` / `PopItemWidth`).
   - Confirmation modals (`pa26_menu.confirmationLayout`) must use pagination (`Назад` / `Далее`) rather than inner scrollbars and must pass x86 headless layout checks at `640×480`, `1366×768`, `1920×1080`, and `2560×1440`.

---

## SECTION 1. FIVE VERIFIED TECHNICAL REFINEMENTS FROM THE 0.40.0 REVIEW (APPLY FIRST IF NOT YET MERGED)

1. **Shared `alerts.on_duty` Toggle in the Weapons Tab (`moonloader/lib/pa26_studio.lua`):**
   - In `Studio:drawWeapons`, add a shared checkbox at the top bound to `self.lib.alerts.on_duty`:
     - Label: `'На службе · разрешить автофункции PA (оружие, тайзер и рация)##weapons-on-duty'`
     - Explanatory note: `'Разрешает автоматические отыгровки и напоминания PA. Не заменяет серверный выход на смену.'`
   - Update only `alerts.on_duty` while preserving all other `alerts` fields, `alerts.patrol`, and any unsaved edits in `self.alertDraft` (sync `self.alertDraft.on_duty` if `self.alertDraft` is active).
2. **Coordinate Space Fix & Regression Test (`police_assistant_2026.lua`, `fixture.lua`, `test_targeting.lua`):**
   - `getScreenResolution()`, `convert3DCoordsToScreenEx(x, y, z, true, true)`, `getCursorPos()`, and `imgui.GetIO().DisplaySize` all operate in window pixel coordinates, whereas `convertWindowScreenCoordsToGameScreenCoords` converts window pixels into GTA SA's `640×448` virtual canvas.
   - In `acquireTarget` (`police_assistant_2026.lua`): pass `wx, wy` from `convert3DCoordsToScreenEx` directly to `core.cameraScore(wx, wy, width, height, ...)` without calling `convertWindowScreenCoordsToGameScreenCoords`. Remove `'convertWindowScreenCoordsToGameScreenCoords'` from the required-API array in `acquireTarget`.
   - In `updateGame` (`police_assistant_2026.lua`): pass `x, y` from `getCursorPos()` directly to `hud:setPointer(x, y, ...)` without converting to `640×448`.
   - In `tests/support/fixture.lua`: update the mock `convertWindowScreenCoordsToGameScreenCoords` to perform actual `640×448` scaling (`return x * 640 / s.io.DisplaySize.x, y * 448 / s.io.DisplaySize.y`) and add regression tests in `tests/test_targeting.lua` at `1280×720` and `1920×1080`.
3. **Single-Anchor Camera / Crosshair Scoring (`pa26_core.lua`, `police_assistant_2026.lua`):**
   - Do not use two simultaneous centers. Extend `M.cameraScore(x, y, width, height, anchorX, anchorY)` to evaluate a single anchor point per frame:
     - Default anchor: screen center `(width * 0.5, height * 0.5)`.
     - Third-person weapon aiming anchor: `(width * 0.53, height * 0.40)`, passed **only** when the player is on foot (`inVehicle == false`) and actively holding third-person aim (`aimControl == true` with a fresh third-person aim `camMode` `53` or `55`).
4. **Vehicle Occupant Visibility via Obstacle Ownership (`police_assistant_2026.lua`):**
   - In `bodyPointVisible(cx, cy, cz, x, y, z, inVehicle, ped)`:
     1. If `isLineOfSightClear(cx, cy, cz, x, y, z, true, true, false, true, false) == true`, return `true`.
     2. If `not inVehicle`, return `false`.
     3. Call `local hit, colPoint = optionalRead('processLineOfSight', cx, cy, cz, x, y, z, true, true, false, true, true, true, false, false)`.
     4. If `hit == false`, return `true`.
     5. If `hit == true` and `ped` is provided and `type(colPoint) == 'table'` and `colPoint.entityType == 2` and `core.finite(colPoint.entity)` and `type(_G.getVehiclePointerHandle) == 'function'` and `type(_G.storeCarCharIsInNoSave) == 'function'`:
        - Check `optionalRead('getVehiclePointerHandle', colPoint.entity) == optionalRead('storeCarCharIsInNoSave', ped)` (proving the first vehicle hit by the ray from the camera is the target occupant's own vehicle, not an intervening car) AND `optionalRead('isLineOfSightClear', cx, cy, cz, x, y, z, true, false, false, true, false) == true` (proving no walls, buildings, or objects block the ray). Return `true` only if both hold; otherwise `false`.
     - Add unit tests for: (a) own vehicle hit with clear world LOS -> selectable; (b) another vehicle hit in front -> rejected; (c) own vehicle hit but wall blocking -> rejected.
5. **Custom Launcher Vehicle Model IDs (`400..65535` `uint16_t` Contract) & Keep SA:MP Vehicle ID `1..1999`:**
   - Keep SA:MP vehicle ID validation at `id >= 1 and id < 2000` (`1..1999`).
   - Allow `model >= 400 and model <= 65535` (`uint16_t`) in `pa26_vehicle_world.lua`, `pa26_vehicle_settings.lua`, and `pa26_vehicle_ui.lua` for valid streamed vehicle handles, falling back to `cfg.model_aliases[tostring(c.model_id)] or cfg.unknown_model` when `c.model_name` is `nil`. Update `tests/test_vehicle_names.lua`.

---

## SECTION 2. COLLEAGUE RADAR (16 VERIFIED PD SKINS + `/r`, `/f`, `/find` CACHE), CRUISER ROLE (`ADAM` / `LINCOLN`), AND AUTO-CALLSIGN

Create `moonloader/lib/pa26_colleagues.lua` (and wire it into `main()` / `patrolSession` / `vehicle`):

1. **Server-Verified PD Uniform Skin Catalog (16 Skin IDs) & PD Vehicle Models:**
   ```lua
   M.pdSkins = {
       [300] = {role = 'cadet',      station = 'LSPS', label = 'Кадет LSPS'},
       [301] = {role = 'cadet',      station = 'SFPS', label = 'Кадет SFPS'},
       [267] = {role = 'cadet',      station = 'LVPS', label = 'Кадет LVPS'},
       [280] = {role = 'officer',    station = 'LSPS', label = 'Офицер LSPS'},
       [281] = {role = 'officer',    station = 'SFPS', label = 'Офицер SFPS'},
       [282] = {role = 'officer',    station = 'LVPS', label = 'Офицер LVPS'},
       [283] = {role = 'supervisor', station = 'EPD',  label = 'Старший офицер'},
       [284] = {role = 'officer',    station = 'EPD',  label = 'Мотобат / Патруль'},
       [285] = {role = 'swat',       station = 'SWAT', label = 'Боец SWAT'},
       [288] = {role = 'supervisor', station = 'EPD',  label = 'Командование'},
       [295] = {role = 'detective',  station = 'EPD',  label = 'Детектив / Штаб'},
       [211] = {role = 'officer',    station = 'EPD',  label = 'Сотрудница ПД'},
       [265] = {role = 'officer',    station = 'EPD',  label = 'Офицер ПД'},
       [266] = {role = 'officer',    station = 'EPD',  label = 'Офицер ПД'},
       [306] = {role = 'officer',    station = 'EPD',  label = 'Офицер ПД'},
       [307] = {role = 'officer',    station = 'EPD',  label = 'Офицер ПД'},
   }
   M.pdVehicles = {[596]=true, [597]=true, [598]=true, [599]=true, [490]=true, [528]=true, [427]=true}

```

2. **Passive Colleague Discovery & Nearby Officer Scan (`main()` every `500 ms`):**
* In `observeMessage`: passively record nicknames seen in incoming departmental radio lines (`/r`, `/f`) or `/find` output into a session-scoped table `knownColleagues[nick:lower()] = true` (cleared on session reset).
* Every `500 ms` in `main()`, inspect already-streamed peds/vehicles within `50 m`:
* `nearbyOfficers`: connected, non-dead, non-NPC players within `50 m` whose `getCharModel(ped)` is in `M.pdSkins` OR whose nickname is in `knownColleagues` or `library.partners`. Store `{id, name, skin, role_label, distance}`.
* `nearbyCruisers`: count of streamed vehicles within `50 m` with `M.pdVehicles[model] == true` (excluding empty wrecks if unoccupied, or counting active units).
* `ownCruiserRole`: when the local player is inside a vehicle (`ownCar`):
* `isDriver = (optionalRead('getDriverOfCar', ownCar) == PLAYER_PED)`
* `cruiserOccupants = 1 + math.max(0, tonumber(optionalRead('getNumberOfPassengers', ownCar)) or 0)`
* If `cruiserOccupants >= 2`: unit mode is `'ADAM'`. If `isDriver` -> role is `'driver'` (`'Водитель ADAM'`), else -> `'navigator'` (`'Штурман-координатор ADAM'`).
* If `cruiserOccupants == 1`: unit mode is `'LINCOLN'`, role is `'solo'` (`'Одиночный LINCOLN'`).






3. **Out-of-the-Box Readiness & Smart Auto-Callsign (`{unit}`, `{station}`, `{crew}`):**
* In `pa26_vehicle_settings.defaults()`: set `enabled = true`, `megaphone_enabled = true`, `require_patrol = false` for fresh defaults (while respecting explicit booleans in saved profiles) so officers can use traffic stops and pursuits immediately without starting a formal Patrol Session first.
* In `pa26_vehicle.lua:values(state, c)`:
* If `out.unit` is empty, use `profile.callsign`; if that is also empty, auto-generate an EPD Manual-compliant callsign:
* Station prefix: `'1'` for LSPS, `'2'` for SFPS (default), `'3'` for LVPS (inferred from `profile.department` or local player's skin).
* Unit letter: `'DAVID-1'` if local skin is `285`; `'<station>-A-1'` if `cruiserOccupants >= 2` or patrol session has crew; otherwise `'<station>-L-1'`.


* If `out.station` is empty, fallback to `profile.department ~= '' and profile.department or 'SFPS'`.
* If `out.crew` is empty, fallback to `profile.name ~= '' and profile.name or state.my_name or 'Офицер'`.





---

## SECTION 3. RICH VEHICLE SENSORS & COMPACT TACTICAL CONSOLE (`10-55 / 10-66 / 10-57`)

1. **Extended Vehicle Observation (`pa26_vehicle_world.lua`, `pa26_vehicle.lua`, `pa26_vehicle_settings.lua`):**
* In `pa26_vehicle_world.lua`: for each scanned/resolved vehicle, read (in `main()`):
* `driver_ped = read('getDriverOfCar', handle)`
* `driver_id`, `driver_name` (via `sampGetPlayerIdByCharHandle` / `sampGetPlayerNickname` when `driver_ped` is a valid connected player).
* `passengers = tonumber(read('getNumberOfPassengers', handle)) or 0`
* `occupants = (core.finite(driver_ped) and read('doesCharExist', driver_ped) == true and 1 or 0) + math.max(0, passengers)`
* `armed = (core.finite(driver_ped) and (tonumber(read('getCurrentCharWeapon', driver_ped)) or 0) >= 22) or false`


* In `pa26_vehicle.lua:M.describe(c, cfg, gender)`:
* Populate and register in `pa26_vehicle_settings.M.variables` & `M.vehicleFields`:
* `{occupants}` = `tostring(c.occupants or 1)`
* `{occupants_text}` = `({[0]='салон пуст', [1]='внутри один', [2]='внутри двое', [3]='внутри трое', [4]='внутри четверо'})[c.occupants or 1] or ('внутри ' .. tostring(c.occupants) .. ' чел.')`
* `{driver_id}` = `c.driver_id and tostring(c.driver_id) or ''`
* `{driver_name}` = `c.driver_name and c.driver_name:gsub('_', ' ') or 'Водитель'`
* `{vehicle_plate}` = `(cfg.select_plate and cfg.select_plate ~= '') and cfg.select_plate or string.format('SA-%03d', c.id)`
* `{tac}` = `cfg.tac_channel or 'TAC 1'` (configurable in vehicle settings: `'TAC 1'`, `'TAC 2'`, `'TAC 3'`)
* `{armed_text}` = `(c.armed or cfg.pursuit_armed) and ' Подозреваемые вооружены!' or ''`
* `{stop_outcome}` = `cfg.stop_outcome or 'проведена беседа'` (options: `'проведена беседа'`, `'выписан штраф'`, `'подозреваемый задержан'`, `'Код 4 АДАМ, подозреваемый потерян'`).






2. **Non-Intrusive Tactical Console (`F4` / `Alt + 7` / `Alt + 8`):**
* In `police_assistant_2026.lua` (around line 2545): pressing `select_shortcut` (`Alt + 7`) or `pursuit_shortcut` (`Alt + 8`) must **NOT** force-open the large `F9` main window (`openWorkspace('partners')`), which blocks the driver's view during a chase.
* Instead, `select_shortcut` (`Alt + 7`) selects the nearest vehicle in front (`vehicle:selectNearest()`) and opens the compact Assist window (`studioCallbacks.openAssist('traffic')`) or triggers the immediate tactical confirmation modal/toast.
* In `pa26_assist_ui.lua`: add `'traffic'` (`'Трафик и погоня'`) as the primary tab of the compact `F4` window, featuring:
* **Live Target Banner:** `Sultan [Чёрный] · ID 142 · Гос. номер: SA-142 · Салон: внутри двое · Водитель: ID 37 · 14 м · Статус: 10-55` (with a red `'Повышенный риск · рекомендуется 10-66'` badge if `c.armed` or after a pursuit).
* **Crew & Colleague Status Bar:** `'Маркировка: 2-A-1 · Роль: Водитель ADAM · Сотрудников ПД рядом: 2 · Экипажей: 2'`.
* **Tactical Controls:** quick selectors for `TAC 1 / 2 / 3`, `[ ] Подозреваемые вооружены`, and outcome selector (`Беседа / Штраф / Задержан / CODE 4 ADAM`).
* **One-Click Phase Actions:**
1. `'10-55 · Мегафон: остановиться у обочины'` (`megaphone_stop`)
2. `'10-55 · Доклад в рацию о проведении остановки'` (`traffic_stop`)
3. `'10-55 · Подойти к фаре и осмотреть салон'` (`approach`)
4. `'10-66 · Доклад CODE 3 и запрос экипажей'` (`high_risk_stop`)
5. `'10-66 · Мегафон: выбросить ключи и выйти'` (`megaphone_1066`)
6. `'10-57 VICTOR · Начать погоню (Доклад + Розыск 8.1 + /pt)'` (`pursuit`)
7. `'10-57 FOXTROT · Пешая погоня'` (`pursuit_foot`)
8. `'Завершить ситуацию (доклад по выбранному итогу)'` (`finish`)







---

## SECTION 4. INTELLIGENT COPILOT STATE MACHINE & CONTEXTUAL `Y / N` TOASTS (`pa26_vehicle.lua`)

Implement automatic scene transition detection inside `Vehicle:tick(state, now)` (in `main()`) and expose contextual toast candidates via `Vehicle:candidates()` wired into `notifications:tick(...)` in `police_assistant_2026.lua`:

### 4.1. Proper `10-55` Sequence & Stationary Stop Detector

1. Per EPD Manual §110 & §230, a traffic stop begins with a **megaphone command (`/m`)** to pull over, followed by a radio report **after** the vehicle stops:
* Default `traffic_stop_template`:
`'{local_tag}{unit}, провожу остановку {vehicle_description} в районе {area} ({map_square}), {occupants_text}, Код 4.'`
* Default `finish_template`:
`'{local_tag}{unit}, заканчиваю проведение остановки {vehicle_description} в районе {area}, {stop_outcome}, продолжаю патрулирование. Код 4.'`


2. **Stationary Stop Detector:** when `self.phase == '10-55'`, `not self.stopReportOffered`, the officer's cruiser is stationary (`self.directionValue == cfg.stationary`), and the selected target vehicle is within `25 m` and stationary (moved `< 0.4 m` over `1500 ms`):
* Emit a `notifications` candidate (`owner = 'vehicle'`, `mode = 'confirm'`, `yes = 'Доложить (Y)'`, `no = 'Позже (N)'`):
* Title: `'Машина остановилась · Доложить о 10-55?'`
* Body: preview of `traffic_stop_template`.
* Accepting (`Y`) queues the `traffic_stop` radio report through `executor` and marks `self.stopReportOffered = true`.


* **ADAM Crew Filter:** if `state.ownCruiserRole == 'driver'` and `cfg.adam_driver_mute_radio == true` (default `true`), suppress automatic radio-report toasts for the driver so the passenger navigator handles radio coordination undisturbed (the driver still gets megaphone and `/pt` actions).



### 4.2. Unauthorized Driver Exit Detector during `10-55` (Smart `/m` vs `/s` Channel Switch + Escalation Fork)

Track whether the selected vehicle had a driver (`self.hadDriver = true`, `self.lastDriverId = c.driver_id`, `self.lastDriverPed = c.driver_ped`).
If `self.phase == '10-55'` and the driver exits the vehicle (`c.occupants == 0` or `c.driver_ped == nil`):

1. **Immediate Return-to-Vehicle Order (Smart `/m` vs `/s` selection based on `state.inVehicle`):**
* If the officer is **inside a vehicle (`state.inVehicle == true`)**, offer via `/m`:
`'/m Водитель автомобиля ' .. model .. ', немедленно вернитесь в салон, заглушите двигатель и держите руки на руле!'`
* If the officer is **already on foot (`state.inVehicle == false`)**, `/m` is blocked by the server! Automatically switch the offered command to shout **`/s`**:
`'/s Немедленно вернитесь в салон автомобиля и держите руки на виду! При неподчинении будет применена сила!'`


2. **Escalation Fork if the Exited Driver Does Not Return:**
Inspect the exited `lastDriverPed` in `main()`:
* **Branch A — Foot Pursuit (`10-57 FOXTROT`):** if the exited driver moves away (`distance > 12 m`) and is unarmed (`weapon < 22`), automatically transition/offer **`10-57 FOXTROT`** (`Y / N`):
* Radio report: `'{local_tag}{unit}, подозреваемый покинул {model}, веду пешую погоню 10-57 FOXTROT в районе {area} ({map_square}), направление: {direction}, {tac}, Код 3!'`
* Followed by the Step-2 offer: fast wanted `8.1` (`/su {driver_id} 8 1`) + `/pt {driver_id}` + Taser warning prompt (`/s`).


* **Branch B — Armed Suspect / Shots Fired (`CODE 0` Combat Protocol):** if the exited driver holds a firearm (`weapon >= 22`) or deals damage to the officer (`onSendTakeDamage`), immediately suppress any Taser prompt (Rule 5.5 compliance) and offer the **`CODE 0` Combat Protocol**:
* Emergency radio report: `'{local_tag}{unit}, CODE 0! По офицеру открыт огонь из {vehicle_description} в районе {area} ({map_square})! Требуется срочная поддержка всех юнитов!'`
* Followed by `/mark CODE 0! Нападение на офицера в районе {area} ({map_square}), нужна срочная помощь!`
* Followed by fast wanted `2.2` (`/su {driver_id} 2 2` — Armed assault on a government officer, 6 stars) + `/pt {driver_id}`.





### 4.3. Officer Exit & Approach Detector (Day/Night Flashlight + `/n` OOC Hint for New Players)

When `self.phase == '10-55'`, the officer exits the cruiser (`state.inVehicle == false`) and approaches the target vehicle within `distance <= cfg.approach_distance` (`6 m`), offer (`Y / N`) the multi-line `10-55` Approach sequence (once per stop):

* Check in-game hour `h = getTimeOfDay()`.
* **Daytime (`06:00–20:59`):**
`'/me подходя к автомобилю, {gender:коснулся|коснулась} ладонью задней левой фары, оставив отпечаток, и {gender:осмотрел|осмотрела} салон.'`
* **Nighttime (`21:00–05:59`, when `cfg.night_flashlight ~= false`):**
`'/me достав с пояса тактический фонарик, {gender:коснулся|коснулась} ладонью задней левой фары и {gender:посветил|посветила} лучом в салон автомобиля.'`
* **Line 2 (`/do` visual inspection question per EPD Manual §230.4):**
`'/do {gender:Мог|Могла} ли {my_firstname} увидеть оружие или запрещённые предметы в салоне автомобиля?'`
* **Line 3 (when `cfg.window_ooc_hint ~= false` — helper for new players):**
`'/n Ответьте в /do на мой вопрос (например: /do В салоне оружия нет.)'`

### 4.4. Pursuit `10-57 VICTOR` & Two-Step Consecutive Chain (`Radio Report` -> `Streamlined Vehicle Wanted 8.1 + /pt` WITHOUT Mask Modal!)

When the target vehicle flees during `10-55` (`distance > 25 m` and moving after megaphone) or the officer initiates `10-57 VICTOR`:

1. **Step 1 (`Y / N` Toast — Pursuit Radio Report):**
* Template `pursuit_template`:
`'{local_tag}{unit}, 10-57 VICTOR за {vehicle_description}, {occupants_text}. Направление: {direction}, район: {area} ({map_square}), {tac}, Код 3.{armed_text}'`


2. **Step 2 (Automatically offered as soon as Step 1 finishes sending, or pinned to the Pursuit HUD Widget if deferred with `N`):**
* **CRITICAL REQUIREMENT:** When issuing wanted level `8.1` (Disobeying a police officer) during a vehicle stop or pursuit (`10-55`, `10-66`, `10-57`), do **NOT** open the multi-step Wanted Assistant window asking about RP masks, passports, or `/todo` appearance traits! In a vehicle pursuit, the officer reports the **vehicle model, color, and license plate** to dispatch.
* Provided `driver_id` is a valid connected player ID (and `generations[driver_id]` matches), Step 2 offers/executes the streamlined 4-step vehicle wanted plan (`fast_vehicle_wanted`):
1. `'/me {gender:зажал|зажала} кнопку тангенты рации и {gender:передал|передала} диспетчеру ориентировку на {model} ({vehicle_color}), гос. номер «{vehicle_plate}».'`
2. `'/do Диспетчер пробил регистрационные данные автомобиля и внёс водителя в базу розыска за неподчинение.'`
3. `'/su ' .. driver_id .. ' 8 1'`
4. `'/pt ' .. driver_id`


* If the user presses **`Y`**, the 4-step plan executes immediately via `workspace.executor`.
* If the user presses **`N`** (e.g., busy steering through a turn), the action is **not** lost — a one-click button **`[ Розыск 8.1 + /pt (ID) ]`** remains pinned inside the **Pursuit HUD Widget** until executed or the pursuit ends!
* *(Keep the full Wanted Assistant window with RP mask/passport questions and `/todo` traits intact for regular `/su ID` usage outside active vehicle stops/pursuits).*



### 4.5. Automatic Transitions from `10-57 VICTOR` to `10-57 FOXTROT` and `10-66` (High-Risk Stop)

1. **Driver Bails Out during `10-57 VICTOR` (`c.occupants == 0`):**
* Automatically offer (`Y / N`) transition to **`10-57 FOXTROT`** with radio report:
`'{local_tag}{unit}, подозреваемый покинул {model}, веду пешую погоню 10-57 FOXTROT в районе {area} ({map_square}), направление: {direction}, {tac}, Код 3!'`


2. **Vehicle Stops after Pursuit (`10-57 VICTOR` -> `10-66` High-Risk Stop):**
* When `self.phase == 'Преследование'` and the target vehicle remains stationary for `>= 2500 ms` within `35 m`, automatically offer (`Y / N`) transition to **`10-66` (Остановка повышенного риска)**:
* Radio report (`high_risk_stop_template`):
`'{local_tag}{unit}, провожу остановку повышенного риска 10-66 {vehicle_description}, {occupants_text}, район {area} ({map_square}), запрашиваю свободные экипажи по Код 3!'`
* Optional `/mark` backup call:
`'/mark 10-66 / CODE 3! Провожу остановку повышенного риска {vehicle_description}, район {area} ({map_square})!'`


* **Smart `10-66` Megaphone Selection based on `c.occupants` (EPD Manual §240.2):**
* **If `occupants <= 1` (single driver):**
1. `'/m Водитель {model}, заглушите двигатель, вытащите ключи из замка зажигания и выбросьте их в окно!'`
2. `'/m Медленно откройте дверь снаружи, выйдите с поднятыми руками спиной к офицерам и поднимите верхнюю одежду!'`
3. `'/m Сделайте три шага влево от машины и лягте на землю на живот! Любое резкое движение — огонь на поражение!'`


* **If `occupants >= 2` (multiple occupants):**
1. `'/m Водитель {model}, заглушите двигатель, вытащите ключи из замка зажигания и выбросьте их в окно!'`
2. `'/m Водитель и пассажиры, выходите из машины строго ПО ОДНОМУ с поднятыми руками спиной к офицерам!'`
3. `'/m Ложитесь на живот в метре от дороги в шахматном порядке! Любое резкое движение — огонь на поражение!'`




* Never block a solo officer from using `10-66` megaphone or arrest actions if backup does not arrive.



---

## SECTION 5. PURSUIT HUD WIDGET & TIRE-SHOOTING MEGAPHONE COUNTER (`pa26_vehicle.lua` / `pa26_hud.lua`)

When `vehicle.enabled` and `vehicle.phase` is active (`'10-55'`, `'10-66'`, `'Преследование'`, `'10-57 FOXTROT'`), render a compact tactical card in the HUD attachment lane (styled identically to `pa26_taser.lua`):

1. **Header:** `phase .. ' · ' .. model .. ' [' .. id .. '] · ' .. durationMMSS` + occupant badge (`внутри двое`).
2. **Tire-Shooting Megaphone Counter (in `Преследование` / `10-57 VICTOR`):**
* Track `self.tireWarnings` (`0..5`) and `self.lastMegaphoneAt` (with a `5000 ms` cooldown progress bar) whenever a pursuit/stop megaphone warning is sent for the active target vehicle.
* **Dual Rule Compliance Status Line:**
* `tireWarnings == 0`: `'Огонь по колёсам ЗАПРЕЩЁН (0/1 OOC · 0/5 Мануал)'` (Red/Amber tint)
* `tireWarnings >= 1 and tireWarnings < 5`: `'OOC-минимум выполнен (1/1 ✓) · По Мануалу EPD: ' .. tireWarnings .. '/5'` (Green tint)
* `tireWarnings >= 5`: `'Все предупреждения выполнены (5/5 ✓) · Огонь за городом разрешён'` (Teal tint)




3. **Interactive Alt-Cursor Buttons on the Widget:**
* `[ /m Предупреждение (+1) ]` (sends pursuit megaphone warning: `'Водитель автомобиля {model}, немедленно остановитесь у обочины! В случае неподчинения будет открыт огонь по колёсам!'`)
* `[ Розыск 8.1 + /pt ]` (shown if `driver_id` is known and fast wanted has not been sent yet in this pursuit)
* `[ 10-66 ]` / `[ Завершить ]`.



---

## SECTION 6. CADET RULE GUARDRAILS (MOSCOW TIME `UTC+3`, GHETTO `< 3` OFFICERS, TASER IN COMBAT, FRISK MODES)

1. **Moscow Time (`UTC+3`) Helper (`pa26_core.lua`):**
* Add `function M.moscowTime(ts) return os.date('!*t', (ts or os.time()) + 10800) end`.
* Use `M.moscowTime()` to evaluate server-time rules (e.g., raids allowed `14:00–22:00` MSK per Rule 4.3 / 10.9).


2. **Dangerous District (Ghetto) Arrest Guardrail (Rule 9.3 & 10.28):**
* Define LS Ghetto zones: `Ganton`, `Idlewood`, `East Los Santos`, `Jefferson`, `Glen Park`, `Willowfield`, `Las Colinas`, `Los Flores`, `East Beach`, `Playa del Seville`, `El Corona`, `Little Mexico`.
* When the local officer is in one of these zones, has fewer than 2 nearby PD colleagues (`#nearbyOfficers + 1 < 3`), and is **not** in an active pursuit (`vehicle.phase ~= 'Преследование'` and `vehicle.phase ~= '10-66'`), prepend a clear advisory warning to `/cuff` and `/arrest` confirmation modals:
`'⚠ Правило 9.3 / 10.28: вы в опасном районе (сотрудников рядом: ' .. (#nearbyOfficers + 1) .. ' из 3). Задержание менее чем втроём разрешено ТОЛЬКО если подозреваемый скрылся сюда во время погони!'`


3. **Taser-in-Combat Warning (`pa26_taser.lua`, Rule 5.5 & 10.15):**
* Record incoming firearm damage timestamps (`weapon >= 22 and weapon <= 38` from `onSendTakeDamage`).
* If the local player took firearm damage within the last `10000 ms` (or the selected target holds a firearm `>= 22`), display a warning line in `Taser:view()` / `Taser:draw()`:
`'⚠ В активной перестрелке тайзер ЗАПРЕЩЁН (п. 5.5) · только в спину/бок или против +C!'`


4. **Primary vs Full Secondary Frisk Presets (`pa26_manual_actions.lua`, EPD Manual §220.20 & §220.30):**
* In `pa26_manual_actions.lua`, add two selectable standard presets for `frisk` (and a toggle button in the `frisk` settings/modal):
* **Primary Frisk (`Первичный обыск · без перчаток`, §220.20):**
`'/me {gender:поставил|поставила} задержанного у опоры и быстрыми движениями без перчаток {gender:прохлопал|прохлопала} верхнюю одежду, торс и ноги на наличие оружия.\n/do Что офицер {gender:мог|могла} нащупать под одеждой задержанного?'`
* **Full Secondary Frisk (`Полный обыск · перчатки и зип-пакет`, §220.30):**
`'/me {gender:надел|надела} плотные чёрные резиновые перчатки, тщательно {gender:проверил|проверила} все карманы и обувь задержанного и {gender:выложил|выложила} вещи под камеру крузера.\n/do Запрещённые предметы упакованы в зип-пакет и убраны в бокс для улик.'`




5. **Server Command Reference Updates (`pa26_server_commands.lua`):**
* Update `/mark` description to `'/mark [текст] — Отправить запрос с текстом'`.
* In `M.bindingWarnings(binding)`, add a non-destructive hint if a bind contains `/blacklist` or `/unblacklist`, noting that the server help lists `/black` and `/unblack`.



---

## SECTION 7. SMART AUTO-EVIDENCE (`F8`) & SA:MP 1000-SCREENSHOT LIMIT ARCHIVER (`pa26_evidence_files.lua`, `pa26_evidence.lua`, `pa26_assist_ui.lua`)

SA:MP stops saving F8 screenshots once `sa-mp-999.png` exists in `Documents\GTA San Andreas User Files\SAMP\screens` (`Unable to save screenshot`), and typing file paths manually during a shift is impractical.

1. **Automatic SA:MP Screens Directory Scanner (`pa26_evidence_files.lua`):**
* Using WinAPI `FindFirstFileW`, `FindNextFileW`, `FindClose`, `CreateDirectoryW`, and `MoveFileExW` in `kernel32` (with UTF-16 conversion via `wide(path)` and strict path validation), implement:
* `defaultScreensDir()`: resolves `(os.getenv('USERPROFILE') or '') .. '\\Documents\\GTA San Andreas User Files\\SAMP\\screens'`.
* `scanScreens(customDir)`: scans `.png` / `.jpg` files in the directory, returning:
`{dir = dir, count = totalCount, maxIndex = maxSampIndex, latestFile = newestPath, latestWritten = maxWritten, nearLimit = (totalCount >= 900 or maxSampIndex >= 990), full = (maxSampIndex >= 999)}`.




2. **Automatic New Screenshot Verification after `/time` + `F8` (`pa26_evidence.lua`):**
* While `self.active` is waiting for a screenshot (`p.clock`), poll `files.scanScreens()` every `500 ms` in `Evidence:tick` (in addition to any manual `self.checkRequest`).
* If `scan.latestFile` has `created >= p.clock` and `written >= p.clock`, automatically run `files.verify(scan.latestFile, p.clock)`. Once verified across two ticks (`self.sample.key == file.key`), automatically record it as `'verified'` with `file.path`! Keep the manual path input field as a fallback.


3. **One-Click Screenshot Archiver (`files.archiveScreens(dir)` in `pa26_evidence_files.lua` & UI in `pa26_assist_ui.lua`):**
* Implement `archiveScreens(dir, dateTag)`:
* Creates subfolder `dir .. '\\PA_Archive_' .. dateTag` via `CreateDirectoryW`.
* Moves all `sa-mp-*.png` and `sa-mp-*.jpg` files from `dir` into the archive subfolder via `MoveFileExW` (with flags `0` — never overwrite existing files, never delete).
* Returns `{moved = count, archiveDir = archivePath}`.


* In `pa26_assist_ui.lua:M.evidence` (and as a warning banner on the `F9` Home page when `nearLimit == true`), display:
`'Скриншоты SA:MP: ' .. count .. ' / 1000 (макс. индекс: ' .. maxIndex .. '/999)'`
and a one-click button **`[ Освободить счётчик SA:MP → Перенести скрины в подпапку Архива ]`**.



---

## SECTION 8. TESTING & VERIFICATION DELIVERABLES

1. Add comprehensive LuaJIT unit and integration tests:
* `tests/test_colleagues.lua`: tests all 16 PD skin IDs, passive `/r` & `/f` colleague caching, `ADAM` (`driver` / `navigator`) vs `LINCOLN` (`solo`) role detection, auto-callsign generation (`1-L-1`, `2-A-1`, `DAVID-1`), and the Ghetto `< 3` officers warning on `/cuff` and `/arrest`.
* `tests/test_copilot_traffic.lua`: tests the full `10-55` -> stationary stop detector -> unauthorized driver exit (`/m` in vehicle vs `/s` on foot, plus `10-57 FOXTROT` vs armed `CODE 0` fork) -> officer approach (day vs night flashlight + `/n` OOC hint) -> `10-57 VICTOR` two-step chain with streamlined vehicle wanted `8.1` + `/pt` (verifying no mask modal opens) -> 5-warning tire-shooting counter -> post-pursuit `10-66` transition for 1 vs 2+ occupants.
* `tests/test_evidence_screens.lua`: tests `scanScreens` (`990/999` limit detection), automatic verification of newly created `sa-mp-XXX.png` after `/time`, and `archiveScreens` moving files into `PA_Archive_*` without data loss.


2. Run the entire test suite (all LuaJIT test groups, `tools/verify-ux-preservation.py`, CEF tests, PowerShell installer/updater tests, and x86 native ImGui layout checks at `640×480`, `1366×768`, `1920×1080`, `2560×1440`).

```

---

Как только Кодекс отработает этот мега-промпт и выдаст отчёт или архив `0.41.0` — скидывай сюда, проверим каждый байт!

```