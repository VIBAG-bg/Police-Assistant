"""Verify saved local evidence against the exact runtime being packaged.

Run after build-update.ps1 and copying reports to tests/evidence/0.43.3.
This validates provenance, not GTA input latency or server behaviour.
"""
from pathlib import Path
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'tests/evidence/0.43.3'


def read(name):
    return json.loads((EVIDENCE / name).read_text('utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def hashes_match(rows):
    for name, expected in rows.items():
        assert sha(ROOT / name) == expected, 'Stale evidence: ' + name


lua = read('REGRESSION.json')
hashes_match(lua['lua_source_sha256'])
hashes_match(lua['resource_sha256'])
assert len(lua['results']) == 186
assert all(row['status'] == 'passed' for row in lua['results'])
assert lua['total_checks'] == sum(row['checks'] for row in lua['results'])

adapter = sha(ROOT / 'cef/assets/hud/pa26-chat.js')
bridge = sha(ROOT / 'moonloader/lib/pa26_chat_bridge.lua')
js, native = read('CEF_BROWSER_RESULTS.json'), read('CEF_NATIVE32_RESULTS.json')
assert js['status'] == native['status'] == 'passed'
assert js['adapter_sha256'] == native['adapter_sha256'] == adapter
assert js['test_sha256'] == sha(ROOT / 'tests/test_cef_chat.js')
assert native['test_sha256'] == sha(ROOT / 'tests/test_cef_native32.js')
assert native['bridge_sha256'] == bridge
for field, path in [('manual_sha256', 'moonloader/lib/pa26_manual_chat.lua'),
                    ('rp_sha256', 'moonloader/lib/pa26_rp_text.lua'),
                    ('chat_text_sha256', 'moonloader/lib/pa26_chat_text.lua')]:
    assert native[field] == sha(ROOT / path), 'Stale native integration: ' + field
assert not native['gta_launched'] and not native['actual_game_server_contacted']

browser = read('BROWSER_PERFORMANCE.json')
soak = next(row for row in browser['rows'] if row['mode'] == '0.43.3')
assert soak['elapsed_ms'] >= 900000 and soak['adapter_sha256'] == adapter
assert soak['selection_checks'] >= 1000 and soak['exactly_once_checks'] >= 2000
assert browser['live_gta_measured'] is False
bench = read('LUA_BENCHMARK.json')
hashes_match(bench['source_sha256'])

repro = read('REPRODUCTION.json')
assert repro['all_reproduced'] and len(repro['results']) == 5
for row in repro['results']:
    assert row['reproduced'] and row['new_test_sha256'] == sha(ROOT / 'tests' / row['test'])
preservation = read('PRESERVATION.json')
assert preservation['status'] == 'passed' and preservation['migration_idempotent']
assert preservation['accepted_untouched_contract_upgrade'] == []
assert preservation['source_articles_preserved'] == 1073
assert preservation['public_preset_legacy_values_preserved']

worker, installer = read('PREVIOUS_WORKER.json'), read('INSTALLER.json')
assert worker['status'] == installer['status'] == 'passed'
assert worker['package_sha256'] == sha(ROOT / 'pa26-update.zip')
assert {case['environment'] for case in worker['cases']} == {'native', 'launcher'}
assert installer['manifest_sha256'].lower() == sha(ROOT / 'INSTALL_MANIFEST.json')
assert installer['installer_sha256'].lower() == sha(ROOT / 'install.ps1')
assert installer['preserved_personal_files'] and installer['personal_backups']
assert installer['native_install'] and installer['cef_install']
assert not worker['real_game_written'] and not installer['real_game_written']
with zipfile.ZipFile(ROOT / 'pa26-update.zip') as archive:
    assert archive.testzip() is None
    manifest = json.loads(archive.read('pa26-update.json'))
    assert manifest['version'] == '0.43.3' and len(manifest['files']) == 130
    assert hashlib.sha256(archive.read('cef/assets/hud/pa26-chat.js')).hexdigest() == adapter
    assert all('/config/' not in row['path'].lower() for row in manifest['files'])
    for row in manifest['files']:
        data = archive.read(row['path'])
        assert len(data) == row['size'] and hashlib.sha256(data).hexdigest() == row['sha256']

report = {
    'release': '0.43.3', 'base_release': '0.43.2', 'date': '2026-10-31',
    'status': 'local_engineering_checks_passed_game_acceptance_pending',
    'lua_groups': len(lua['results']), 'lua_checks': lua['total_checks'],
    'syntax_files': lua['syntax_files'], 'cef_js_checks': js['checks'],
    'cef_native32_checks': native['checks'], 'previous_worker_checks': worker['checks'],
    'installer_rollback_points': installer['rollback_after'],
    'legacy_leaf_checks': preservation['legacy_leaf_checks'],
    'source_articles_preserved': preservation['source_articles_preserved'],
    'baseline_failures_reproduced': len(repro['results']),
    'cef_adapter_sha256': adapter, 'cef_bridge_sha256': bridge,
    'update_package_sha256': worker['package_sha256'],
    'browser_soak': soak, 'browser_limitations': browser['limitations'],
    'lua_benchmark': bench, 'real_game_written': False, 'game_started': False,
    'live_server_tested': False, 'windows7_vm_tested': False,
    'publication_authorized': True, 'local_installation_authorized': False,
    'performance_acceptance': 'Pending 15-minute comparison in the actual Exsellent client. Rare browser spikes remain recorded; no claim of zero added game latency.',
    'evidence_sha256': {p.name: sha(p) for p in sorted(EVIDENCE.glob('*.json'))}
}
for path in [ROOT / 'docs/validation-0.43.3.json', ROOT / 'tests/VERIFICATION0433.json']:
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'0.43.3 evidence matches runtime: {report["lua_groups"]} groups, {report["lua_checks"]} checks; game acceptance pending.')
