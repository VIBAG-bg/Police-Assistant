> История первого кандидата 0.45.1. [Итоговые проверки опубликованной сборки](RELEASE-VERIFICATION.md).

# Итоговая проверка локального кандидата 0.45.1

Кандидат собран из проверенного исходного архива 0.45.0. Базовый commit: `93259614db652aec6a6010665a34a65b422dab51`. Оригинал ТЗ сохранён дословно; версия — **0.45.1**. Ни публикации, ни установки, ни записи в живую GTA не выполнялось.

## Что реализовано

83 авторских бинда, 34 правила ручных команд, мужские/женские формы, два независимых колеса (8 пеших / 6 автомобильных), дополнительные действия «Ещё», сохранённый личный раздел и следствие в F9. Используются существующие классификатор транспорта и Copilot. Неизвестная модель предлагает два предпросмотра. Опасные этапы подтверждаются отдельно, проверяется прежняя цель и машина; НЕТ / Esc / тайм-аут прекращают остаток.

Тексты, варианты, вопросы, паузы, тайм-ауты и клавиши доступны в прежнем GUI. Номер значка — отдельное поле профиля. Сохранение и предпросмотр проверены. [Уточнения исходного текста](RP-DEVIATIONS.md): четыре замены SA:MP ID на IC-номер значка и одно слишком длинное действие `/todo`, целиком вынесенное в `/me`. Утверждённый текст ручной `/setmark` не менялся; новый A40 приведён к этому же тексту вместо устаревшей фразы старого публичного A40. Задержки и центральное исключение повторов сохранены.

## Матрица результатов

| Проверка | Результат | Область доказательства |
|---|---|---|
| Lua-регрессия | PASS | 216 групп, 13,427,112 проверок; 410 файлов синтаксиса |
| 83 бинда / 34 ручных правила | PASS | Обе формы пола, CP1251, пределы сообщений и `/todo`, точные исходные строки с документированными уточнениями |
| Входы команды / F4/F9 / колесо / клавиша | PASS | Реальная подготовка и исполнитель PA в симуляторе; отмена, этапы, неизвестная модель, без повторных отправок |
| Пользовательские данные | PASS | Roundtrip старого формата, личные тексты, избранное, горячие клавиши, названия и порядок колёс, профиль, заметки, геометрия |
| Импорт авторского набора | PASS | Предпросмотр, подтверждение, резервная копия, личные ответвления, конфликты, повторное применение, лимит 128 без удаления данных |
| Защита старого PA | PASS | Настоящие валидаторы 0.45.0 отклоняют оба новых публичных документа schema 2 |
| Установщик / обновлятор | PASS | 8 основных + 6 дополнительных групп на изолированных папках; 12 точек сбоя/отката |
| All-in-One и старый worker 0.44 | PASS | Полный пакет, граф дорог, обрыв и восстановление, безопасный отказ старого worker |
| x86 LuaJIT / IPC | PASS | 113 проверок; настоящий loopback и функция отправки HUD в отдельном V8; чат DOM — тестовый |
| Нативная CPU-отрисовка | PASS | 1148 кадров, 19 прежних + 3 новых представления, 7 разрешений, 2 масштаба шрифта; не GPU и не GTA |
| CEF синтетика | PASS | 578 + 21 + 74 проверок; 40 000 событий редактирования без запросов/DOM-работы, восстановление и отсутствие дублей |
| CEF `d7526…` | PASS | Сохранённые проверенные реальные файлы; статический контракт, установка/переустановка/откат в макете, без изменения original main.js |
| Текущий CEF `f6122…` | BLOCKED | Прежний verifier отклоняет изменившийся функциональный профиль; native-only. Полная CEF-совместимость не заявляется |
| Полный старый клиент `c458…` | BLOCKED | Исходный main.js недоступен; путь известного реестра проверен только макетом |
| GTA / Exsellent, реальная задержка и кадры | NOT RUN | Нужен отдельный игровой прогон |
| Второй компьютер / Windows 7 как ОС | NOT RUN | PS 5.1 и x86 на текущей ОС не доказывают работу на другом ПК / Windows 7 |

Три первых неудачи полного прогона были устаревшими ожиданиями тестов и включением новых системных пунктов в старую раскладку. Исправление сохраняет старую раскладку: новые пункты появляются лишь при явном назначении. Повторный полный прогон чистый. Дополнительный старый тест ожидал замену 6 записей на 83; теперь проверяется сохранение 6 записей плюс 83 новых (89). До запуска All-in-One требуется построенный update.zip; после его подготовки актуальный вариант теста прошёл. Проверки CEF на движущемся live-файле не объявлены успешными: для регрессии отдельно использован архивный `d7526…`, а текущая несовместимость отражена в CURRENT_CEF.json.

