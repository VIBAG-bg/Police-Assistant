"""Read-only, in-memory old/new migration comparison. Never exports user values."""
from pathlib import Path
import argparse,hashlib,json
from lupa.luajit21 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--game',type=Path,required=True);p.add_argument('--baseline',type=Path,required=True);a=p.parse_args()
folder=a.game/'moonloader/config';prefix='police_assistant_2026'
files={k:folder/(prefix+suffix)for k,suffix in {'ini':'.ini','settings':'_settings.json','binds':'_binds.json','notes':'_notes.json'}.items()}
raw={k:p.read_bytes()for k,p in files.items()}
def digest(b):return hashlib.sha256(b).hexdigest()
def measure(root):
 lua=LuaRuntime(unpack_returned_tuples=True);lua.execute('package.path='+repr((root/'moonloader/lib/?.lua').as_posix())+"..';'..package.path")
 def from_py(v):
  if isinstance(v,dict):return lua.table_from({k:from_py(x)for k,x in v.items()})
  if isinstance(v,list):return lua.table_from([from_py(x)for x in v])
  return v
 lua.globals().INPUT=from_py({k:json.loads(b.decode('utf-8-sig'))for k,b in raw.items()if k!='ini'})
 lua.globals().INI=raw['ini'].decode('utf-8-sig')
 value=lua.execute("local config=require('pa26_config');local c=assert(config.parse(INI));local cfg=assert(require('pa26_core').normalizeConfig(c));local lib=assert(require('pa26_user_files').combine(INPUT,cfg));return {config=cfg,library=lib}")
 leaves={}
 def visit(v,path=''):
  if hasattr(v,'items'):
   for k,x in v.items():visit(x,path+'.'+str(k))
  else:leaves[path]=v
 visit(value);return leaves
before=measure(a.baseline.resolve());after=measure(ROOT)
assert all(k in after and after[k]==v for k,v in before.items()),'Existing user values changed in the migration model'
assert all(p.read_bytes()==raw[k]for k,p in files.items()),'Live files changed during read-only inspection; retry a stable snapshot'
report={'status':'passed','input':'current local split user documents; in-memory comparison only','user_values_exported':False,
 'existing_leaf_values_preserved':len(before),'additional_leaf_count':len(set(after)-set(before)),'source_files_unchanged':True,
 'notes_exported':False,'live_game_written':False,'baseline':'0.44.0','candidate':'0.45.0'}
(ROOT/'tests/USER_DATA_PRESERVATION0450.json').write_text(json.dumps(report,indent=2)+'\n','utf-8')
print(json.dumps(report))
