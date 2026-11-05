"""Collect the verification results of the exact local 0.45.2 candidate."""
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


base = read('docs/qa/0.45.2/BASELINE.json')
regression = read('tests/REGRESSION-0.45.2.json')
assert len(regression['results']) == 217
assert all(row['status'] == 'passed' for row in regression['results'])
for path, digest in (regression['lua_source_sha256'] | regression['resource_sha256']).items():
    assert sha(path) == digest, path
assert all(sha(path) == digest for path, digest in base['protected'].items())
assert sha('presets/pa-binds.json') == base['files']['presets/pa-binds.json']
previous = ROOT.parent / 'Police-Assistant-2026-v0.45.1-dev'
main = 'moonloader/police_assistant_2026.lua'
old_main = (previous / main).read_bytes()
assert hashlib.sha256(old_main).hexdigest() == base['files'][main]


def window_hook(text):
    start = text.index(b'function onWindowMessage(message, wparam, lparam)')
    return text[start:text.index(b'function onScriptTerminate(', start)]


assert window_hook(old_main) == window_hook((ROOT / main).read_bytes())
old_settings = json.loads((previous / 'presets/pa-settings.json').read_text('utf-8'))
settings = read('presets/pa-settings.json')
help_settings = settings['settings']['data']['settings'].pop('help')
assert settings == old_settings
assert help_settings == dict(welcome=False, visible=True, opacity=.74, scale=1)

legacy = read('tests/LEGACY_INSTALL0452.json')
platform = read('tests/PLATFORM0452.json')
rollback = read('tests/INSTALLER_RESULTS.json')
assert legacy['status'] == rollback['status'] == 'passed'
assert rollback['installer_sha256'].lower() == sha('install.ps1')
assert rollback['manifest_sha256'].lower() == sha('INSTALL_MANIFEST.json')
assert platform['version'] == rollback['release'] == '0.45.2'
assert len(platform['results']) == 7 and all(row['status'] == 'passed' for row in platform['results'])
assert len(rollback['rollback_after']) == 12

names = {
    'native_ui': 'UX_NATIVE32_0452.json', 'native_rp': 'UX_NATIVE32_0451.json',
    'native_gps': 'ROADS_NATIVE32_0450.json', 'cef_browser': 'CEF_BROWSER_RESULTS.json',
    'cef_adaptive': 'CEF_ADAPTIVE_JS0450.json', 'cef_recovery': 'CEF_RECOVERY0450.json',
    'cef_static': 'CEF_ADAPTIVE_STATIC0450.json', 'cef_install': 'CEF_ADAPTIVE_INSTALL0450.json',
    'cef_native': 'CEF_NATIVE32_RESULTS.json',
}
results = {name: read('tests/' + file) for name, file in names.items()}
for result in results.values():
    assert result['status'] == 'passed', result
    result.pop('sandbox', None)
current = read('tests/CURRENT_CEF0452.json')
ui, roads = results['native_ui'], results['native_gps']
cef, native = results['cef_browser'], results['cef_native']
assert results['cef_adaptive']['editing_ipc'] == results['cef_recovery']['editing_ipc'] == 0
assert native['hud_main_sha256'] == 'd7526b3e76b4d9492407e77728be4ac8383b535600e62a3885fd1c785a4d29d2'
assert ui['views'] == 22 and roads['cases'] == 5
assert current['sha256'] and current['runtime'] == 'NOT_RUN'

save('STATE.json', dict(
    version='0.45.2', baseline_source_zip_sha256=base['archive_sha256'],
    lua_regression='PASS', lua_groups=len(regression['results']),
    lua_checks=regression['total_checks'], lua_syntax_files=regression['syntax_files'],
    installer_updater_fixtures='PASS', platform_fixture_groups=len(platform['results']),
    installer_rollback_points=rollback['rollback_after'], legacy_migration=legacy,
    native_ui_frames=ui['frames'] + results['native_rp']['frames'],
    cef_native_ipc='PASS', cef_current_contract=current,
    protected_sha256=base['protected'], window_hook_unchanged=True, author_binds_unchanged=True,
    actual_gta='NOT RUN', actual_cef_input_latency='NOT RUN', actual_windows7='NOT RUN',
    published=False, installed=False, live_game_written=False,
))
rollback.pop('sandbox', None)
save('TEST-RESULTS.json', dict(lua=regression, platform=platform, installer=rollback,
                              legacy=legacy, cef_current=current, **results))

