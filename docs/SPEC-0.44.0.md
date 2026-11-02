# Police Assistant 2026 — Codex Implementation Specification
## Release v0.44.0 · Tactical UX, Native Icons, Knowledge Integrity & Performance

**Base:** the currently maintained PA code. `v0.43.2` is already released; `v0.43.3` may already have been implemented or be under active development. Inspect the **current working tree** first, preserve all improvements from 0.43.2 and 0.43.3, and target the final release as **v0.43.4**. Do not reset the branch to an older archive.  
**Language:** Russian for all player-facing UI, English or Russian for internal names and tests.  
**Goal:** make PA feel like a polished, lightweight native in-game police workstation: critical controls immediately accessible, rare settings out of the way, consistent beautiful icons throughout the UI, reference material readable, CEF chat smooth, with all existing functionality and user data preserved.

> This is an implementation request, not a request for another design essay. Inspect the current source, implement the features, run tests, deliver a reproducible release and an evidence-backed report. If the repository differs from the paths or behavior named below, use its actual APIs and explain the difference. Never fabricate a passing test or a verified rule.

---

## 0. Priorities, boundaries and definition of success

**P0 — non-negotiable:** no CEF typing/selection freezes; no broken existing actions; no loss of settings, binds or knowledge; no unwanted sends; no regression in native/legacy compatibility.  
**P1 — main deliverable:** restructured F4/F9, accessible tactical actions, clear Y/N confirmation flows, entirely redesigned `ВАЖНОЕ`, coherent native iconography across PA.  
**P2 — quality:** attractive, coherent design system; readable data badges; reliable, source-linked knowledge; responsive layouts.  
**P3 — optional polish:** keyboard shortcuts, scroll-to-section, remembered views, if they do not add risk or performance cost.

### Architectural invariants

1. This is an **assistive tool, not an automatic RP binderbot**. The player chooses their actions, performs normal role-play, and explicitly confirms sending critical commands or reports. No time-based assumption that an encounter occurred merely because an officer stood next to a car.
2. Preserve all existing saved configuration leaf paths and meaning, custom bindings, wheels, personal notes and edits, profiles, colors, key mappings, histories, knowledge records and user templates. In particular, keep F9 internal menu key `partners` while changing its visible label.
3. Preserve the established separation of duties: game/SA:MP/WinAPI input and output belong in the existing game-thread integration; UI renders state snapshots via the existing `mimgui`/studio abstractions. Do not make ImGui draw callbacks directly send server commands.
4. Leave `moonloader/lib/pa26_update_platform.lua` **byte-identical** to the 0.43.2 baseline unless a demonstrably unavoidable release blocker is approved. Confirm its SHA-256 before/after and explain any mismatch. Keep current CEF/updater integration, packaging and automatic update path intact.
5. Stay compatible with the established LuaJIT/MoonLoader + 32-bit mimgui runtime, GTA SA/SA:MP and **Windows 7 SP1**. No modern Windows-only API, webview dependency, heavy renderer, emoji font assumption, network calls from UI, or runtime generation of thousands of controls.
6. Reuse existing handlers, send guards, action IDs, data sources, modal/confirmation utilities and navigation callbacks. Do **not** create duplicate action pipelines, duplicate persistent settings, or incompatible parallel state machines.
7. Build incrementally with regression tests after each subsystem. UI refactoring must not silently alter server commands, legal semantics, safety interlocks or existing action preconditions.

### Source map to examine first

- F9 shell/navigation: `moonloader/lib/pa26_menu.lua`, `pa26_studio.lua`, `pa26_settings_ui.lua`.
- Patrol/crew: `pa26_patrol_ui.lua` and its session/controller callbacks.
- F4 tactical/dispatch: `pa26_copilot_ui.lua`, `pa26_copilot.lua`, `pa26_copilot_incident.lua`, `pa26_dispatch.lua`, `pa26_dispatch_followups.lua`, `pa26_report_context.lua`, `pa26_ground_window.lua`, `police_assistant_2026.lua`.
- Knowledge: `pa26_knowledge_important_ui.lua`, `pa26_knowledge_important.lua`, generated `pa26_important_data.lua`, `pa26_knowledge_ui.lua`, `tools/build-important.py`, `moonloader/resource/pa26/{knowledge-base,knowledge-policy,wanted-catalog}.json`.
- Authoritative *supplied snapshots*, not automatically proof of present-day authority: `docs/sources/2026-10-28/`, its `manifest.json`, `COMMAND_RP_MATRIX.json`, `RADIO_APPENDIX.json`, plus `docs/forum-review-2026-10-25.json`.
- CEF performance: `cef/assets/hud/pa26-chat.js`, corresponding message bridge, `tests/test_cef_chat.js` and integration tests.

---

## 1. One coherent visual language for F4, F9 and Knowledge Base

The visual target is **restrained professional dispatch software**, not a casino dashboard or a grey list of anonymous buttons.

### Layout and hierarchy

- **Header / context**: a compact status bar with relevant object and state. Use brief status chips, not an explanatory paragraph.
- **Primary action**: immediately below context, largest clearly labeled button(s), with one obvious safe default.
- **Secondary actions**: grouped by intent (10-55, pursuit, high risk, reports), consistently positioned; never shuffle a button's position each frame merely because its enabled state changes.
- **Advanced settings**: a separate `Настройки и тексты` view, with subsections and contextual help when needed. During an active pursuit, no slider/checkbox/template editor may push critical actions below the fold.
- **Reference content**: typography, source metadata, colored value chips and ample readable spacing. No fake action buttons merely to show a heading.

### Design tokens (adapt to current theme, do not hard-code unreadable text)

| Semantic role | Suggested accent | Rules |
| --- | --- | --- |
| Navigation / normal operation | Teal / cyan `#35B7C9` | Action highlights, links, selected tabs |
| Verified / complete / safe | Emerald `#54C995` | Positive status, confirmation **after** success |
| Caution / high risk / uncertainty | Amber `#E4AF58` | 10-66, missing facts, conditional rules |
| Information / law / articles | Indigo-blue `#759AE9` | Badges for codes, citations, legal references |
| Destructive / abort / dangerous | Muted red `#E77C79` | End/remove/cancel only, not every police control |

