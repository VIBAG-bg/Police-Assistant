"""Reproduce the final regression tests against untouched published 0.43.3."""
from pathlib import Path
import argparse
import hashlib
import json
import os

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', type=Path, required=True)
baseline = parser.parse_args().baseline.resolve()
runner = root / 'tests/run_tests.py'
scope = {'__file__': str(runner), '__name__': 'f9_reproduction'}
exec(compile(runner.read_text('utf-8').split('results = []')[0], str(runner), 'exec'), scope)
rows = []
for name in ['test_f9_report_validation.lua', 'test_report_template_validation.lua']:
    os.chdir(baseline)
    lua = scope['runtime']()
    try:
        lua.execute((root / 'tests' / name).read_bytes())
    except Exception as exc:
        error = str(exc)
        reproduced = 'pa26_map_grid.lua:83' in error and "'template'" in error and 'nil value' in error
        rows.append({'test': name, 'expected_nil_template_crash_reproduced': reproduced,
                     'error': error, 'test_sha256': hashlib.sha256((root / 'tests' / name).read_bytes()).hexdigest()})
    else:
        rows.append({'test': name, 'expected_nil_template_crash_reproduced': False})
os.chdir(baseline)
lua = scope['runtime']()
ok, error = lua.execute(b"local cfg=require('pa26_bindings').alertDefaults();cfg.on_duty=true;cfg.sos_template='Course {direction}.';return pcall(require('pa26_alerts').prepare,'sos',{session='test',ped=1,demo=false,directionKnown=false},cfg,codec,1000,1)")
error = error.decode('utf-8', errors='replace') if isinstance(error, bytes) else str(error)
alert_reproduced = not ok and 'pa26_map_grid.lua:83' in error and "'template'" in error and 'nil value' in error
os.chdir(root)
report = {'baseline': '0.43.3', 'baseline_commit': '42f90ffc3697c73dd68d0de28418e94223148587',
          'all_reproduced': all(row['expected_nil_template_crash_reproduced'] for row in rows),
          'results': rows, 'alerts_nil_template_reproduced': alert_reproduced, 'alerts_error': error, 'game_written': False}
(root / 'tests/F9_REPRODUCTION.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
assert report['all_reproduced'] and alert_reproduced, 'A failure was different from the reported nil-template defect'
print('Published 0.43.3: both final tests and a separate SOS call reproduce the exact map_grid.lua:83 nil-template defect.')