paths = set(base['files'])
for folder, pattern in (('presets', '*.json'), ('tools', '*'), ('tests', '*'), ('docs/qa/0.45.2', '*')):
    paths.update(path.relative_to(ROOT).as_posix() for path in (ROOT / folder).glob(pattern)
                 if path.is_file() and (folder != 'tests' or path.suffix in {'.lua', '.py', '.ps1', '.js'}))
paths.update({'moonloader/lib/pa26_help.lua', 'docs/RELEASE-0.45.2.md', 'docs/qa/0.45.2/FILES.md'})
new = sorted(paths - set(base['files']))
changed = sorted(path for path in base['files'] if sha(path) != base['files'][path])
listing = '# Файлы 0.45.2\n\nПути указаны от корня исходников. Архивы и контрольные суммы находятся в `dist`.\n'
for title, group in (('Изменены', changed), ('Добавлены', new)):
    listing += '\n## ' + title + '\n\n' + ''.join(f'- `{path}`\n' for path in group)
(QA / 'FILES.md').write_text(listing, 'utf-8')

report = f'''# Проверка Police Assistant 0.45.2

Основа сверена с исходным архивом 0.45.1. Для переноса использованы установочный архив и идентификаторы официальной 0.44.0. [Список файлов](FILES.md) · [Результаты по тестам](TEST-RESULTS.json).

| Проверка | Результат | Объём |
|---|---|---|
| Lua и регрессия | PASS | {len(regression['results'])} групп, {regression['total_checks']:,} проверок, {regression['syntax_files']} файлов синтаксиса |
| Инструкции и панель | PASS | Приветствие, повторное открытие, назначенные клавиши, прозрачность, масштаб, перенос и скрытие. {ui['frames']} кадров нативного mimgui x86 при 7 размерах экрана |
| Ручной перенос | PASS | {legacy['checks']} проверок. Чистая установка, подтверждение версии, правки штатных и отдельные личные записи, коллизии, повторная установка, отказ и условная 0.45.3 |
| Установщик и откат | PASS | {len(platform['results'])} групп Windows PowerShell 5.1 и 12 точек отката. В отдельной проверке перенос прерывается, а следующий запуск восстанавливает исходные байты |
| CEF | PASS | {cef['checks']} браузерных проверок, {native['checks']} проверок x86/IPC, {results['cef_static']['checks']} проверок контракта и {results['cef_install']['checks']} проверка установки. 40 000 событий ввода в синтетике дали 0 IPC-запросов |
| GPS | PASS | {roads['checks']} нативная проверка x86, 4 допустимых источника графа и отказ для повреждённого. Граф и код навигации совпадают с 0.45.1 |
| GTA, задержка ввода, Windows 7 | NOT RUN | Нативные тесты LuaJIT, V8 и mimgui выполнены вне игры |

Старый автообновлятор 0.44.0 безопасно отклоняет архив с путём к графу дорог. Для перехода используется полный установщик. У рабочего автообновлятора проверена передача только программных файлов. Новая миграция в обновление не входит.

Приоритет у личных записей. Если происхождение старого бинда неясно, он сохраняется в «Свои бинды». При неподтверждённых файлах 0.44.0 доступна обычная установка. Повреждённый, неполный или слишком большой набор останавливает перенос до записи. Можно продолжить с прежними данными.

Совместимый CEF проверен на архивном HUD `d7526…`. HUD текущего лаунчера `{current['sha256'][:8]}…` даёт `{current['reason']}`. Подключение CEF при чистой установке с этим HUD имеет статус **{'BLOCKED' if not current['allowed'] else 'NOT RUN'}**. Предусмотрен нативный режим. Адаптер, обработчик ввода и защита обновлятора сверены побайтно с 0.45.1.

Кандидат подготовлен локально. [Приёмка в GTA и команды сборки](../../RELEASE-0.45.2.md).
'''
(QA / 'FINAL-REVIEW.md').write_text(report, 'utf-8')
print(f'QA verified. {len(changed)} changed and {len(new)} new files.')