- Match contrast and disabled/hover/focused states in dark and available light themes. Do not rely on color alone: pair with textual states such as `Подтверждено`, `Не проверено`, `RP требуется`.
- Typography: 3 levels (screen heading, section heading, body) plus readable small metadata; prefer existing loaded fonts and safe glyphs. Avoid tiny fonts and icon-only commands. Ellipsize *only* summaries, never legal clauses or editable values.
- Consistent spacing rhythm: 8/12/16 px where current ImGui styling allows it; compact rows ~38–44 px at desktop size; interactive hitboxes remain usable when scaled.
- No excessive gradients, shadows, animation, frame-by-frame text measurement or expensive text wrapping. Cache derived layout by width/font/text revision when appropriate.
- Responsive layouts at **640×480, 800×600, 800×1100, 1024×768, 1366×768, 1920×1080, 2560×1440**; the unusual 800×1100 case matters. Respect custom font scale and maximize/restore. At 640×480 prioritize visible critical actions and allow **one intentional internal scroll** for less critical content; never promise to fit 12 full-width, 44px buttons above the fold in 480px height.
- Use one consistent content scroll region per view, fixed context/primary controls when feasible, and no nested wheel traps. Do not let overlays intercept CEF typing, mouse text selection or normal GTA focus.

### Native UX behavior

1. **Stable placement:** enabled state can change; row and button order should not unexpectedly jump under the cursor.
2. **Truthful states:** explicit labels `Нет цели`, `Юнит не задан`, `Ожидание ответа`, `Устаревшая цель`, `Требуется подтверждение` rather than silent disabled buttons.
3. **One confirmation only:** reuse central modal/toast ownership. Avoid stacked Y/N toasts or opening F4/F9 modals over CEF text entry.
4. **Keyboard/focus:** Escape closes overlays safely; no global Y/N action while the player types in chat, a text editor, or a modal with input focus. Back navigation returns to the previous logical view without wiping drafts.
5. **Persistence:** remember last appropriate tab/scroll only within the current user profile, but entering `04. Патруль` from F9 for the *first time* defaults to active patrol, not contacts. Explicit navigation from a button opens the requested subpage.
6. **No false success:** a click means request/confirmation; mark `Отправлено` only after the existing send pipeline accepts the command. If the server outcome is unknown, do not display `Выполнено` as a proven fact.

---

## 1A. A unified native iconography system for the entire PA (NEW IN v0.43.4)

### Objective and design philosophy

Introduce a **tasteful, coherent set of beautiful vector icons** across the application. The player should immediately recognize navigation, warning severity, police procedures and key actions without reading dense paragraphs. However, PA must remain professional, uncluttered and readable: **icons support Russian labels, never replace them**. This applies to **all F4/F9 pages, settings, forms, Knowledge Base, radial wheel where technically feasible, toasts, dialogs and status banners**, not just the home screen.

### Recommended icon library and licensing

Prefer a **pinned version of Font Awesome Free 6, Solid style only**, supplied as a bundled `fa-solid-900.ttf` icon font (no Pro icons or brand icon pack). Verify the exact font and icon glyphs in the official tagged upstream distribution, licensing and hashes before integrating. Font Awesome Free font files use **SIL Open Font License 1.1**; the terms for SVG/JS assets differ, so **bundle only the verified font** along with the applicable license text and upstream attribution in `docs/licenses/` or `third_party/`. An equivalent small, freely distributable icon font is acceptable only if Font Awesome proves incompatible with this actual mimgui build and the replacement satisfies the same requirements.

Never download fonts at runtime, depend on a CDN, require an installed Font Awesome package, include Pro content, inject JS/CSS icon frameworks into CEF, or use Unicode emoji/Wingdings as the primary solution. Keep all assets local and compatible with **Windows 7 SP1 and 32-bit mimgui**.

### Technical integration (important: inspect actual mimgui capabilities)

The v0.43.2 source already creates its native ImGui fonts in `moonloader/police_assistant_2026.lua` inside `imgui.OnInitialize`: it uses `ImFontGlyphRangesBuilder`, includes Cyrillic punctuation and loads several sizes of `segoeui.ttf` / `arial.ttf` from Windows. Reuse this existing initialization mechanism:

1. Bundle one icon font under `moonloader/resource/pa26/fonts/` (or the existing resource convention), pin the exact version, source, SHA-256, applicable license and **verified codepoints** in a checked-in manifest. Include it in the package/updater; no new runtime downloader or file watcher.
2. Prefer a **carefully tested font merge** into existing Cyrillic fonts, if the actual bundled `mimgui` supports `ImFontConfig.MergeMode` and private-use glyph ranges safely. Otherwise use a dedicated icon font with scoped `PushFont/PopFont` inside shared helpers and aligned icon/text layouts. **Do not assume mimgui exposes modern ImFontConfig APIs**; inspect/compile/smoke-test the x86 native binding first.
3. Build the atlas **once at font initialization**, never during rendering, CEF input, chat selection, window resize, or each frame. Limit glyph ranges to the actual icons used if possible; avoid importing every icon at multiple sizes. Preserve existing Cyrillic ranges, font pointers, lifetimes and existing icon-like Unicode characters.
4. Add a small shared semantic registry, e.g. `moonloader/lib/pa26_icons.lua`: `get(name)`, `label(name,text)`, `draw(name,options)`, or equivalent, with a **single source of truth** for icon names, font glyphs, color, baseline, spacing and fallback. Use existing UI wrappers; avoid ad hoc `PushFont` and custom glyphs in every file.
5. Preserve **every existing ImGui stable ID** (`##...`), control label meaning, hitbox and callback. Carefully adapt `menu.labelLayout`, `menu.fittedButton`, `CalcTextSize`, button widths and double-line wrapping so decorative icon glyphs do not break measured Cyrillic text or redirect clicks. Keep icon glyphs out of persistent IDs.
6. If fonts fail to load, glyphs are missing, or icons are disabled, render **the original complete Russian label** and normal UI with no tofu squares, `?` symbols or inaccessible buttons. An optional `Показывать иконки интерфейса` checkbox may be added under **F9 → Настройки → Внешний вид** with backward-compatible `true` default, if it fits the existing settings architecture. No parallel settings store.
7. These icons are **presentation only**: never add private-use glyphs to outgoing SA:MP commands, CEF message input, RP speech, report templates, saved user binds, log export, Knowledge Base source text or search indexes.

### Rules for beauty, consistency and accessibility

