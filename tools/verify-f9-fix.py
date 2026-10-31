"""Local-only F9 validation gate; reuses the existing PA Lua test runtime."""
from pathlib import Path
import argparse
import hashlib
import json

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', type=Path, required=True)
base = parser.parse_args().baseline.resolve()


def read(name):
    return json.loads((root / 'tests' / name).read_text('utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


regression = read('F9_FULL_REGRESSION.json')
assert len(regression['results']) == 188
assert all(row['status'] == 'passed' for row in regression['results'])
for rows in [regression['lua_source_sha256'], regression['resource_sha256']]:
    for name, expected in rows.items():
        assert sha(root / name) == expected, 'Stale full test: ' + name
native = read('F9_NATIVE32_RESULTS.json')
assert native['status'] == 'passed' and native['command_sends'] == 0
for name, expected in native['source_sha256'].items():
    assert sha(root / name) == expected, 'Stale native UI test: ' + name
preservation = read('F9_PRESERVATION.json')
assert preservation['status'] == 'passed' and preservation['baseline'] == '0.43.3'
assert preservation['accepted_untouched_contract_upgrade'] == []
assert preservation['migration_idempotent'] and preservation['public_preset_legacy_values_preserved']
reproduction = read('F9_REPRODUCTION.json')
assert reproduction['all_reproduced'] and reproduction['alerts_nil_template_reproduced']
for row in reproduction['results']:
    assert sha(root / 'tests' / row['test']) == row['test_sha256']
frozen = ['moonloader/police_assistant_2026.lua', 'moonloader/pa26_guard.lua',
          'moonloader/lib/pa26_chat_bridge.lua', 'moonloader/lib/pa26_cef_assets.lua',
          'moonloader/lib/pa26_chat_text.lua', 'moonloader/lib/pa26_manual_chat.lua',
          'moonloader/lib/pa26_chat_perf.lua', 'moonloader/lib/pa26_bindings.lua',
          'moonloader/lib/pa26_rp_text.lua', 'moonloader/lib/pa26_update_platform.lua',
          'moonloader/resource/pa26/updater/pa26-update.ps1', 'CEF_CONTRACT.json']
frozen += [p.relative_to(root).as_posix() for p in (root / 'cef').rglob('*') if p.is_file()]
for name in frozen:
    assert (root / name).read_bytes() == (base / name).read_bytes(), 'Protected input/updater path changed: ' + name
platform = sha(root / 'moonloader/lib/pa26_update_platform.lua')
assert platform == '995b131aa0250b7ea407915ad7d109de71a8e43cec088603bc99cc489e60565f'
runner = root / 'tests/run_tests.py'
scope = {'__file__': str(runner), '__name__': 'f9_contract_audit'}
exec(compile(runner.read_text('utf-8').split('results = []')[0], str(runner), 'exec'), scope)
lua = scope['runtime']()
lua.execute(r'''
local model=require 'pa26_bindings';local settings=require 'pa26_patrol_settings'
local cfg=settings.defaults();cfg.unit='1-L-1'
local state={session='test',ped=1,alive=true,demo=false,area='Doherty',map_square='J-6',city='Сан-Фиерро',local_tag='',
 direction='север',directionKnown=true,gender='male',my_nick='Victor_Auditore'}
local session=require('pa26_patrol_session').new({settings=function()return cfg end,profile=function()return{name='Officer Test',callsign='A-1'}end,
 contacts=function()return{}end,codec=codec});session.now=1000
local record=assert(session:makeRecord(cfg,state))
local acfg=model.alertDefaults();acfg.enabled=true;acfg.on_duty=true
local spec={name='Test',channel='/r',template='{unit}: {area}.',interval_ms=60000,confirmation=true}
local vcfg=require('pa26_vehicle_settings').defaults();vcfg.traffic_stop_template=spec.template
local ecfg=require('pa26_patrol_event_settings').defaults()
local event=require('pa26_patrol_events').new({settings=function()return ecfg end,codec=codec})
for _,bad in ipairs({false,42,{enabled='yes'}})do
 local s=model.copy(state);s.map_grid=bad;event.state=s
 for _,fn in ipairs({function()return session:prepareLine('start',record,s,cfg)end,
  function()return require('pa26_alerts').prepare('sos',s,acfg,codec,1000,1)end,
  function()return require('pa26_radio_guard').prepare(spec,s,codec,1000,1)end,
  function()return require('pa26_vehicle').preview('traffic_stop',vcfg,s,codec)end,
  function()return event:line({kind='frisk',subject='Officer Test'},ecfg)end})do
   local ok,value,why=pcall(fn);check(ok,tostring(value));eq(value,nil);check(type(why)=='string'and why:find('%S'))
 end
end
'''.encode('utf-8'))
contracts = int(lua.globals()[b'TEST_CHECKS'])
perf = read('F9_PREVIEW_PERFORMANCE.json')
assert perf['valid_report_outputs_identical']
cef = read('CEF_BROWSER_RESULTS.json')
assert cef['status'] == 'passed' and cef['adapter_sha256'] == sha(root / 'cef/assets/hud/pa26-chat.js')
report = {'status': 'FIXED — REQUIRES IN-GAME VERIFICATION', 'baseline_release': '0.43.3',
          'baseline_commit': '42f90ffc3697c73dd68d0de28418e94223148587',
          'lua_groups': len(regression['results']), 'lua_checks': regression['total_checks'],
          'syntax_files': regression['syntax_files'], 'contract_checks': contracts,
          'native32_checks': native['checks'], 'native32_frames': native['frames'], 'native32_screen_sizes': native['screen_sizes'],
          'cef_checks': cef['checks'], 'legacy_leaf_checks': preservation['legacy_leaf_checks'],
          'updater_platform_sha256': platform, 'unchanged_hot_paths': {name: sha(root / name) for name in frozen},
          'preview_performance': perf, 'game_started': False, 'game_written': False, 'github_published': False,
          'persistent_format_changed': False, 'configuration_defaults_changed': False,
          'new_polling_timers_ffi_hooks_or_render_file_io': False,
          'source_sha256': regression['lua_source_sha256']}
for path in [root / 'tests/F9_VERIFICATION.json', root / 'docs/F9-VALIDATION.json']:
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'F9 local gate passed: {report["lua_groups"]} groups / {report["lua_checks"]} checks; {contracts} caller-contract checks; updater/CEF unchanged.')
