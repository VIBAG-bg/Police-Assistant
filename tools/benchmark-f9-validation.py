"""CPU/valid-output comparison of existing preview functions; fake game state."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import statistics
import time

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', type=Path, required=True)
baseline = parser.parse_args().baseline.resolve()
runner = root / 'tests/run_tests.py'
scope = {'__file__': str(runner), '__name__': 'f9_benchmark'}
exec(compile(runner.read_text('utf-8').split('results = []')[0], str(runner), 'exec'), scope)
code = r'''
local settings=require 'pa26_patrol_settings'
local cfg=settings.defaults();cfg.unit='1-L-1'
local profile={name='Victor Auditore',callsign='A-1'}
local state={session='test',ped=1,alive=true,demo=false,area='Doherty',map_square='J-6',city='Сан-Фиерро',local_tag='',
 direction='север',directionKnown=true,gender='male',map_grid=require('pa26_map_grid').defaults(),my_nick='Victor_Auditore',
 radioText={split_enabled=true,max_lines=8,continuation='...'}}
local session=require('pa26_patrol_session').new({settings=function()return cfg end,profile=function()return profile end,
 contacts=function()return{}end,codec=codec})
session.now=1000
local record=assert(session:makeRecord(cfg,state));local keys={'start','resume','finish','crew','periodic'}
local function prepare()for _,key in ipairs(keys)do assert(session:prepareLine(key,record,state,cfg))end end
for _=1,20 do prepare()end
local output={};for _,key in ipairs(keys)do output[#output+1]=assert(session:prepareLine(key,record,state,cfg)).line end
return {run=function()for _=1,300 do prepare()end end,output=table.concat(output,'\n'),previews_per_sample=1500}
'''
rows = []
for label, folder in [('published_0.43.3', baseline), ('local_f9_fix', root)]:
    os.chdir(folder)
    lua = scope['runtime']()
    value = lua.execute(code.encode('utf-8'))
    samples = []
    for _ in range(3):
        started = time.process_time()
        value[b'run']()
        samples.append((time.process_time() - started) * 1000)
    output = value[b'output']
    rows.append({'mode': label, 'samples_cpu_ms': samples, 'median_cpu_ms': statistics.median(samples),
                 'previews_per_sample': 1500, 'output_sha256': hashlib.sha256(output).hexdigest()})
os.chdir(root)
assert rows[0]['output_sha256'] == rows[1]['output_sha256'], 'Valid report text changed'
report = {'status': 'measured', 'timer': 'Python time.process_time; own process CPU', 'valid_report_outputs_identical': True, 'rows': rows,
          'synthetic_game_state': True, 'game_frame_latency_measured': False,
          'limitations': 'CPU aggregate of existing preparation paths; not real GTA/CEF input or physical display latency.'}
(root / 'tests/F9_PREVIEW_PERFORMANCE.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report))