- Use **one coherent solid icon family** and a limited visual rhythm (typically 14–18px icons, 6–10px text gap, a slightly larger icon only in card/section titles). Subtle visual hierarchy, restrained palette, crisp pixel alignment, high contrast in enabled/hover/disabled states.
- Meaningful actions show **icon + visible text**. Icon-only buttons are acceptable only for universally understood compact chrome (close, back, edit) and must have a readable tooltip/accessible label and sufficient hitbox. Keep the main tactical labels visible even at 640×480; hide *decorative* icons first if the text would clip.
- Colored icons have **semantic meaning**, not random color: amber `triangle-exclamation` for caution, red for genuine failure/dangerous action, blue `circle-info` for neutral guidance, emerald `circle-check` for verified successful operations. Do not mark a merely clicked button as successful.
- Avoid applying icons to **every** checkbox, every knowledge record, every legal sentence, every chat line or every background option. The purpose is to create **scannable groups and obvious actions**, not visual noise.
- Tooltips may clarify an operation but cannot be the only place explaining it. Existing Y/N confirmation, game focus, navigation and keyboard behavior must not change.
- Never animate individual icons or introduce hover-driven re-layout, expensive measurement, textures, raster-to-vector conversion or per-frame downloads. Reuse cached styles/fonts.

### Canonical semantic icon map (illustrative names; verify Free Solid availability)

| Visual meaning | Suggested icon | PA locations |
| --- | --- | --- |
| Home/overview | `house` | F9 home, dashboard |
| Patrol / 10-55 | `car-side` | F4 traffic, patrol start, vehicle controls |
| Pursuit / travel | `route` | 10-57, last-known vehicle direction |
| Radio / loudspeaker | `tower-broadcast`, `bullhorn` | Dispatch, radio, megaphone |
| Caution / important `!` | `triangle-exclamation` | Safety, missing prerequisite, serious warning |
| Info / help | `circle-info` | Nonblocking hint, informational toast |
| Verified / success | `circle-check` | Verified officer/contact, send success |
| Failure / unavailable | `circle-xmark` | Missing/invalid data, error dialog |
| Search | `magnifying-glass` | Knowledge, users, bindings |
| Settings | `gear` | Appearance, radio configuration, advanced options |
| Knowledge / manual | `book-open` | 10 Knowledge Base cards and source view |
| Law / justice | `scale-balanced` or `gavel` | Administrative/criminal code, fines, rights |
| Officers / partners | `users` | Contacts, verified crew count |
| Identification | `id-card` | `/ud`, driver documents |
| Target | `crosshairs` | Selected suspect/vehicle, quick `/pt` |
| Incident/report | `clipboard-list` | Calls, reports, history, journal |
| Start / resume / pause | `play`, `pause` | Patrol session and process state |
| Finish / stop | `flag-checkered`, `stop` | End 10-55/10-99; end shift, when appropriate |
| Send / confirm | `paper-plane`, `check` | Real outgoing report, confirmation |
| Close/cancel | `xmark` | Window close, cancel draft |
| Edit / save / restore | `pen`, `floppy-disk`, `rotate` | Profile, speech editor, templates |
| Position / sector | `location-dot` | Radio location, map square, district |
| Timing / duration | `clock` | Patrol duration, timer, cooldown |
| Back / disclose | `arrow-left`, `chevron-down` | Navigation, optional advanced settings |
| Police / authority | `shield-halved` | Confirmed police status only |
| High risk / stolen | `car-burst` if actually free; else `triangle-exclamation` | 10-66, wanted bulletin |

**All names and codepoints must be resolved against the selected pinned font.** If a candidate is unavailable in that *Free* version, choose and test the nearest semantic alternative. Use a central manifest; do not scatter guessed `\uFxxx` values in source code. Do not indiscriminately use an icon merely because it exists.

### Whole-application coverage requirements

Inspect the **actual page inventory** and map icon use across the entire PA, not only the screens discussed in this design document:

1. **F9** sidebar, home action tiles, navigation, sub-tabs, buttons for bindings, addons, patrol, partners, journal/stats, knowledge, help and settings.
2. **F4** Copilot tactical bar, target/vehicle selection, pursuits, 10-55, 10-66, window interaction, report action, stolen bulletin, quick dispatch families and nested follow-up actions.
3. **Patrol** session start/pause/resume/finish, verified crew, unit editing, status chips, timers, crew changes.
4. **Settings** meaningful section headers and actions (appearance, chat, radio, hotkeys, templates, restore/save), with sparse icons in simple form fields.
5. **Knowledge Base** all 10 summary cards with one distinct semantic visual per topic; back/search, highlighted law/radio/status badges, verified source warnings, real action buttons. Do not draw an icon next to every single article.
6. **Global notifications** info/warning/success/failure toasts, blocked actions, missing IDs, Y/N prompts, progress and updater messages. Different severities must be visually distinguishable.
7. **Radial wheel**, if tested glyph rendering does not harm sector hit-testing, keyboard selection, icons centered with names or selected action details; otherwise preserve stable text wheel and document the limitation.
8. **Other tools** wanted, fines, police identity, user/vehicle management, saved bindings, notes, journal, evidence and help, following the same icon mapping.

Keep button ID stability, labels, callbacks, keyboard focus, font scaling and responsiveness across **640×480 through 2560×1440, including 800×1100**. At narrow widths, drop decorative icons before truncating a meaningful label. Save visual examples/screenshot checklist and a concise `docs/ICON-COVERAGE-0.43.4.md` listing every area and icon/fallback decision.

### Icon-specific test and acceptance criteria

- 100% of referenced icons actually exist in the packaged **Free** font and render in the native x86 mimgui build; no missing glyph rectangles or replacements.
- Every actionable control remains usable **with icons ON and OFF**. No altered ImGui IDs, swapped shortcuts, hotkey capture failures or changed report strings.
- Cyrillic text remains readable; icon-text baseline and spacing are consistent; no overlap, new horizontal scroll or clipped button captions.
- Windows 7 font loading and the existing generated glyph range survive; graphics remain lightweight and do not cause CEF typing/selection micro-freezes or frame-time regressions.
- The archive and updater include the icon font, attribution/license and verified manifest; opening PA does not require internet access. Existing installations update cleanly.
- Add a focused x86 atlas/glyph smoke test and UI snapshot or manual screenshot review across F4/F9, settings, Knowledge and toasts. Report what was and was not tested in the real game.

---

## 2. F9 navigation: rename `04. Напарники` to `04. Патруль`

**Files:** `pa26_menu.lua`, `pa26_studio.lua` and existing navigation adapters.

