"""Comparable offline input-handler batches; never a GTA latency measurement."""
from pathlib import Path
import argparse
import json
import os
import statistics
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', type=Path, required=True)
args = parser.parse_args()
baseline = args.baseline.resolve()

def measure(root):
    # Reuse the project's codec, LuaJIT and fixture rather than a second harness.
    namespace = {'__file__': str(root / 'tests/run_tests.py')}
    source = (root / 'tests/run_tests.py').read_text('utf-8').split('syntax_lua = runtime()')[0]
    exec(compile(source, str(root / 'tests/run_tests.py'), 'exec'), namespace)
    lua = namespace['runtime']()
    lua.execute(b"local f=require 'support.fixture'; BENCH_SCENE=f({demo=false}); BENCH_SCENE.step(); BENCH_SCENE.chat=true")
    rows = {}
    for name, statement, count in [
        ('mouse_move_passthrough', 'onWindowMessage(0x200,0,0)', 100000),
        ('wm_char_passthrough', 'onWindowMessage(0x102,0x41,0)', 100000),
        ('typing_keydown', 'onWindowMessage(0x100,0x41,0)', 20000),
        ('prepared_world_frame', 'BENCH_SCENE.step(16)', 60),
    ]:
        run = lua.eval(('function(n) for i=1,n do ' + statement + ' end end').encode('ascii'))
        run(min(count, 100))
        samples = []
        for _ in range(7):
            started = time.perf_counter_ns()
            run(count)
            samples.append((time.perf_counter_ns() - started) / 1_000_000 / count)
        rows[name] = {'iterations_per_batch': count, 'batches': len(samples),
                      'median_batch_average_ms': statistics.median(samples),
                      'maximum_batch_average_ms': max(samples)}
    return rows

before, after = measure(baseline), measure(ROOT)
os.chdir(ROOT)
report = {'status': 'measured', 'baseline': '0.43.4', 'candidate': '0.43.5',
          'environment': 'LuaJIT with project offline game/input fixtures',
          'game_launched': False, 'individual_frame_spikes_measured': False,
          'actual_input_response_latency_measured': False, 'chat_contents_recorded': False,
          'limitations': 'Batch averages include fixture overhead and host scheduling; they are not in-game frame times or input latency.',
          'before': before, 'after': after}
(ROOT / 'tests/PERFORMANCE0435.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report))
