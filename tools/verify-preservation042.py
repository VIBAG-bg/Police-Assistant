"""Load a complete legacy library into 0.42 without changing any existing leaf."""
from pathlib import Path
import argparse,hashlib,json
from lupa.luajit21 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--baseline',type=Path,required=True);a=p.parse_args()
def runtime(root):
 l=LuaRuntime(unpack_returned_tuples=True);l.execute("package.path=.....'/moonloader/lib/?.lua;'..package.path",root.as_posix());return l
def convert(v):
 if hasattr(v,'items'):return {str(k):convert(x) for k,x in v.items()}
 return v
old=runtime(a.baseline.resolve());new=runtime(ROOT)
base=old.execute("local c=require 'pa26_core';local m=require 'pa26_bindings';return assert(m.validate(m.defaults(c.defaults()),c.defaults()))")
def transfer(v):
 if hasattr(v,'items'):
  t=new.table()
  for k,x in v.items():t[k]=transfer(x)
  return t
 return v
def leaves(v,p=''):
 if isinstance(v,dict):
  if not v:return {p:('empty',)}
  out={}
  for k,x in v.items():out.update(leaves(x,p+'.'+k if p else k))
  return out
 return {p:(type(v).__name__,v)}
checked=0
for custom in (False,True):
 if custom:
  old.globals().qa_library=base
  old.execute("""qa_library.profile.name='Private_Name';qa_library.profile.callsign='PERSONAL';
   qa_library.notes[1].body='PRIVATE NOTE MUST STAY';qa_library.partners={{id=1,nickname='Partner_Name',callsign='PERSONAL'}};qa_library.next_partner_id=2;
   qa_library.vehicle.copilot.enabled=false;qa_library.vehicle.copilot.templates.wanted_rp='/me моя личная отыгровка.';
   qa_library.vehicle.copilot.templates.risk_single='Личное требование, не заменять.';
   qa_library.settings.wheel_names={citizen='Своя секция'};qa_library.settings.wheel_child_limit=10""")
 candidate=transfer(base)
 result=new.execute("local m=require 'pa26_bindings';local c=require 'pa26_core';return m.validate(...,c.defaults())",candidate)
 valid,err=result if isinstance(result,tuple) else (result,None)
 assert valid,err
 before=leaves(convert(base));after=leaves(convert(valid))
 mismatches={k:(v,after.get(k)) for k,v in before.items() if after.get(k)!=v}
 assert not mismatches,mismatches
 checked+=len(before)
frozen='moonloader/lib/pa26_update_platform.lua'
assert (ROOT/frozen).read_bytes()==(a.baseline/frozen).read_bytes()
for name in ('cef/assets/hud/pa26-chat-endpoint.js','cef/assets/hud/pa26-chat.js','moonloader/config/police_assistant_2026.ini','presets/pa-binds.json','presets/pa-settings.json'):
 assert (ROOT/name).read_bytes()==(a.baseline/name).read_bytes(),name
report={'status':'passed','legacy_leaf_checks':checked,'cases':['stock_0412','custom_profile_notes_templates_disabled_features_wheel'],
 'loader_sha256':hashlib.sha256((ROOT/frozen).read_bytes()).hexdigest(),'cef_unchanged':True,'presets_unchanged':True,'game_written':False}
(ROOT/'tests/PRESERVATION0420.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report))