- In `M.sections`, change only the visible `label` and `short` to `Патруль` for `{key='partners'}`. **Keep key `partners`** for guards, saved navigation and callbacks.
- On opening the section from the main menu, default to the operational `patrol` page. When the action is a deep link to contacts/events/vehicle, respect that explicit target. Do not reset a user in the middle of editing a contact.
- Replace the `Напарники и служба` dropdown with a **responsive segmented-tab bar**:
  1. `Патруль и смена` — `patrol` (default)
  2. `Трафик и погоня` — existing `vehicle`
  3. `Напарники` — `contacts` (contact directory; not active crew)
  4. `События` — `events`
- On narrow widths wrap the tabs to a second line or offer a clearly labeled overflow selector. Never clip text or turn a submenu into four unreadable 100px tiles.
- Remove the redundant `Перейти к текущему патрулю` button when already on `patrol`; preserve the same action from relevant other pages.
- Do not call `openPatrol` in a loop when the page itself is already open.
- Make the distinction clear: `Напарники` = saved contacts; `Экипаж` = currently selected officers on this shift; `Патруль` = session state.

---

## 3. Patrol workspace: operational essentials above the fold

**Files:** `pa26_patrol_ui.lua`, `pa26_studio.lua`, `pa26_settings_ui.lua`, controllers.

### The operational F9/F4 Patrol view

Organize into **four compact, visually distinct sections**, not a continuous settings form.

1. **Смена:** status badge (`Не начат` / `На службе` / `Пауза` / `Завершён`), duration, current unit and personnel summary. Context-dependent action buttons: `Начать патруль`; during session `Пауза / Продолжить`, `Применить экипаж`, `Завершить с докладом`, `Завершить без доклада`; always a visible `Трафик и погоня` link. Keep existing session and confirmation semantics.
2. **Юнит и связь:** frequently changed fields `unit` (manual, auto when blank), `unit_number`, `station`, `channel`, `mode`; optionally `vehicle`, `sector`, and `post` **only** when relevant. Show editable `Юнит` and `Экипаж` on quick report confirmation as required by §5. Keep only genuinely frequent toggles: session enabled, periodic reporting and `reporter_self`. Use progressive disclosure for rarely changed fields, not a cluttered full form.
3. **Экипаж:** searchable existing contacts, select/deselect with IC name + role, clear applied-vs-draft state; `Управлять контактами` deep-link. Reuse current limit and validation (do not assume all online players are officers).
4. **Оперативные доклады и история:** shared quick-report launcher, recent sessions/events compact and searchable if existing data support it. Avoid duplicate quick-report implementations.

### Move low-frequency session configuration to F9 Settings

Extract a reusable `drawSessionSettings` (or equivalent) from current monolithic `pa26_patrol_ui.M.draw` and integrate into existing `F9 → Настройки → Рация/Патруль`. Include all current settings—**do not accidentally orphan any**:

- Recovery and protection: `restore_offer`, `auto_resume_reload`, `pause_on_crew_change`, `confirmation`, HUD preference and other current rarely changed flags.
- Timings/distances: `interval_ms`, `bind_distance`, `interrupt_grace_ms`, `reload_grace_ms`, `downed_hp`, `respawn_distance`, `respawn_position_tolerance`, `respawn_evidence_ms`.
- Grammar and all existing solo/team phrase forms; five session templates `start`, `resume`, `finish`, `crew`, `periodic` and example insertion.
- Session shortcuts `toggle_shortcut`, `pause_shortcut`, `finish_shortcut`; optional radio/format tuning and advanced explanations.

Expose a single unobtrusive `Шаблоны и дополнительные настройки →` link from the operational page. Preserve the exact autosave, dirty draft and conflict-handling behavior of the original controls. No separate copies of the settings tree.

---

## 4. F4 `Трафик и погоня`: usable under time pressure

**Files:** `pa26_copilot_ui.lua` and existing Copilot model/action handlers.

### Above-the-fold hierarchy

**A. Target strip** (sticky if supported): selected vehicle model/color/plate, vehicle ID, credible driver ID, phase (`10-55`, `10-57 VICTOR`, `10-66`, `FOXTROT`), confidence (`Цель видна` / `Последняя подтверждённая` / `Связь потеряна`). Use meaningful placeholders for unknown values; never display an old ID as current without marking stale.

**B. Target tools:** `Выбрать авто впереди` and `Быстрый /pt`, each with existing safety and Y/N flow. Never send by merely opening the screen.

**C. Immediate tactical controls:** preserve all current action IDs and access. Make the highest priority group visually dominant; do **not** force all 12 actions into six oversized rows on tiny screens. Recommended order, with stable slots and clear group labels:

| Group | Action IDs | Player-facing action labels |
| --- | --- | --- |
| Остановить / начать | `stop_order`, `pursuit` | `10-55 · К обочине`, `10-57 · Начать погоню` |
| Погоня / розыск | `tire`, pinned-wanted + `/pt` | `Мегафон: колёса (+1)`, `Розыск и /pt` |
| Остановка / высокий риск | `stop`, `high_risk` | `Доклад 10-55`, `10-66 · CODE 3` |
| Контакт / приказы | `approach`, `risk_order` | `Осмотр автомобиля`, `10-66 · Ключи, выход` |
| Продолжение | `explain_stop`, `foot` | `Причина и документы`, `10-57 FOXTROT` |
| Завершение / права | `explain_detention`, `finish` | `Основание и права`, `10-99 · Завершить` |

At sufficient width render a clean **two-column** grid; at 640×480 show the four to six most urgent controls in stable positions and an obvious `Остальные действия (6) ▾` segment inside the **same view**, with keyboard-accessible expanded content. Do not bury `finish` during an active stop: it can be in a persistent slim footer or context strip when the phase allows finishing. Do not change action order on every update; disable/annotate unavailable operations with reasons.

**D. Contextual compact blocks below primary controls:**

- Current `Окно водителя` state, with short next action, existing `Водитель открыл`, `Закрыто`, `Спросить снова`, `Пропустить` only when applicable; prioritize what the player should actually do next.
- Active stolen vehicle bulletin: model/color/last location/known square/time, `Уточнить` and `Убрать` with existing confirmation rules.
- Tire warning count; status of `/ud` contact; relevant observed evidence and safety hints, never an oversized instruction paragraph.

**E. Reports and dispatch** below situation:

