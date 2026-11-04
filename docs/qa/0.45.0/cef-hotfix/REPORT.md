# PA 0.45.0 — итог адаптивного CEF hotfix

Снимок проверки перед публикацией. Активная GTA и другой ПК не изменялись. Состояние выпуска — на странице релизов GitHub.

## Причина и решение

Старые установщик и runtime независимо принимали только один SHA. Теперь оба используют один read-only анализатор PA и реестр. Известный файл проходит быстрый путь; новый хеш допускается при совпадении 42 проверенных компонентов контракта и DOM. Перед включением функций обязателен протокол 2 hello/ack/confirm/ready. Собственный тег располагается перед main.js; исходный JS не заменяется.

Профиль фиксирует полные тела нужных функций и зависимостей, таблицу/декодер, регистрацию событий и защищённые обращения; имена или отдельные строки не служат доказательством. Комментарии, пробелы, приватные переименования и проверенное независимое изменение функции вне контракта допускаются. Иная обфускация/структура могут потребовать нового профиля. JavaScript лаунчера установщиком не исполняется.

## Проверки

| Проверка | Статус | Доказательство |
| --- | --- | --- |
| Lua-регрессии | PASS | 209 групп; 13,235,232 проверок; 398 синтаксических Lua-файла |
| Статическая совместимость | PASS | 39 проверок / 17 случаев: текущий d7526…, новые совместимые SHA, повреждённые интерфейсы/DOM/payload, отсутствие файлов |
| Настоящий x86 фоновый анализ | PASS | 100004 проверок; единственное задание и кэш |
| x86 LuaSocket + текущий send-handler в изолированном V8 | PASS | 113 проверок, протокол 2, преобразования, переносы, reconnect, отсутствие дублей |
| Поздний CEF и ограниченное восстановление | PASS | 74 проверок; 30 минут виртуального отказа; без редактирования текста/IPC от 40000 событий ввода |
| Установка текущего неизвестного SHA | PASS | 21 проверка: чистая установка, повтор, поздний тег, native-only отказ, личные файлы |
| Windows installer/updater | PASS | 8 групп; 12 прерываний и откат на самостоятельном тестовом пакете с идентичным кодом установщика; production-реестры и ограничения worker сохранены |
| Текущий полный payload | PASS | All-in-One 47; установленный manifest 171 |
| Native CPU UI | PASS | 1064 кадров; 19 видов; 7 размеров; включая диагностику CEF |
| Старый реестр | PASS (fixture) | Прежний SHA сохранён; быстрый путь и KNOWN_VERIFIED проверены |
| Полный старый launcher c458… | BLOCKED | Файл недоступен; полный повтор реального старого контракта не заявляется |
| Реальные GTA FPS / frametime / задержка ввода / 15 минут | NOT RUN | Требуется пользовательская проверка в игре |
| Установка на другом ПК / Win7, Win10 guest | NOT RUN | Не выполнялась по заданию |
| Неразрешённые изменения GPS/данных/обновлятора | PASS | Хеши совпадают с All-in-One RC |
| Остаточные ошибки автоматического прогона | FAIL: 0 | Все перечисленные завершённые проверки проходят |

## Производительность

Реальный x86 запуск фонового анализатора: 2558.96 мс, вне игрового потока. Вызовы после кэширования не запускают процесс, не читают файлы и не пересчитывают хеш. Пакет из 100000 кэшированных вызовов ниже разрешения использованного socket-таймера; это не обещание нулевой игровой задержки.

| Синтетический callback, медиана p95 трёх прогонов | PA OFF, мс | До (0.44), мс | После (0.45), мс |
| --- | ---: | ---: | ---: |
| russian | 0.001500 | 0.001400 | 0.001400 |
| english | 0.000200 | 0.000200 | 0.000300 |
| backspace | 0.001500 | 0.002400 | 0.001500 |
| word_selection | 0.000300 | 0.001200 | 0.000200 |
| drag_selection | 0.000400 | 0.000600 | 0.000400 |
| double_click | 0.000400 | 0.000400 | 0.000300 |
| ctrl_a | 0.001400 | 0.001700 | 0.000500 |
| ctrl_c | 0.000300 | 0.000400 | 0.000400 |
| ctrl_v | 0.000300 | 0.000400 | 0.000400 |
| long_message | 0.000200 | 0.000200 | 0.000200 |