## Совместимость и сохранность

CEF-адаптер, мост, обработчик текста, реестр и verifier CEF, навигация, roads.bin, классификатор транспорта, updater worker и защищённый Lua-bootstrap сохранены побайтно. 32 проверок сохранности. Изменение install.ps1 ограничено списком собственных PA-модулей. Авторские значения геометрии F4/F9, INI/HUD не менялись. Передача команды клиенту не означает принятия сервером.

Текущий read-only снимок main.js: `f6122cb757c72c38419708c490803912d039e945958225fdaa1be056e2a708a0`. Результат: `functional_profile_mismatch`, `native-only`, runtime `NOT_RUN`. Успешные 113 IPC-проверок выделенной функции отправки **не** подтверждают полный контракт этого клиента. Это внешний блокер новой чистой CEF-установки, выделенный без переписывания защищённого работающего моста. Обычные нативные функции PA сохраняются. Поддержка этого нового контракта требует отдельного задания и проверки.

Существующие личные бинды автоматически не заменяются. Авторский набор применяется только отдельной кнопкой с просмотром и резервной копией. Старые исполняемые файлы могут не читать новые документы: откат пользовательских данных выполняется из резервной копии. Переход с worker 0.44.0 — однократно полный установщик.

## Измерения — только синтетика

Три парных прогона LuaJIT/Lupa и три Node/V8 с тестовым DOM. Числа ниже — медиана p95 трёх прогонов, включая накладные расходы стенда; это не время появления буквы в GTA.

| Обработчик | 0.45.0, мс | 0.45.1, мс |
|---|---:|---:|
| onWindowMessage.mouse | 0.000600 | 0.000600 |
| onWindowMessage.char | 0.000600 | 0.000400 |
| onWindowMessage.key | 0.001500 | 0.001400 |
| Bridge.tick | 0.001900 | 0.002100 |
| Bridge.exchange | 1.642600 | 1.452400 |
| context | 0.001300 | 0.001000 |
| updateGame | 1.534300 | 1.525600 |

В Node/V8 p95 русского ввода: без PA 0.002000 мс, 0.45.0 0.001800 мс, 0.45.1 0.002100 мс. Разница на таком стенде сопоставима с шумом измерения. В обоих адаптерах при редактировании — 0 IPC, чтений/записей текста, чтений стилей/геометрии и загрузок endpoint. CEF-файлы одинаковы с baseline. Реальные input latency, FPS и frame spikes остаются NOT RUN; обещание отсутствия игровых фризов по этим цифрам не делается.

## Дальше

Проверить [ручной чек-лист GTA](../../ACCEPTANCE-0.45.1.md). Команды сборки и будущей публикации — [отдельно](../../BUILD-0.45.1.md). До разрешения владельца кандидата не устанавливать и не публиковать. Артефакты и их фактические SHA-256 проверяются `tools/verify-artifacts0451.py`; сами хеши ZIP лежат рядом с архивами в dist/SHA256SUMS.txt.

## Все изменённые и новые файлы

Ниже перечислены файлы исходного пакета относительно замороженного 0.45.0. Временные макеты, журналы и dist не включены. Самоописывающиеся отчёты проверяются внешней суммой архива.