- Five existing quick reports: `Код 4 · Продолжаю патруль`, `9-1-1 · Код 3`, `Прибыл · Код 6`, `Потерян · Код 4 ADAM`, `Перерыв · Код 7`. Show buttons in an efficient 2-col layout, single-column on narrow screens.
- Existing five dispatch families `9-1-1`, `Угон`, `Бизнес`, `АЗС`, `Банк`. Main family action opens a **nested row of existing follow-up report buttons** in F4. No automatic emission of extra RP by expanding a family or selecting its next-stage action; follow-ups must use established confirmation/safety checks.
- Low-priority on-shift editable controls stay compact at the bottom: TAC, report channel, stop outcome, manual plate and `Подозреваемые вооружены`. Move on-duty enable, capture radius, driver-target binding preference, long instructional text and technical sliders to **`Настройки и тексты`**.

### Quick `/pt` target selection

Preserve the user's chosen pragmatic behavior for low-online Exsellent RP: prefer a confirmed pursuit driver, then an explicitly selected target, then the selected car's driver, then the nearest **server-recognized wanted player** within the valid scope (not any nearby civilian). Confirmation always displays `Nick_Name`, ID and **why this ID was selected**; no verified target → choose ID manually. Re-check the current ID/player identity and wanted status at execution time. Do not silently use a random player just because it is close. Keep the existing server command guard.

---

## 5. Reports without an active patrol, human-driven 10-55 and Y/N decisions

### F4 reports must work even with Patrol OFF

- The F4 quick report and dispatch buttons are separate from the optional *patrol session manager*. They must work without an active shift if the normal duty/status, permissions and server-safety checks allow them.
- On click, show one readable confirmation/preview with the resolved report, channel, placeholders and editable **`Юнит`** and **`Экипаж`**. Do not require the user to start a session just to report `Код 3`.
- `Y / Да` sends only after all required values and existing guards pass; `N / Нет` cancels without sending and offers `Изменить юнит и экипаж` (or opens those fields directly). Do not incorrectly turn N into a send. The exact semantics of N for the **10-55 finish toast**, below, are different and must not be mixed.
- Never silently fill a fake unit, partner, station, vehicle, IC location or direction. Known session context can prefill values and must be visibly editable. Validate empty or invalid fields before send.

### 10-55 human interaction / `/ud` observation

Preserve the 0.43.2 behavior already implemented. The player may use any private bind or manually type `/ud`; it is the **observed sending of `/ud`** that is an eligible signal of real contact, not the name of the bind or how long the character stands nearby. No action should automatically count merely because the officer is within `approach_distance` or has typed unrelated `/me`, `/s` or normal chat.

1. Detect a manual `/ud` through the existing local outgoing-command pipeline (including commands produced by binds where observable), while `10-55` is active; associate it with the correct stop/vehicle and target context. Do not infer server acceptance unless the game explicitly confirms it.
2. Do not set `done.explain_stop` merely because `/ud` occurred: distinguish `contact_confirmed_by_ud` (observed command) from `reason_explained` (actual window/manual report evidence). The user can still converse manually, and the completion toast must not require using Copilot's `explain_stop` window.
3. When contact evidence exists and the officer **returns to cruiser** or the **stopped vehicle visibly departs**, offer **`10-55 завершена? Доложить 10-99 / Код 4? [Y/N]`**.
4. On **Y**, open/execute the established completion confirmation/report with correct unit, vehicle description, area/square and stop outcome; do not immediately reset before the send is validated.
5. On **N**, do **not** automatically accuse the driver of flight. Only if credible observed departure/flee conditions exist may the next toast ask **`Начать 10-57 VICTOR? [Y/N]`**; otherwise keep 10-55 active and return to the operational panel. When `c.stale == true` because of stream-out, treat it as **unknown visibility**, not proof of flight.
6. Keep `lastCar` and known stop context until the player explicitly finishes, switches target with appropriate confirmation or resets. `finish` can use known car data when no car is currently streamed; label stale data as last known. Do not break new-stop capture.

### Role-play at the driver's window

- **Never** send `/me постучался...` on a fixed timer; the officer may still be walking to the car.
- After the headlight/salon step and when genuinely near the driver's window, offer `Спросить, открыто ли окно?` and a preview of `/do Окно открыто?` / `/n Ответьте в /do`. Only **Y** sends the selected action.
- The Copilot may parse the existing observable chat stream (e.g. `Окно открыто. (Nick_Name)`, `Окно закрыто. (Nick_Name)`) and associate the reply **with the confirmed player** and current stop, not arbitrary nearby chat. Detect plausible positive/negative forms, handle ambiguous answers as unknown, and avoid guessing from OOC chatter.
- If the window is closed, the next toast may suggest `/me постучался в водительское окно.` **only upon Y and only when position/identity conditions still hold**. After an opened-window reply, offer the existing introduction/reason window directly. Continue to support manual conversation, skip/cancel and original controls without forcing a scripted sequence.
- In the reason window, use a **single scrollable searchable list**, common reasons first, reference AK/UK articles where verified; `Выезд на встречную полосу` exists as a practical reason **without inventing an article**. Switching reasons must not silently reuse a previously edited speech draft intended for another violation: store per-reason drafts or prompt before replacement.

### Direction and radio safety

- Use the **last reliably observed course of the vehicle before it stopped**. If none was captured, provide an explicitly labeled approximate heading from vehicle orientation when available. Do not emit `на неизвестно` or invent a compass course.
- Where an optional direction cannot be resolved, remove the direction-dependent phrase from stock templates cleanly. For user-custom templates, preserve wording and expose unresolved placeholder/preview instead of rewriting their prose silently.
- Map squares already available from the game/project must remain authoritative; don't approximate every neighborhood to a fabricated fixed square. Keep verified `{map_square}` support.
- Count actual **verified police colleagues**, not all cruiser occupants, for dispatch and reinforcement requirements (check `pa26_dispatch.lua` and the distinction between `patrolOccupants` and raw `cruiserOccupants`).

---

## 6. Knowledge Base `ВАЖНОЕ`: from grey buttons to readable reference cards

**Files:** `pa26_knowledge_important_ui.lua`, `pa26_knowledge_important.lua`, `pa26_important_data.lua` generator and related navigation.

### Information architecture

The knowledge base has two distinct jobs:

1. **`ВАЖНОЕ`** = 10 curated operational guides, optimized for finding an answer in seconds.
2. **`РЕЕСТР`** = complete searchable articles/commands/rules with detailed source provenance and user edits.

Do not merge 1,073 articles into the 10-guide dashboard or read them all on every frame. Do not remove or shorten existing records to improve aesthetics.

### Dashboard: 10 clearly differentiated cards