Среда: Node V8 и синтетический DOM; после — с подтверждённым протоколом 2. Во всех прогонах 0 editing IPC и 0 чтений/записей текста, style/layout-запросов от обычного редактирования. Полные worst samples сохранены в JSON. Нельзя переносить эти значения на end-to-end ввод или FPS GTA.

## Сохранение

GPS-модули, roads.bin, рендер карты, /setmark policy, патруль, бинды, колесо, RP, половые формы, параметры и публичные авторские пресеты совпадают с предыдущим локальным All-in-One RC. В основном Lua изменены только подключение проверяющего задания, передача диагностики и cleanup. F4/F9 не переработаны; добавлена только сводка в существующем разделе CEF. Защищённый bootstrap: `995b131aa0250b7ea407915ad7d109de71a8e43cec088603bc99cc489e60565f`. Worker обновлятора побайтно сохранён относительно предыдущего RC.

Правила раскладки сохранены по уточнению владельца: преобразуется имя команды с точкой; обычная речь, имена и аргументы не переводятся автоматически.

## Точный список изменённых программных и тестовых файлов

- `CEF_CONTRACT.json`
- `INSTALL_MANIFEST.json`
- `UPDATE_CEF_BASELINE.json`
- `cef/assets/hud/pa26-chat.js`
- `install.ps1`
- `moonloader/lib/pa26_cef_assets.lua`
- `moonloader/lib/pa26_cef_compat.lua`
- `moonloader/lib/pa26_cef_contract.lua`
- `moonloader/lib/pa26_cef_job.lua`
- `moonloader/lib/pa26_chat_bridge.lua`
- `moonloader/lib/pa26_studio.lua`
- `moonloader/police_assistant_2026.lua`
- `tests/benchmark_cef0450.js`
- `tests/run_tests.py`
- `tests/support/fixture.lua`
- `tests/support/installer-cef-fixture.ps1`
- `tests/test_cef_adaptive0450.js`
- `tests/test_cef_adaptive0450.lua`
- `tests/test_cef_adaptive0450.ps1`
- `tests/test_cef_adaptive_native32.lua`
- `tests/test_cef_assets.lua`
- `tests/test_cef_chat.js`
- `tests/test_cef_contract0440.lua`
- `tests/test_cef_contract_native32.lua`
- `tests/test_cef_install_adaptive0450.ps1`
- `tests/test_cef_native32.js`
- `tests/test_cef_recovery0450.js`
- `tests/test_installer.ps1`
- `tests/test_ux0450_native32.lua`
- `tools/benchmark-cef0450.py`
- `tools/build-cef-contract0450.py`
- `tools/cef-contract-engine.ps1`
- `tools/final-review0450.py`
- `tools/inspect-cef0450.ps1`
- `tools/performance-report0450.py`
- `tools/publish-release.ps1`
- `tools/report-cef-hotfix0450.py`
- `tools/report0450.py`
- `tools/run-installer-shards0450.py`