- `.github/workflows/check.yml` — modified
- `AGENTS.md` — new
- `CHANGELOG.md` — modified
- `INSTALL_MANIFEST.json` — modified
- `README.md` — modified
- `docs/ACCEPTANCE-0.45.1.md` — new
- `docs/BUILD-0.45.1.md` — new
- `docs/RELEASE-0.45.1.md` — new
- `docs/TODO-0.45.1.md` — new
- `docs/qa/0.45.1/ALLINONE.json` — new
- `docs/qa/0.45.1/AUTHOR_ORACLE.json` — new
- `docs/qa/0.45.1/AUTHOR_REPRODUCIBILITY.json` — new
- `docs/qa/0.45.1/BASELINE.json` — new
- `docs/qa/0.45.1/CEF_NATIVE32.json` — new
- `docs/qa/0.45.1/CEF_PERFORMANCE.json` — new
- `docs/qa/0.45.1/CEF_REVIEWED_REFERENCE_INSTALL.json` — new
- `docs/qa/0.45.1/CEF_REVIEWED_REFERENCE_STATIC.json` — new
- `docs/qa/0.45.1/CHANGESET.json` — new
- `docs/qa/0.45.1/CURRENT_CEF.json` — new
- `docs/qa/0.45.1/DOWNGRADE.json` — new
- `docs/qa/0.45.1/EXTRA.json` — new
- `docs/qa/0.45.1/FINAL-REVIEW.md` — new
- `docs/qa/0.45.1/INSTALLER.json` — new
- `docs/qa/0.45.1/LUA_PERFORMANCE.json` — new
- `docs/qa/0.45.1/PLATFORM.json` — new
- `docs/qa/0.45.1/PRESERVATION.json` — new
- `docs/qa/0.45.1/REGRESSION.json` — new
- `docs/qa/0.45.1/RP-DEVIATIONS.md` — new
- `docs/qa/0.45.1/STATE.json` — new
- `docs/qa/0.45.1/UX_EXISTING_NATIVE32.json` — new
- `docs/qa/0.45.1/UX_RP_NATIVE32.json` — new
- `docs/specs/PA-0.45.0-AUTHOR-BASELINE.json` — new
- `docs/specs/PA-0.45.0-INSTALLER.txt` — new
- `docs/specs/PA-0.45.0-SETTINGS-BASELINE.json` — new
- `docs/specs/PA-0.45.1-AUTHORITATIVE.md` — new
- `install.ps1` — modified
- `moonloader/lib/pa26_author_controller.lua` — modified
- `moonloader/lib/pa26_author_merge.lua` — new
- `moonloader/lib/pa26_author_presets.lua` — modified
- `moonloader/lib/pa26_author_rp.lua` — new
- `moonloader/lib/pa26_binder.lua` — modified
- `moonloader/lib/pa26_bindings.lua` — modified
- `moonloader/lib/pa26_command_policy.lua` — modified
- `moonloader/lib/pa26_copilot.lua` — modified
- `moonloader/lib/pa26_copilot_settings.lua` — modified
- `moonloader/lib/pa26_copilot_ui.lua` — modified
- `moonloader/lib/pa26_core.lua` — modified
- `moonloader/lib/pa26_executor.lua` — modified
- `moonloader/lib/pa26_manual_actions.lua` — modified
- `moonloader/lib/pa26_rp_context.lua` — new
- `moonloader/lib/pa26_rp_context_ui.lua` — new
- `moonloader/lib/pa26_studio.lua` — modified
- `moonloader/lib/pa26_user_files.lua` — modified
- `moonloader/lib/pa26_wheel.lua` — modified
- `moonloader/lib/pa26_wheel_scope.lua` — modified
- `moonloader/lib/pa26_workspace.lua` — modified
- `moonloader/police_assistant_2026.lua` — modified
- `presets/manifest.json` — modified
- `presets/pa-binds.json` — modified
- `presets/pa-settings.json` — modified
- `tests/benchmark_cef0451.js` — new
- `tests/run_tests.py` — modified
- `tests/test_allinone0451.ps1` — new
- `tests/test_author_merge0451.lua` — new
- `tests/test_author_presets.lua` — modified
- `tests/test_cef_adaptive0451.ps1` — new
- `tests/test_cef_install_adaptive0451.ps1` — new
- `tests/test_copilot0451.lua` — new
- `tests/test_copilot_traffic.lua` — modified
- `tests/test_hotfix0404.lua` — modified
- `tests/test_migration0451.lua` — new
- `tests/test_pipeline0451.lua` — new
- `tests/test_rp0451_native32.lua` — new
- `tests/test_rp_context0451.lua` — new
- `tests/test_unified_rp0451.lua` — new
- `tests/test_variables.lua` — modified
- `tests/test_wheels0451.lua` — new
- `tools/audit-preservation0451.py` — new
- `tools/benchmark-cef0451.py` — new
- `tools/benchmark0451.py` — new
- `tools/build-author0451.py` — new
- `tools/build-source0451.py` — new
- `tools/check-downgrade0451.py` — new
- `tools/collect-qa0451.py` — new
- `tools/refresh-release0451.py` — new
- `tools/run-extra0451.py` — new
- `tools/run-installer-shards0451.py` — new
- `tools/run-platform0451.py` — new
- `tools/run-regression0451.py` — new
- `tools/verify-artifacts0451.py` — new
- `tools/verify-package.py` — modified
