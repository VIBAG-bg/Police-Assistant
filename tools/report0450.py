"""Assemble evidence for this local candidate, without exporting live user data."""
from pathlib import Path
import datetime, hashlib, json, re, shutil

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT/'docs/qa/0.45.0'
QA.mkdir(parents=True, exist_ok=True)
def read(name): return json.loads((ROOT/name).read_text('utf-8-sig'))
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def save(name, value): (QA/name).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', 'utf-8')

baseline = read('docs/qa/0.45.0/BASELINE.json')
base = ROOT.parent/'Police-Assistant-2026-v0.44.0-dev'
assert all((base/name).is_file() and sha(base/name)==digest for name,digest in baseline['files'].items()), 'Baseline changed'
frozen = ['cef/assets/hud/pa26-chat-endpoint.js', 'moonloader/lib/pa26_update_platform.lua']
public = [name for name in baseline['files'] if name.startswith('presets/') or name.startswith('docs/sources/')]
assert all(sha(ROOT/name)==baseline['files'][name] for name in frozen+public), 'Protected baseline file changed'
assert sha(ROOT/'moonloader/lib/pa26_update_platform.lua')=='995b131aa0250b7ea407915ad7d109de71a8e43cec088603bc99cc489e60565f'
worker='moonloader/resource/pa26/updater/pa26-update.ps1'
old_worker=(base/worker).read_text('utf-8-sig')
assert (ROOT/worker).read_text('utf-8-sig')==old_worker.replace('wanted-catalog\\.json|banner-bmw','wanted-catalog\\.json|roads\\.bin|banner-bmw',1), 'Worker change must remain limited to the exact graph allowlist entry'
regression = read('tests/REGRESSION-0.45.0.json')
assert all(row['status']=='passed' for row in regression['results'])
for group in ('lua_source_sha256', 'resource_sha256'):
    assert all(sha(ROOT/name)==digest for name,digest in regression[group].items()), 'Runtime changed after regression'
platform = read('tests/PLATFORM0450.json')
assert all(row['status']=='passed' for row in platform['results']), 'Platform regression incomplete'
payload = read('tests/GPS_PATROL_INSTALL0450.json')
roads = read('tests/ROADS_PERFORMANCE0450.json')
assert payload['status']==roads['status']=='passed'
assert payload['manifest_sha256']==sha(ROOT/'INSTALL_MANIFEST.json')
assert payload['installer_sha256']==sha(ROOT/'install.ps1')
assert roads['backend_sha256']==sha(ROOT/'moonloader/lib/pa26_navigation_roads.lua')
assert all(sha(ROOT/'moonloader/lib'/name)==digest for name,digest in roads['source_sha256'].items())
aio=read('tests/ALLINONE_INSTALL0450.json');native_roads=read('tests/ROADS_NATIVE32_0450.json')
assert aio['status']==native_roads['status']=='passed'
assert aio['archive_sha256']==sha(ROOT/'pa26-update.zip') and aio['manifest_sha256']==sha(ROOT/'INSTALL_MANIFEST.json')
assert aio['updater_sha256']==sha(ROOT/worker)
ui = read('tests/UX_NATIVE32_0450.json')
preservation = read('tests/USER_DATA_PRESERVATION0450.json')
browser = read('tests/CEF_BROWSER_RESULTS.json')
assert ui['status']==preservation['status']==browser['status']=='passed'
assert browser['adapter_sha256']==sha(ROOT/'cef/assets/hud/pa26-chat.js')
recovery=read('tests/CEF_RECOVERY0450.json')
assert recovery['status']=='passed' and recovery['adapter_sha256']==sha(ROOT/'cef/assets/hud/pa26-chat.js')
cef_perf=read('tests/CEF_PERFORMANCE0450.json')
native_cef=read('tests/CEF_NATIVE32_RESULTS.json')
assert native_cef['status']=='passed'
assert native_cef['adapter_sha256']==sha(ROOT/'cef/assets/hud/pa26-chat.js')
assert native_cef['bridge_sha256']==sha(ROOT/'moonloader/lib/pa26_chat_bridge.lua')
assert cef_perf['trials']==3
for run in cef_perf['runs']:
    for row in run['rows'].values():
        assert row['editing_ipc']==0
        assert all(row['editing_dom_work'][name]==0 for name in ['textReads','textWrites','styleReads','rectReads'])

game = Path.home()/'AppData/Local/Exsellent Launcher/game'
main = game/'cef/assets/hud/main.js'
source = main.read_text('utf-8') if main.is_file() else ''
contract = read('CEF_CONTRACT.json')
functions = {name: ('function '+name+'(') in source for name in ['_0x52d0', '_0x2db2', 'sendMessageToChat']}
live_sha = sha(main) if main.is_file() else None
assert native_cef['hud_main_sha256']==live_sha, 'Current client changed after isolated IPC verification'
adaptive=read('tests/CEF_ADAPTIVE_STATIC0450.json')
shared=read('tests/CEF_ADAPTIVE_NATIVE32_0450.json')
adaptive_install=read('tests/CEF_ADAPTIVE_INSTALL0450.json')
assert adaptive['status']==shared['status']==adaptive_install['status']=='passed'
assert shared['report']['sha256']==live_sha and shared['report']['allowed']
assert adaptive_install['installer_sha256']==sha(ROOT/'install.ps1')
save('CEF_CURRENT_CONTRACT.json', {'status':'CONTRACT_COMPATIBLE','hud_main_sha256':live_sha,
    'known_reviewed_identity':False,'functional_profile':shared['report']['fingerprint'],
    'shared_static_verifier':'PASS','isolated_x86_runtime_handshake':'PASS',
    'actual_launcher_runtime_handshake':'NOT RUN','actual_game_input_latency':'NOT RUN',
    'live_game_written':False,'second_computer_installation':'NOT RUN'})