Keep the ten existing IDs and informational coverage: `radio`, `traffic`, `risk`, `force`, `rights`, `commands`, `service`, `wanted`, `fines`, `catalog` (verify actual order/IDs in generated data). Render 1–3 columns based on **available width and font scale**, not display resolution alone.

Each card:

- Has a subtle colored left rail, a small stable `01`–`10` number, a **human-readable title**, a one-line promise/subtitle and 2–3 real highlights. No excessive neon or giant gradients.
- Is visually a card, not a full-frame button. A prominent `Открыть памятку` action is the only required click target; make navigation discoverable via hover/focus, preserve accessibility.
- Displays a compact badge if important material contains unresolved/conflicting sources (`Есть уточнения`) rather than suggesting certainty.
- Uses cached text-layout measurements. No height jitter across frames when text changes or font scaling is enabled.

### Inside a guide: complete content, no accordion button per row

- Top: `← Все памятки`, guide title, subtitle, optional factual `Источник: ... · проверено ...`, and only **real** shortcuts to relevant PA tools. These must execute their existing callbacks, not navigate to dead stub screens.
- Below: **responsive filter pills** `Все темы` (default) + the guide's actual section titles; wrap/scroll pills as needed with readable labels, no double stacked comboboxes.
- Content: distinct **section headings**, fully expanded entries with readable article/code title, complete description, conditions, neutral separators, source references, warning chips and appropriate operation buttons. Absolutely **no** `v:button(row.title...)` used as an accordion; no `Предыдущие/Следующие` pages within a guide.
- For a long guide, use a **single scroll view**, incremental/virtualized ImGui rendering (`ImGuiListClipper` if supported by this mimgui build, otherwise stable measured block heights + visible-window culling). The text of *every* entry is available by scrolling immediately, with no extra click/pagination. Do not eagerly create hundreds of child windows or re-wrap all strings each frame.
- Make `Все темы` deduplicate entries **by stable row identity**: `fines` and `commands` intentionally index records in `all` **and** thematic sections; they must not appear twice in the combined view. When a specific section is chosen, show exactly that section's original membership. Keep accurate section headings when deduplicating.
- Global search searches guide records across cards and returns the matching entries **already expanded** with parent guide/section labels. Use cached casefolded searchable text and only recompute filters when query/data revision changes; no frame-by-frame O(n) scans during CEF typing.
- Provide clear empty state (`По запросу ничего не найдено`) with back/clear action; retain query only where intended. Show results count, not page count.

### Structured data types: visual highlighting is evidence-driven

| Material | Formatting | Prohibition |
| --- | --- | --- |
| Radio | prominent `10-55`, `CODE 4 ADAM`, `TAC` chip; description below | Inventing a code meaning |
| AK fines | `АК · статья`, **each existing sanction branch** with condition and ПМ range | Inferring a missing fine, collapsing contradictory branches |
| УК and `/su` | article reference + game wanted category + `★` count *when directly verified* | Presenting a game mapping as a legal equivalence |
| RP command matrix | monospace-style command and textual chip `RP требуется` / `Без отдельного RP` / `Условно` / `Не подтверждено` where justified | Treating absence from matrix as proof of RP exemption |
| Rights, detention, tactics | clearly numbered sequence + source metadata + highlighted verified numbers | Displaying a derived shortcut as universal permission |
| User-edited/conflicted | `Моя редакция` or `Требует сравнения` chip and link to full Registry | Overwriting original or hiding the conflict |

- Parse and format structured sanctions, citation IDs and value fields rather than coloring arbitrary numerals in narrative text; don't use regex that makes every number a fake legal fact. If necessary, extend the **presentation model** and generator instead of mutating source text.
- Action buttons only when `row.action` / verified navigation callbacks exist: `/su`, form of fine, `setmark`, F4, stop reason, legal rights/timers. Pure information has **no buttons**. Keep actual action preconditions and explicit confirmation; opening a knowledge article is not permission to perform a command.

---

## 7. Mandatory factual/source audit of the Knowledge Base

The supplied source snapshot is dated **2026-10-28**, not independently certified as latest. Check publicly accessible current Exsellent RP/EPD forum rules and source files where possible. Do not use real-world penal codes, old Diamond RP tables or guesses as game rules. The forum may have inaccessible or password-protected areas; a failed request never authorizes inventing content.

### Verified baseline facts from an offline read of the attached v0.43.2 archive

| Item | Baseline result |
| --- | ---: |
| Knowledge `sources` | 94 |
| Indexed `articles` | 1,073 |
| `commands` records | 51 |
| `rules` | 212 |
| `radio` entries | 86 |
| `offenses` | 41 |
| Scenarios | 25 |
| Wanted catalog | 31 game categories |
| Supplied RP matrix | 50 unique commands; 21 require RP, 29 without separate RP |
| Supplied norm snapshots | 14/14 SHA-256 hashes matched `manifest.json` |
| Article ID collisions / orphaned article source IDs | 0 / 0 in baseline check |
| Known catalog gaps / unresolved values | 23 / 4 |

**Important:** these are integrity/count checks, **not** a claim that 1,073 articles were manually checked against today's live forum. Recompute all numbers in Codex, preserve sources, and report any deviation.

Known unresolved values in source JSON: `PM_currency_value`, `IC_year_to_game_minutes`, `article_to_stars`, `official_patrol_grid`. None may be silently filled from intuition. Existing `wanted-catalog.json` says game levels are based on a supplied list; legal links are *suggestions* rather than server-verified 1:1 mappings.

### Full audit required from Codex

