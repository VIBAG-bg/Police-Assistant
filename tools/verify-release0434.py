"""Gate the 0.43.4 release against published 0.43.3 and the reviewed F9 patch."""
from pathlib import Path
import argparse
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', type=Path, required=True)
parser.add_argument('--fix-reference', type=Path, required=True)
args = parser.parse_args()
base, reference = args.baseline.resolve(), args.fix_reference.resolve()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(name):
    return json.loads((ROOT / 'tests' / name).read_text('utf-8-sig'))


regression = read('REGRESSION-0.43.4.json')
assert len(regression['results']) == 188 and all(r['status'] == 'passed' for r in regression['results'])
for rows in (regression['lua_source_sha256'], regression['resource_sha256']):
    for name, expected in rows.items():
        assert sha(ROOT / name) == expected, 'Stale test result: ' + name
fixed = {'moonloader/lib/pa26_' + name + '.lua' for name in
         ['alerts', 'map_grid', 'patrol_events', 'patrol_session', 'patrol_ui', 'radio_guard', 'report_context', 'vehicle']}
versions = {'moonloader/police_assistant_2026.lua': 2, 'moonloader/pa26_guard.lua': 1, 'moonloader/lib/pa26_core.lua': 1}
manifest = json.loads((ROOT / 'INSTALL_MANIFEST.json').read_text('utf-8-sig'))
old_manifest = json.loads((base / 'INSTALL_MANIFEST.json').read_text('utf-8-sig'))
assert manifest['release'] == '0.43.4' and old_manifest['release'] == '0.43.3'
runtime = {}
for prefix, key in [('moonloader', 'files'), ('cef/assets/hud', 'cef_files')]:
    assert {r['path'] for r in manifest[key]} == {r['path'] for r in old_manifest[key]}
    for row in manifest[key]:
        name = prefix + '/' + row['path'].replace('\\', '/')
        current, old = (ROOT / name).read_bytes(), (base / name).read_bytes()
        assert hashlib.sha256(current).hexdigest() == row['sha256']
        if name in fixed:
            assert current == (reference / name).read_bytes(), 'Reviewed fix changed: ' + name
        elif name in versions:
            assert current.count(b'0.43.4') == versions[name]
            assert current.replace(b'0.43.4', b'0.43.3') == old, 'Change exceeds version bump: ' + name
        else:
            assert current == old, 'Unrelated runtime changed: ' + name
        runtime[name] = hashlib.sha256(current).hexdigest()
platform = sha(ROOT / 'moonloader/lib/pa26_update_platform.lua')
assert platform == '995b131aa0250b7ea407915ad7d109de71a8e43cec088603bc99cc489e60565f'
assert (ROOT / 'install.ps1').read_bytes() == (base / 'install.ps1').read_bytes()
for row in manifest['setup_files'] + manifest['preset_files']:
    assert (ROOT / row['path']).read_bytes() == (base / row['path']).read_bytes()
assert (ROOT / 'UPDATE_CEF_BASELINE.json').read_bytes() == (base / 'UPDATE_CEF_BASELINE.json').read_bytes()
native, js = read('NATIVE32-0.43.4.json'), read('CEF_BROWSER_RESULTS.json')
assert native['status'] == js['status'] == 'passed'
assert native['checks'] == 1260 and native['frames'] == 84 and native['command_sends'] == 0
for name, digest in native['source_sha256'].items():
    assert sha(ROOT / name) == digest
assert js['adapter_sha256'] == runtime['cef/assets/hud/pa26-chat.js']
assert js['test_sha256'] == sha(ROOT / 'tests/test_cef_chat.js')
preservation = read('PRESERVATION-0.43.4.json')
assert preservation['release'] == '0.43.4' and preservation['baseline'] == '0.43.3'
assert preservation['status'] == 'passed' and preservation['accepted_untouched_contract_upgrade'] == []
assert preservation['migration_idempotent'] and preservation['public_preset_legacy_values_preserved']
worker = read('PREVIOUS_WORKER0434.json')
assert worker['status'] == 'passed' and worker['baseline'] == '0.43.3' and worker['release'] == '0.43.4'
assert {case['environment'] for case in worker['cases']} == {'native', 'launcher'}
assert worker['package_sha256'] == sha(ROOT / 'pa26-update.zip') and not worker['real_game_written']
with zipfile.ZipFile(ROOT / 'pa26-update.zip') as archive:
    assert archive.testzip() is None
    update = json.loads(archive.read('pa26-update.json'))
    assert update['version'] == '0.43.4' and len(update['files']) == 130
    assert len(archive.namelist()) == 131
    for row in update['files']:
        assert '/config/' not in row['path'].lower()
        data = archive.read(row['path'])
        assert hashlib.sha256(data).hexdigest() == row['sha256'] and len(data) == row['size']
report = {'release': '0.43.4', 'baseline': '0.43.3',
          'baseline_commit': '42f90ffc3697c73dd68d0de28418e94223148587',
          'reviewed_fix_commit': '0ef276913c26842865641ee252414d777c52450a',
          'status': 'local_checks_passed_game_acceptance_pending',
          'lua_groups': len(regression['results']), 'lua_checks': regression['total_checks'],
          'syntax_files': regression['syntax_files'], 'native32_checks': native['checks'],
          'native32_frames': native['frames'], 'native32_screen_sizes': native['screen_sizes'],
          'cef_checks': js['checks'], 'previous_worker_checks': worker['checks'],
          'legacy_leaf_checks': preservation['legacy_leaf_checks'],
          'source_articles_preserved': preservation['source_articles_preserved'],
          'runtime_sha256': runtime, 'updater_platform_sha256': platform,
          'update_package_sha256': worker['package_sha256'],
          'cef_changed': False, 'unrelated_runtime_changed': False, 'personal_data_in_update': False,
          'configuration_defaults_changed': False, 'persistent_format_changed': False,
          'publication_authorized': True, 'local_game_written': False, 'game_started': False,
          'live_server_tested': False, 'windows7_vm_tested': False,
          'acceptance': 'Automated and native component checks passed; actual GTA acceptance remains pending.'}
for path in [ROOT / 'tests/VERIFICATION0434.json', ROOT / 'docs/validation-0.43.4.json']:
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'0.43.4 gate passed: {report["lua_groups"]} groups, {report["lua_checks"]} checks; reviewed F9 logic, CEF and personal data preserved.')