preserved = {'status':'passed', 'baseline_head':baseline['head'], 'baseline_files':len(baseline['files']),
             'baseline_unchanged':True, 'frozen_sha256':{name:sha(ROOT/name) for name in frozen},
             'public_presets_and_normative_sources_unchanged':True, 'protected_source_files':len(public),
             'user_data_comparison':preservation,
             'runtime_matches_full_regression':True,'cef_changes_authorized_targeted_hotfix':True}
save('PRESERVATION.json', preserved)
changed=[]
for name,digest in baseline['files'].items():
    target=ROOT/name
    if target.is_file() and sha(target)!=digest:
        changed.append({'path':name,'before_sha256':digest,'after_sha256':sha(target)})
new_runtime=[p.relative_to(ROOT).as_posix() for p in (ROOT/'moonloader').rglob('*')
             if p.is_file() and p.relative_to(ROOT).as_posix() not in baseline['files']]
save('CHANGESET.json',{'baseline_head':baseline['head'],'changed_existing_files':changed,
                      'new_runtime_files':sorted(new_runtime), 'private_config_added':False})
for name in ['REGRESSION-0.45.0.json','UX_NATIVE32_0450.json','USER_DATA_PRESERVATION0450.json',
             'CEF_BROWSER_RESULTS.json','CEF_RECOVERY0450.json','CEF_PERFORMANCE0450.json','LUA_PERFORMANCE0450.json','PLATFORM0450.json',
             'ROADS_PERFORMANCE0450.json','GPS_PATROL_INSTALL0450.json','ALLINONE_INSTALL0450.json','ROADS_NATIVE32_0450.json','CEF_NATIVE32_RESULTS.json','CEF_ADAPTIVE_STATIC0450.json','CEF_ADAPTIVE_NATIVE32_0450.json','CEF_ADAPTIVE_INSTALL0450.json','CEF_ADAPTIVE_JS0450.json','CEF_HANDSHAKE0450.json']:
    shutil.copyfile(ROOT/'tests'/name, QA/name)
state = {'version':'0.45.0', 'at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
         'status':'LOCAL_CANDIDATE_WITH_EXPLICIT_GAME_GATES', 'baseline_head':baseline['head'],
         'lua_groups':len(regression['results']), 'lua_checks':regression['total_checks'],
         'lua_syntax_files':regression['syntax_files'], 'lua_regression':'PASS',
         'native_cpu_ui':ui, 'cef_synthetic_callbacks':browser,
         'installer_updater_fixture_groups':len(platform['results']), 'installer_updater_fixtures':'PASS',
         'platform_fixture_scope':'Eight groups rerun after adding the exact roads.bin worker ownership entry; current full payload also tested separately.',
         'current_payload_fixture':payload, 'road_graph_cpu_trials':roads,
         'all_in_one_install_update':aio,'road_graph_native32':native_roads,
         'current_cef_isolated_transport':native_cef,'cef_bounded_recovery':recovery,
         'packaged_graph_sha256':sha(ROOT/'moonloader/resource/pa26/roads.bin'),
         'updater_worker_change':{'scope':'one exact owned path added: MoonLoader/resource/pa26/roads.bin','sha256':sha(ROOT/worker),
             'old_0.44_worker':'safe rejection; one-time upgrade via the full installer required'},
         'paired_lua_timing_trials':3, 'cef_off_baseline_candidate_timing_trials':3,
         'user_data':preservation, 'chat_bridge_and_js_unchanged':False,'cef_targeted_hotfix':'shared static contract + initialization-only protocol 2 handshake', 'updater_platform_unchanged':True,
         'soak':{'status':'PASS_VIRTUAL_TIME_ONLY','ticks':216000,'virtual_minutes':30,'real_duration_minutes':None,
                 'scope':'accelerated deterministic field service replay; does not exercise real LGPS file or real GTA wall-clock soak'},
         'runtime_features_blocked':{'native_road_pathfinder':'NO_VERIFIED_PRODUCTION_BACKEND',
             'cruise_and_signals':'NO_VERIFIED_PRODUCTION_BACKEND'},
         'experimental_road_route':'PA-bundled, hash-pinned LGPS v1; bounded preparation/search; independent of launcher GPS; live GTA NOT RUN',
         'launcher_waypoint_deletion':'Not patched. Optional PA retention works only for a destination actually observed by PA.',
         'not_run':['actual GTA input latency/FPS/frame-time A-B','15-minute real CEF editing',
                    '30-minute real all-feature soak','actual Win7/Win10 guest acceptance',
                    'actual launcher waypoint retention, road route and Esc/radar drawing',
                    'fresh-install conversion on the affected PC','real server /gnews permission and signature verification'],
         'current_launcher_contract':'CONTRACT_COMPATIBLE_WITH_ISOLATED_RUNTIME_PROOF','cef_adaptive_installation':adaptive_install,'cef_adaptive_static':adaptive,'cef_async_native':shared,
         'installed':False,'published':False,'live_game_written':False,'private_author_presets_exported':False,
         'artifact_verification':'See dist/ARTIFACT_VERIFICATION0450.json after local packaging.'}
save('STATE.json',state)
print('Evidence assembled:',len(regression['results']),'Lua groups;',len(platform['results']),'Windows fixture groups; current contract compatible; actual GTA and second PC acceptance NOT RUN.')