1. Re-check SHA-256 for every file listed in `docs/sources/2026-10-28/manifest.json`, source count, JSON/schema validity, unique keys, article-to-source links, referenced lookup keys, forward references and derivation reproducibility of `pa26_important_data.lua`.
2. Build **a coverage matrix** mapping each of the 10 cards → every section → every row → all source references (file / URL / article / paragraph / capture date / edit status). Report broken links, ungrounded text, duplicate display entries, missing sanctions and mismatched official terminology.
3. For public forum sources, compare **relevant official current text** to the frozen snapshot: EPD/FBI common regulations, current police manual/radio codes, AK, UK, Constitution, police law and training/command rules. Record source URLs and timestamps. Protected/restricted pages are `access_blocked`/`not_verified`, never fabricated or bypassed.
4. For **each AK article** represented in fines UI, confirm article reference, applicability, all sanction branches, units (ПМ), alternatives/conditions and effective edition. Distinguish ambiguous or conflicting clauses. *Never* convert a missing ПМ value into a made-up in-game amount.
5. For **each `/su` category**, verify code, display name, star level against supplied game observations; any legal article association is separate (`confirmed`, `suggested`, `unmapped`) with source explanation. Keep `Выезд на встречную полосу` as a useful stop reason without fake article attribution until verified.
6. For RP command table, maintain 50 unique user-supplied commands, one duplicate `/undivision` in raw source, and the separate `/ticket` user-confirmed workflow. Reconcile `COMMAND_RP_MATRIX.json`, generated presentation, executable bindings and full Registry. Flag contextual commands, known exceptions and unverified syntax; an `rp_required=false` table cell does **not** override other scenario-specific RP obligations.
7. Verify operational conditions that matter to a patrol: when ID may be known IC, masks, pursuit/tire warnings, taser 20m/5-second/2-shot constraints, arrest rights, telephone/access to counsel, 10-55, 10-66, robbery/raid minimum staffing and limitations; retain contradictory rules side by side where authority is unresolved. Do not replace them with one universal numeric rule.
8. Determine **which source has priority**, from explicit published provenance and `knowledge-policy.json` rather than simply newest date; manual vs common rules vs a particular operation can vary. Record decisions or unresolved conflicts.
9. **Keep original normative source snapshots immutable.** If live sources changed, create a new dated capture with source URL/date/hash and generated diff. Do not quietly rewrite the frozen 2026-10-28 baseline or use a stale version as current. Do not republish protected or copyrighted full pages outside allowed storage.
10. Deliver `docs/KNOWLEDGE-AUDIT-0.43.4.md` plus machine-readable `docs/knowledge-audit-0.43.4.json` with counts and entries classified `verified_current`, `verified_snapshot_only`, `conflict`, `missing`, `access_blocked`, `needs_manual_review`. Missing material should appear as a visible UI caution, not be silently removed.

### Known live cross-checks worth repeating

- Public common EPD/FBI rules: `https://forum.exsellentrp.com/threads/yedinyi-reglament-i-pravila-dlya-sotrudnikov-epd-i-fbi.201/` — check sections on `/su` IC identity, TASER and intervention conditions.
- Public EPD manual vol. 1: `https://forum.exsellentrp.com/threads/www-epd-gov-manual-rukovodstvo-tom-1-politika-departamenta.472/`.
- Public Constitution: `https://forum.exsellentrp.com/threads/konstitutsiya-respubliki-exsellent.725/`.

Those are examples for live verification, **not proof** every imported law is current. Preserve 0.43.2's existing source IDs and account for inaccessible threads.

---

## 8. Correct known 0.43.2 edge cases while restructuring (P1)

1. **Direction:** `pa26_copilot.lua` stock dispatch/`patrol_continue` currently risks emitting unnatural `на неизвестно`; resolve via `pa26_report_context` and safe template cleanup per §5.
2. **Staff counting:** `pa26_dispatch.lua` must base a police-staff requirement on verified `patrolOccupants` (or equivalent), not all raw `cruiserOccupants`. Show confidence if the roster has unknown IDs.
3. **Stale vehicle after contact:** `pa26_copilot_incident.lua` must preserve offerability of finish when `/ud` was observed and the target streams out, while carefully distinguishing `stale` from observed escape. No spurious `10-57` on stream-out.
4. **Reason draft leakage:** `pa26_ground_window.lua` changes of stop reason must not send a speech text manually edited for a different reason without explicit user review/reset.
5. **CEF provenance:** confirm the *actual* 0.43.2 CEF asset is distributed. Do not rely on release prose saying hashes/contents are identical to 0.43.1; inspect real ZIP SHA-256 and package metadata.
6. **Duplicate guides:** fix the `all` vs categorized section duplication in the new `Все темы` rendering without altering the underlying per-section data or links.

---

## 9. CEF chat performance is a release blocker, not a cosmetic optimization

The user previously experienced micro-freezes and input lag **on every typed character or mouse text selection** in the CEF chat when PA was loaded. Hiding the old `Текст перенесётся на две строки` hint is acceptable; smooth editing and selecting are much more important. **Keep PA's other features working.**

- Audit keypress/input/change/selection/keyup handlers, DOM mutation and selection observers, text wrapping, callbacks across the CEF bridge, and heavy Lua polling/JSON serialization triggered on each keystroke.
- No O(n) traversal over chat history, all binds, all knowledge items or arbitrary windows **per character**, selectionchange or animation frame. Never repeatedly rebuild a whole preview due to cursor movement or highlighting text.
- Prefer precomputation, event filtering and invalidation-based caches; schedule expensive *nonessential* work after input idle and outside focus-sensitive paths. Do not debounce the real chat input itself or make text appear late.
- Eliminate feedback loops between CEF input edits and PA sync. Do not intercept normal Ctrl+A/C/V, backspace, arrows, select-drag, IME/composition or native CEF context selection semantics.
- Retain message splitting/127-byte wire checks at **submit/send time**, not while every individual character is typed. Preserve safety preflight of all chunks.
- Create repeatable stress fixtures: long CEF message, Russian/English mix, every-key typing, continuous drag selection, Ctrl+A, paste, backspace, open/close PA while typing, 500+ chat lines. Compare PA disabled vs enabled and v0.43.2 vs v0.43.4; record median/p95 input-handler duration and worst long task, FPS/frame-time spikes. The actual user must see no perceptible difference between PA ON and PA OFF.
- UI redesign must not worsen frame time during an active chase or when the Knowledge Base search is open. Keep costly source comparisons **offline**, never at game runtime.

---

## 10. Test plan and release acceptance criteria

Create `tests/test_ux_reorg_0434.lua` (or extend the already implemented 0.43.3 suite) and add targeted icon/font tests; reuse the project's actual native mimgui and mock harness. Pure Lua mocks cannot prove GTA/CEF performance, so list a required in-game manual test matrix separately.

### Functional/UX acceptance