Документация и доказательства:
- `CHANGELOG.md`
- `README.md`
- `docs/ALL-IN-ONE-0.45.0.md`
- `docs/CEF-ADAPTIVE-0.45.0.md`
- `docs/INSTALLATION.md`
- `docs/PERFORMANCE-0.45.0.md`
- `docs/RELEASE-0.45.0.md`
- `docs/UPDATES.md`
- `docs/qa/0.45.0/ALLINONE_INSTALL0450.json`
- `docs/qa/0.45.0/CEF_ADAPTIVE_INSTALL0450.json`
- `docs/qa/0.45.0/CEF_ADAPTIVE_JS0450.json`
- `docs/qa/0.45.0/CEF_ADAPTIVE_NATIVE32_0450.json`
- `docs/qa/0.45.0/CEF_ADAPTIVE_STATIC0450.json`
- `docs/qa/0.45.0/CEF_BROWSER_RESULTS.json`
- `docs/qa/0.45.0/CEF_CURRENT_CONTRACT.json`
- `docs/qa/0.45.0/CEF_HANDSHAKE0450.json`
- `docs/qa/0.45.0/CEF_NATIVE32_RESULTS.json`
- `docs/qa/0.45.0/CEF_PERFORMANCE0450.json`
- `docs/qa/0.45.0/CEF_RECOVERY0450.json`
- `docs/qa/0.45.0/CHANGESET.json`
- `docs/qa/0.45.0/CI-PORTABILITY.md`
- `docs/qa/0.45.0/FINAL-REVIEW.md`
- `docs/qa/0.45.0/GPS_PATROL_INSTALL0450.json`
- `docs/qa/0.45.0/LUA_PERFORMANCE0450.json`
- `docs/qa/0.45.0/PLATFORM0450.json`
- `docs/qa/0.45.0/PRESERVATION.json`
- `docs/qa/0.45.0/REGRESSION-0.45.0.json`
- `docs/qa/0.45.0/STATE.json`
- `docs/qa/0.45.0/UX_NATIVE32_0450.json`
- `docs/qa/0.45.0/cef-hotfix/BEFORE.json`
- `docs/qa/0.45.0/cef-hotfix/CEF_ADAPTIVE_INSTALL0450.json`
- `docs/qa/0.45.0/cef-hotfix/CEF_ADAPTIVE_JS0450.json`
- `docs/qa/0.45.0/cef-hotfix/CEF_ADAPTIVE_NATIVE32_0450.json`
- `docs/qa/0.45.0/cef-hotfix/CEF_ADAPTIVE_STATIC0450.json`
- `docs/qa/0.45.0/cef-hotfix/CEF_HANDSHAKE0450.json`
- `docs/qa/0.45.0/cef-hotfix/CEF_NATIVE32_RESULTS.json`
- `docs/qa/0.45.0/cef-hotfix/CEF_PERFORMANCE0450.json`
- `docs/qa/0.45.0/cef-hotfix/CEF_RECOVERY0450.json`
- `docs/qa/0.45.0/cef-hotfix/CONTRACT_REVIEW.json`
- `docs/qa/0.45.0/cef-hotfix/FROZEN_FINAL.json`
- `docs/qa/0.45.0/cef-hotfix/INSTALLER_RESULTS.json`
- `docs/qa/0.45.0/cef-hotfix/PLATFORM0450.json`
- `docs/qa/0.45.0/cef-hotfix/PROFILE_INVENTORY.json`
- `docs/qa/0.45.0/cef-hotfix/REPORT.md`
- `docs/qa/0.45.0/cef-hotfix/STATE.json`
- `docs/qa/0.45.0/cef-hotfix/UX_NATIVE32_0450.json`

Документация и пересозданные JSON-доказательства дополнительно находятся в docs/qa/0.45.0 и этой папке; SHA файлов и архивов проверяются при упаковке.

## Следующая приёмка

Практический [чек-лист второго ПК и пояснения](../../../CEF-ADAPTIVE-0.45.0.md). Не отключать SHA/профильные защиты. `CONTRACT_COMPATIBLE` — статическая совместимость; `RUNTIME_VERIFIED` означает подтверждение конкретного запущенного моста и адаптера, а не выполнение всех игровых сценариев.

Со старого 0.44 worker нужен однократный полный установщик. Универсальный update ZIP сохраняет CEF-ассеты на месте и не заменяет необходимую начальную установку нового адаптера. QA выполнялся до публикации; активная игра не изменялась.
