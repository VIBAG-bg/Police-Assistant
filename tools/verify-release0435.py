"""Gate PA 0.43.5 against its current 0.43.4 baseline and recorded tests."""
from pathlib import Path
import argparse
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', type=Path, required=True)
args = parser.parse_args()
base = args.baseline.resolve()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(name):
    return json.loads((ROOT / 'tests' / name).read_text('utf-8-sig'))


regression = read('REGRESSION-0.43.5.json')
assert len(regression['results']) == 192
assert all(r['status'] == 'passed' for r in regression['results'])
for group in ('lua_source_sha256', 'resource_sha256'):
    for name, expected in regression[group].items():
        assert sha(ROOT / name) == expected, 'Stale regression evidence: ' + name

manifest = json.loads((ROOT / 'INSTALL_MANIFEST.json').read_text('utf-8-sig'))
old_manifest = json.loads((base / 'INSTALL_MANIFEST.json').read_text('utf-8-sig'))
assert manifest['release'] == '0.43.5' and old_manifest['release'] == '0.43.4'
allowed = {'moonloader/lib/pa26_' + name + '.lua' for name in (
    'bindings', 'chat_text', 'copilot', 'copilot_incident', 'copilot_settings',
    'copilot_ui', 'elapsed_clock', 'manual_actions', 'patrol', 'patrol_session',
    'patrol_settings', 'patrol_ui', 'radio_guard', 'report_context', 'studio',
    'vehicle', 'vehicle_settings', 'vehicle_ui')}
allowed |= {'moonloader/police_assistant_2026.lua', 'moonloader/pa26_guard.lua',
            'moonloader/lib/pa26_core.lua', 'cef/assets/hud/pa26-chat.js'}
runtime, changed = {}, []
for prefix, key in [('moonloader', 'files'), ('cef/assets/hud', 'cef_files')]:
    new_paths = {r['path'].replace('\\', '/') for r in manifest[key]}
    old_paths = {r['path'].replace('\\', '/') for r in old_manifest[key]}
    assert new_paths - old_paths == ({'lib/pa26_elapsed_clock.lua'} if key == 'files' else set())
    assert not old_paths - new_paths
    for row in manifest[key]:
        name = prefix + '/' + row['path'].replace('\\', '/')
        current, previous = ROOT / name, base / name
        assert sha(current) == row['sha256'], 'Manifest hash: ' + name
        if not previous.exists() or current.read_bytes() != previous.read_bytes():
            assert name in allowed, 'Unrelated runtime change: ' + name
            changed.append(name)
        runtime[name] = sha(current)
assert set(changed) == allowed, 'Review the exact expected runtime changes'

platform = sha(ROOT / 'moonloader/lib/pa26_update_platform.lua')
assert platform == '995b131aa0250b7ea407915ad7d109de71a8e43cec088603bc99cc489e60565f'
for name in ('moonloader/lib/pa26_update_platform.lua',
             'moonloader/resource/pa26/updater/pa26-update.ps1', 'CEF_CONTRACT.json',
             'moonloader/config/police_assistant_2026.ini'):
    assert (ROOT / name).read_bytes() == (base / name).read_bytes(), name
for row in manifest['setup_files'] + manifest['preset_files']:
    assert (ROOT / row['path']).read_bytes() == (base / row['path']).read_bytes(), row['path']
installer = (ROOT / 'install.ps1').read_text('utf-8-sig')
assert installer.replace("'lib\\pa26_elapsed_clock.lua',", '') == (base / 'install.ps1').read_text('utf-8-sig')

js, native = read('CEF_BROWSER_RESULTS.json'), read('F9_NATIVE32_RESULTS.json')
assert js['status'] == native['status'] == 'passed'
assert js['checks'] == 578 and native['checks'] == 1325
assert native['frames'] == 84 and native['screen_sizes'] == 7
assert native['command_sends'] == 0 and not native['game_written'] and not native['game_started']
assert js['adapter_sha256'] == sha(ROOT / 'cef/assets/hud/pa26-chat.js')
assert js['test_sha256'] == sha(ROOT / 'tests/test_cef_chat.js')
policy = json.loads((ROOT / 'UPDATE_CEF_BASELINE.json').read_text('utf-8-sig'))
assert policy['include_assets'] is True
assert js['adapter_sha256'] in json.dumps(policy)

preservation = read('PRESERVATION0435.json')
assert preservation['status'] == 'passed'
assert preservation['migration_idempotent'] and preservation['public_preset_legacy_values_preserved']
assert preservation['private_mask_template_preserved'] and preservation['source_articles_preserved'] == 1073
ps = read('POWERSHELL0435.json')
assert len(ps) == 9 and all(r['exit_code'] == 0 for r in ps)
ps_evidence = [
    'UPDATER_WORKER_RESULTS.json', 'UPDATE_LEGACY_PATH_RESULTS.json',
    'UPDATE_PROGRESS_RESULTS.json', 'INSTALLER_RESULTS.json',
    'INSTALLER_LEGACY_PATH_RESULTS.json', 'SETUP_RESULTS.json',
    'SETUP_WINDOW_RESULTS.json', 'SETUP_LAUNCH_RESULTS.json', 'AUTHOR_INSTALL_RESULTS.json',
]
for name in ps_evidence:
    assert read(name)['status'] == 'passed', name