- [ ] `04. Патруль` is named correctly; key still `partners`; defaults to patrol, while explicit contacts/event navigation still works.
- [ ] Existing patrol life cycle, contact roster, unit formatting, saved profile, report templates, hotkeys, history and automatic reports retain behavior. Rare settings are accessible and not duplicated.
- [ ] F4 target strip + primary actions are reachable before technical settings. F4 reports/dispatch work **without a started patrol** when normal guards allow. Quick report preview has editable `Юнит` and `Экипаж`.
- [ ] Nested dispatch follow-ups reveal buttons without sending extraneous RP. Y/N and focus rules work; changing context dismisses stale toasts.
- [ ] `/pt` uses confirmed/wanted candidate selection with nick, ID and source, then execution-time recheck.
- [ ] Manual `/ud` can lead to a **finish** offer after returning to cruiser or a real departure; no idle-time false positive. N proposes chase only when departure evidence supports it. Vehicle stream-out cannot on its own prove fleeing.
- [ ] Window prompt/knock is position-aware and Y-confirmed, chat replies are matched to a relevant actor, and own/manual RP remains valid. No auto-typing `/me постучался` from timer.
- [ ] `ВАЖНОЕ` shows exactly 10 visually distinct cards; full text of every guide row is immediately scroll-readable; no per-row accordion or pagination; no duplicated records in `Все темы`; actual tool buttons navigate; global search is responsive.
- [ ] Knowledge source hashes and coverage checks pass, with contradictions/unverified rows clearly labeled and original snapshots untouched.
- [ ] F4/F9, settings, knowledge, toasts and appropriate subtools use one consistent local icon font and semantic registry; every icon has a verified glyph and unobscured Russian label; all controls work identically without icons.
- [ ] No accidental action when a CEF textbox or editor is active; CEF typing and mouse-selection are as smooth with PA enabled as with PA disabled.

### Responsive/manual matrix

Check at `640×480`, `800×600`, `800×1100`, `1024×768`, `1366×768`, `1920×1080`, `2560×1440`, default and enlarged font scales:

1. F4 `Ситуация` with **no target**, active `10-55`, active `10-57`, `10-66`, stale car, window dialogue, stolen bulletin and 5 dispatch families expanded independently.
2. F9 `Патруль` inactive, active with 0/1/multiple crew, narrow and overlong nick/unit values; switch tab during edit, back, cancel and reopen.
3. Knowledge all 10 dashboards, heavy `АК` / `Команды` / `Радиокоды`, `Все темы`, one specific section, global search and no-results.
4. Icons enabled/disabled: F4, F9 sidebar, tabs, forms, all 10 knowledge tiles, radial wheel, warnings, Y/N confirmations, search, status, large text, fallback when icon font is unavailable.
5. Confirm **no clipped text/buttons, no inaccessible controls, no disappearing modals, no wrong nested scrolling**, no focus steal, no overlapping toasts, no click-through into gameplay.
6. Compare game FPS and input response PA on/off while moving/chasing, typing, selecting CEF text and opening large reference content.

### Automated checks

- Run existing Lua syntax/luacheck conventions, relevant LuaJIT test suite, generator consistency checks, `tests/test_ux0432.lua`, `tests/test_knowledge_important.lua`, `tests/test_knowledge.lua`, `tests/test_cef_chat.js` and available native x86 ImGui smoke tests; add focused 0.43.4 regressions.
- Snapshot/compare config serialization of representative **real old user profiles** in temporary test fixtures; any additional settings require backward-compatible defaults and migration. Never overwrite originals.
- Verify no unauthorized change to updater, no duplicate input hooks, no unguarded chat sends, no unexpected difference in source snapshot hashes.
- Validate the icon manifest against the actual pinned Free Solid TTF, 32-bit native font atlas, Cyrillic rendering and all fallback paths. Assert decorative glyphs never enter player messages, report templates or stored bind text.
- Package version/manifest/release notes accurately. Include CEF assets only where updates require them; verify install/update path with a real upgrade simulation from 0.43.2.

### Deliverables

1. Working `0.43.4` source diff and complete tested release archive.
2. `docs/RELEASE-0.43.4.md`: what changed, screenshots or accurate descriptions of F4/F9/Knowledge, compatibility and remaining limitations.
3. `docs/KNOWLEDGE-AUDIT-0.43.4.md` and `docs/knowledge-audit-0.43.4.json` with evidence, hashes, citations and unresolved issues; any access restriction explicitly declared.
4. `docs/UX-TEST-MATRIX-0.43.4.md` with automated results **and** in-game manual tests, clearly separating `passed`, `not run`, `blocked`, `failed`.
5. Small `Before → After` inventory of screens and each setting's new location; proof all existing controls and knowledge sections remain reachable.
6. `docs/ICON-COVERAGE-0.43.4.md`, pinned Free font/codepoint manifest, original license/attribution, bundled TTF and screenshots (or a clearly identified pending manual screenshot checklist) proving consistent icon use across PA.

### Final response format required from Codex

Summarize: (a) implemented changes, (b) key UX/iconography decisions, actual bundled font/license and screenshots/test evidence, (c) knowledge audit: what is fully verified vs snapshot-only vs conflicted, (d) performance before/after and CEF test methodology, (e) test commands and outcomes including native glyph/fallback tests, (f) files touched and risks. **Never** claim in-game performance or current forum validity from offline mocked tests alone. If complete source-by-source online audit is blocked or unfinished, say so and create a finite, actionable follow-up list; still ship a functioning and visibly improved UX without invented normative data.

---

## 11. Delivery sequence to limit regressions

1. Baseline SHA/count audit and mapping of screen actions/settings; capture existing behavior and CEF performance.
2. Reuse existing v0.43.3 progress; implement unified layout tokens and the simple `04. Патруль` navigation; verify old configs.
3. Integrate one verified Free Solid icon font and central semantic registry into the existing ImGui font initialization; test Win7/x86, fallback and no CEF regression **before** adding icons widely.
4. Refactor Patrol operation vs advanced settings, preserving same underlying state; apply icons to section headers and meaningful buttons.
5. Reorganize F4 combat UI and independent quick reports; verify every action/confirmation and icon/button ID.
6. Fix listed 0.43.2 incident/RP/direction/occupant issues with targeted state-machine tests.
7. Rebuild `ВАЖНОЕ` presentation and generator, with de-duplication, source badges, appropriate semantic category icons and viewport-aware rendering.
8. Apply the shared icon system to all remaining meaningful PA surfaces, review visual consistency without clutter, complete the documented coverage audit.
9. Perform full source audit and document discrepancies **without** making unjustified legal edits.
10. Run native/CEF performance and resolution matrix, fix failures, prepare versioned release and handoff report.

**Quality bar:** the officer should understand the current situation in one glance with tasteful visual icons, find the next action in one click, edit a report without starting a patrol, read any rule without opening nested grey accordions, and type freely in CEF chat with PA enabled. All of that must happen without weakening RP safety, source credibility, performance or backwards compatibility.
