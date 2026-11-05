"""Three offline callback timing trials, never a GTA latency/FPS measurement."""
from pathlib import Path
import datetime, json, subprocess

ROOT = Path(__file__).resolve().parents[1]
baseline = ROOT.parent / 'Police-Assistant-2026-v0.45.0-dev'
runs = []
for trial in range(1, 4):
    result = subprocess.run(['C:/Program Files/nodejs/node.exe', 'tests/benchmark_cef0451.js',
                             str(baseline)], cwd=ROOT, capture_output=True, timeout=90)
    if result.returncode:
        raise RuntimeError(result.stderr.decode('utf-8', errors='replace'))
    runs.append(json.loads((ROOT/'tests/CEF_PERFORMANCE0451.json').read_text('utf-8')))
    print('Offline CEF callback trial', trial, 'passed', flush=True)
report = {'trials': 3, 'environment': 'Node V8; synthetic DOM; production CEF callbacks including ready protocol-2 path',
          'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'actual_input_latency_measured': False, 'actual_frame_time_spikes_measured': False,
          'game_started': False, 'chat_contents_recorded': False, 'runs': runs}
(ROOT/'tests/CEF_PERFORMANCE0451.json').write_text(json.dumps(report, indent=2)+'\n', 'utf-8')
