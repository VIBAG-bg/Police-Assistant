"""Repeatable CPU/operation measurements. Fake game APIs; never launch GTA."""
from pathlib import Path
import argparse,hashlib,json,zipfile
ROOT=Path(__file__).resolve().parents[1]
runner=ROOT/'tests/run_tests.py'
scope={'__file__':str(runner),'__name__':'cef_benchmark'}
exec(compile(runner.read_text('utf-8').split('results = []')[0],str(runner),'exec'),scope)
lua=scope['runtime']()
parser=argparse.ArgumentParser()
parser.add_argument('output',nargs='?',default=str(ROOT/'tests/CEF_BENCHMARK.json'))
parser.add_argument('--baseline-archive',type=Path)
args=parser.parse_args()
names=('moonloader/police_assistant_2026.lua','moonloader/lib/pa26_chat_bridge.lua','cef/assets/hud/pa26-chat.js')
sources={n:(ROOT/n).read_bytes() for n in names}
if args.baseline_archive:
    with zipfile.ZipFile(args.baseline_archive) as archive:sources={n:archive.read(n) for n in names}
    overrides=lua.table()
    for name,value in sources.items():
        if name.endswith('.lua'):overrides[name.encode()]=value
    lua.globals()[b'TEST_BASELINE_SOURCES']=overrides
    lua.execute(b"local original=dofile;function dofile(path) local source=TEST_BASELINE_SOURCES[path];if source then return assert(loadstring(source,'@'..path))()end;return original(path)end")
lua.globals()[b'TEST_TEMP_PATH']=(ROOT/'tests/.pa26-benchmark.ini').as_posix().encode()
value=lua.execute((ROOT/'tests/bench_cef_input.lua').read_bytes())
report=json.loads(value.decode('utf-8'))
report['source_sha256']={n:hashlib.sha256(value).hexdigest() for n,value in sources.items()}
report['cleanup_included_in_counters']=False
report['synthetic_game_apis']=True
target=Path(args.output)
target.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,indent=2))
