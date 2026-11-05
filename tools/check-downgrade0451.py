"""Run actual previous-release validators against the new public schema (read only)."""
from pathlib import Path
import argparse, hashlib, json
from lupa.luajit21 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--baseline',type=Path,required=True);args=p.parse_args()
old=args.baseline.resolve();baseline=json.loads((ROOT/'docs/qa/0.45.1/BASELINE.json').read_text('utf-8'))
for name in ['moonloader/lib/pa26_author_presets.lua','moonloader/lib/pa26_user_files.lua']:
    assert hashlib.sha256((old/name).read_bytes()).hexdigest()==baseline['files'][name]
lua=LuaRuntime(encoding='utf-8',unpack_returned_tuples=True)
lua.execute('package.path = ... .. ";" .. package.path',(old/'moonloader/lib/?.lua').as_posix())
def table(v):
    if isinstance(v,dict):return lua.table_from({k:table(x)for k,x in v.items()})
    if isinstance(v,list):return lua.table_from([table(x)for x in v])
    return v
validate=lua.eval("require('pa26_author_presets').validate");rows=[]
for kind,name in [('binds','pa-binds.json'),('settings','pa-settings.json')]:
    result=validate(kind,table(json.loads((ROOT/'presets'/name).read_text('utf-8'))))
    ok=result[0]if isinstance(result,tuple)else result
    assert not ok,'Old PA must reject the new public schema'
    rows.append(dict(kind=kind,status='PASS',result='Old PA rejects schema 2 before applying it'))
(ROOT/'tests/DOWNGRADE0451.json').write_text(json.dumps(dict(status='PASS',baseline='0.45.0',results=rows,game_started=False),indent=2)+'\n','utf-8')
print('Downgrade protection PASS: real 0.45.0 validators reject both new public documents.')
