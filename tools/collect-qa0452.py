"""Collect and verify evidence for the corrected local 0.45.2 distribution."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / 'docs/qa/0.45.2'


def read(path):
    return json.loads((ROOT / path).read_text('utf-8-sig'))


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def save(name, value):
    (QA / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', 'utf-8')


def passed(name):
    result = read('tests/' + name + '.json')
    assert result['status'] == 'passed', name
    result.pop('sandbox', None)
    return result


base = read('docs/qa/0.45.2/BASELINE.json')
assert all(sha(path) == digest for path, digest in base['protected'].items())
regression = read('tests/REGRESSION-0.45.2.json')
assert len(regression['results']) == 217
assert all(row['status'] == 'passed' for row in regression['results'])
for path, digest in (regression['lua_source_sha256'] | regression['resource_sha256']).items():
    assert sha(path) == digest, path
platform = read('tests/PLATFORM0452.json')
assert len(platform['results']) == 7 and all(row['status'] == 'passed' for row in platform['results'])
legacy, rollback = map(passed, ('LEGACY_INSTALL0452', 'INSTALLER_RESULTS'))
assert rollback['installer_sha256'].lower() == sha('install.ps1')
assert rollback['manifest_sha256'].lower() == sha('INSTALL_MANIFEST.json')
assert len(rollback['rollback_after']) == 12

inventory = read('tests/CEF_INVENTORIES_FINAL0452.json')
huds = {}
for key, evidence, runtime in (
    ('F6122', 'original launcher JavaScript and HTML', 'RUNTIME_VERIFIED'),
    ('D7526', 'archived launcher JavaScript and HTML', 'RUNTIME_VERIFIED'),
    ('C4586', 'archived JavaScript with D7526 HTML as a fixture', 'KNOWN_VERIFIED'),
):
    i, n = map(passed, ('CEF_INSTALL_' + key, 'CEF_NATIVE32_' + key))
    entry = inventory[key.lower()]
    assert i['hud_main_sha256'] == n['hud_main_sha256'] == entry['sha256']
    assert i['installer_sha256'] == sha('install.ps1')
    assert i['manifest_sha256'] == sha('INSTALL_MANIFEST.json')
    assert n['test_sha256'] == sha('tests/test_cef_native32.js')
    assert n['runtime_handshake'] == runtime and not n['gta_launched']
    s = passed('CEF_STATIC_' + key) if key != 'C4586' else None
    huds[key] = {'evidence': evidence, 'install': i, 'runtime': n, 'static': s}

browser, adaptive, recovery, performance = map(passed, (
    'CEF_BROWSER_RESULTS', 'CEF_ADAPTIVE_JS0450', 'CEF_RECOVERY0450', 'CEF_PERFORMANCE_FINAL0452'))
assert adaptive['editing_ipc'] == recovery['editing_ipc'] == 0
for trials in performance['comparisons'].values():
    assert len(trials) == 3
    for trial in trials:
        for result in trial.values():
            assert result['editing_ipc'] == 0 and not any(result['editing_dom_work'].values())
assert performance['adapter_sha256'] == sha('cef/assets/hud/pa26-chat.js')
setup, launch, ui, rp_ui = map(passed, (
    'SETUP_WINDOW_RESULTS', 'SETUP_LAUNCH_RESULTS', 'UX_NATIVE32_0452', 'UX_NATIVE32_0451'))
assert launch['compatible_hud'] and ui['views'] == 22
onboarding = next(row for row in regression['results'] if row['test'] == 'test_help0452.lua')

diffs = {}
new = inventory['f6122']['components']
for key in ('d7526', 'c4586'):
    old = inventory[key]['components']
    diffs[key] = {
        'changed': sorted(name for name in old.keys() & new.keys() if old[name] != new[name]),
        'added': sorted(new.keys() - old.keys()),
        'removed': sorted(old.keys() - new.keys()),
    }

acceptance = dict.fromkeys((
    'fresh_install_f6122', 'fresh_install_d7526', 'c4586_js_with_fixture_html', 'incompatible_hud_fallback',
    'missing_cef_fallback', 'preflight_error_and_destination_change', 'reinstallation', 'manual_migration_0440_to_0452',
    'personal_data_preserved', 'welcome_after_migration_once', 'runtime_handshake_success_x86',
    'runtime_handshake_failure_and_recovery_synthetic', 'cef_input_performance_synthetic',
    'installer_rollback_and_file_integrity'), 'PASS')
acceptance.update(original_c4586_full_launcher='NOT RUN', real_gta_input_latency='NOT RUN',
                  actual_server_and_tester_pc='NOT RUN', actual_windows7='NOT RUN')

save('STATE.json', dict(version='0.45.2', baseline_source_zip_sha256=base['archive_sha256'],
    lua_regression='PASS', lua_groups=len(regression['results']), lua_checks=regression['total_checks'],
    installer_updater_fixtures='PASS', installer_rollback_points=rollback['rollback_after'],
    cef_current_contract=huds['F6122']['runtime']['runtime_verifier']['report'],
    legacy_migration=legacy, acceptance=acceptance, protected_sha256=base['protected'],
    published=False, installed=False, live_game_written=False))
save('TEST-RESULTS.json', dict(acceptance=acceptance, lua=regression, platform=platform,
    installer=rollback, legacy=legacy, setup=setup, launch=launch, onboarding=onboarding,
    cef_huds=huds, contract_inventory=inventory, f6122_component_diff=diffs, cef_browser=browser,
    cef_adaptive=adaptive, cef_recovery=recovery, cef_performance=performance, native_ui=ui,
    native_rp_ui=rp_ui))

paths = sorted(path for path, digest in base['files'].items() if path != 'docs/qa/0.45.2/FILES.md' and sha(path) != digest)
paths += ['docs/qa/0.45.2/FILES.md', 'docs/qa/0.45.2/FINAL-REVIEW.md']
paths = sorted(set(paths))
(QA / 'FILES.md').write_text('# Файлы исправленной 0.45.2\n\nСравнение с исходным архивом опубликованной 0.45.2.\n\n'
    + ''.join(f'- `{path}`\n' for path in paths), 'utf-8')

rows = []
for version, trials in performance['comparisons'].items():
    def p95_range(group):
        values = [max(sample['p95_ms'] for key, sample in trial[group]['handlers'].items()
                      if key != 'unrelated_cef') * 1000 for trial in trials]
        return f'{min(values):.2f}–{max(values):.2f}'
    rows.append(f'| {version} | {p95_range("baseline")} | {p95_range("candidate")} |')
timings = '\n'.join(rows)
f, d, c = (huds[key] for key in ('F6122', 'D7526', 'C4586'))
report = f'''# Проверка исправленной Police Assistant 0.45.2

Сборка сверена с опубликованным исходным архивом 0.45.2. [Изменённые файлы](FILES.md) · [Подробные результаты](TEST-RESULTS.json).

## Причина отказа

Исходная 0.45.2 отклоняла `f6122…` с `functional_profile_mismatch` после успешной проверки HTML. Изменились все 42 общих структурных отпечатка относительно `d7526…`, в том числе функции отправки, приёма, фокуса и диалога, декодер, таблица строк, инициализация и обращения к защищённым API. Обход зависимостей теперь дополнительно находит `_0x3e78` и `_0x5374`. В `c4586…` эти зависимости назывались `_0x2db2` и `_0x52d0`. Имена и хеши всех компонентов сохранены в отчёте.

Форматы событий сохранились. Отправка вызывает `HandleHudSendMessage` с одной строкой, регистрация `chat:messages` передаёт цвет, текст и два необязательных значения. Фокус управляется `cef.set_focus`. В новом `hideCursor` добавлена проверка открытого `#casesUI`. В тесте эта панель удерживает фокус. У `f6122…` и `d7526…` проверены оригинальные формы чата, диалог и кнопка отправки. Для `c4586…` восстановлен точный `main.js`, HTML для теста взят из `d7526…`.

Добавлен проверенный структурный профиль. Установщик и его окно запускают один проверяющий код. Он сверяет и допустимость установки тега, а перед записью установщик повторно сверяет проверенные байты HTML. Порядок инициализации, проверка IP и одноразового ключа, подтверждение связи и нативный режим при отказе сохраняются.

## Проверки

| Сценарий | Результат | Доказательство |
|---|---|---|
| Чистая установка `f6122…` | PASS | {f['install']['checks']} проверок. Оба JS, один тег до `main.js`, настройки по умолчанию, повторная установка поверх прежней 0.45.2 |
| Чистая установка `d7526…` | PASS | {d['install']['checks']} проверок на архивном HUD |
| `c4586…` с тестовым HTML | PASS | {c['install']['checks']} проверок установки. Исходный HTML этой версии недоступен |
| Неподдерживаемый или неполный HUD | PASS | Отказ для изменённых событий, разметки, неполного HUD и конфликта тега. Нативная установка сохраняет исходный чат |
| Предварительная проверка CEF | PASS | {setup['checks']} проверок условий и {launch['checks']} проверок обычного окна WinForms. При смене папки окно ожидает её собственный результат |
| Успешное подключение | PASS | Реальный LuaJIT x86 и локальный HTTP. `f6122…` {f['runtime']['checks']}, `d7526…` {d['runtime']['checks']}, `c4586…` {c['runtime']['checks']} проверок. Проверены передача входящих в PA, локальная команда PA, отправка, фокус, рация, фильтры и переносы |
| Отказ подтверждения и восстановление | PASS | {recovery['checks']} синтетических проверок, включая таймаут, потерю связи, повторное подключение и отсутствие дублей |
| Перенос 0.44.0 → 0.45.2 | PASS | {legacy['checks']} проверок на официальном архиве. Обновлены штатные записи, сохранены личные сценарии, профиль и заметки. Проверены конфликт, отказ, восстановление и сохранение настроек при обновлении на условную 0.45.3 |
| Приветствие и панель клавиш | PASS | Проверены отсутствие показа при входе, открытом диалоге и вводе, повторная попытка после прерывания до отрисовки, сохранение после закрытия и ручное открытие. {ui['frames']} нативных кадров mimgui для 22 представлений |
| Откат и целостность | PASS | 12 отдельных точек сбоя в установщике, откат CEF и отдельное восстановление переноса |
| Регрессия Lua | PASS | {len(regression['results'])} групп, {regression['total_checks']:,} проверок. Сценарии RP, колёса, F4/F9, Copilot, патруль и GPS |
| Исходный лаунчер `c4586…` целиком | NOT RUN | Сохранился исходный JavaScript |
| GTA, задержка ввода, игровой сервер и ПК тестера | NOT RUN | V8 использовал имитацию DOM и CEF. Приёмка на реальном клиенте ещё нужна |
| Windows 7 в виртуальной машине | NOT RUN | Проверки установки выполнены на Windows с PowerShell 5.1 |

## Синтетическая производительность ввода

Во всех шести сравнениях обработчики печати, Backspace, выделения и сочетаний Ctrl+A/C/V дали ноль операций с текстом и геометрией DOM и ноль запросов IPC. В отдельном тесте {adaptive['editing_events']:,} событий редактирования также дали 0 IPC. Обработчики CEF побайтно совпадают с 0.45.1 и исходной 0.45.2. Микросекунды в таблице показывают разброс наибольшего p95 по тестовым операциям в трёх повторах. Это время вызова в Node V8.

| База | База, мкс | Кандидат, мкс |
|---|---:|---:|
{timings}

Кандидат подготовлен локально. [Порядок установки и ручная проверка](../../RELEASE-0.45.2.md).
'''
(QA / 'FINAL-REVIEW.md').write_text(report, 'utf-8')
print(f'Corrected 0.45.2 QA verified. {len(paths)} changed files.')