worker = read('PREVIOUS_WORKER0435.json')
assert worker['status'] == 'passed' and worker['baseline'] == '0.43.4' and worker['release'] == '0.43.5'
assert {case['environment'] for case in worker['cases']} == {'native', 'launcher'}
assert not worker['real_game_written']
assert worker['package_sha256'] == sha(ROOT / 'pa26-update.zip')
with zipfile.ZipFile(ROOT / 'pa26-update.zip') as archive:
    assert archive.testzip() is None
    update = json.loads(archive.read('pa26-update.json'))
    assert update['version'] == '0.43.5'
    assert len(update['files']) == len(manifest['files']) - 1 + len(manifest['cef_files'])
    assert len(archive.namelist()) == len(update['files']) + 1
    for row in update['files']:
        assert '/config/' not in row['path'].lower()
        data = archive.read(row['path'])
        assert len(data) == row['size'] and hashlib.sha256(data).hexdigest() == row['sha256']
assert (ROOT / 'dist/pa26-update.zip').read_bytes() == (ROOT / 'pa26-update.zip').read_bytes()
with zipfile.ZipFile(ROOT / 'dist/Police-Assistant-v0.43.5.zip') as archive:
    assert archive.testzip() is None
    assert json.loads(archive.read('INSTALL_MANIFEST.json')) == manifest
    assert archive.read('presets/pa-binds.json') == (ROOT / 'presets/pa-binds.json').read_bytes()
    assert archive.read('presets/pa-settings.json') == (ROOT / 'presets/pa-settings.json').read_bytes()
    assert archive.read('presets/baseline.json') == (ROOT / 'presets/baseline.json').read_bytes()
    for name, digest in runtime.items():
        assert hashlib.sha256(archive.read(name)).hexdigest() == digest, name
performance = read('PERFORMANCE0435.json')
assert performance['status'] == 'measured' and not performance['game_launched']

report = {
    'release': '0.43.5', 'baseline': '0.43.4',
    'baseline_commit': 'c7f04fa14da5e840809d953446a446fbf0a863b6',
    'status': 'IMPLEMENTED — IN-GAME VERIFICATION REQUIRED',
    'lua_groups': len(regression['results']), 'lua_checks': regression['total_checks'],
    'syntax_files': regression['syntax_files'], 'cef_checks': js['checks'],
    'native32_checks': native['checks'], 'native32_frames': native['frames'],
    'native32_screen_sizes': native['screen_sizes'], 'powershell_groups': len(ps),
    'previous_worker_checks': worker['checks'], 'legacy_leaf_checks': preservation['legacy_leaf_checks'],
    'source_articles_preserved': preservation['source_articles_preserved'],
    'recognized_stock_template_upgrades': preservation['recognized_stock_template_upgrades'],
    'runtime_sha256': runtime, 'changed_runtime': sorted(changed),
    'updater_platform_sha256': platform, 'update_package_sha256': worker['package_sha256'],
    'source_test_sha256': {'tests/test_f9_validation_native32.lua': sha(ROOT / 'tests/test_f9_validation_native32.lua')},
    'synthetic_performance': performance,
    'personal_data_in_program_update': False, 'public_presets_unchanged': True,
    'original_hud_or_dll_changed': False, 'persistent_document_format_changed': False,
    'publication_authorized': True, 'local_game_written': False, 'game_started': False,
    'live_server_tested': False, 'windows7_vm_tested': False,
    'actual_input_response_latency_measured': False,
    'offobject_server_effect_verified': False,
}
for path in (ROOT / 'tests/VERIFICATION0435.json', ROOT / 'docs/validation-0.43.5.json'):
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
evidence = ROOT / 'tests/evidence/0.43.5'
evidence.mkdir(parents=True, exist_ok=True)
for name in ['REGRESSION-0.43.5.json', 'CEF_BROWSER_RESULTS.json', 'F9_NATIVE32_RESULTS.json',
             'PRESERVATION0435.json', 'POWERSHELL0435.json', 'PERFORMANCE0435.json',
             'PREVIOUS_WORKER0435.json'] + ps_evidence:
    value = read(name)
    if isinstance(value, dict):
        value.pop('sandbox', None)
    (evidence / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'0.43.5 gate passed: {report["lua_groups"]} Lua groups, {report["lua_checks"]} checks; game acceptance pending.')
