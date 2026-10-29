"""Check legacy values, source provenance, immutable updater and public personal-data boundary."""
from pathlib import Path
import argparse, hashlib, json
from lupa.luajit21 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
args=argparse.ArgumentParser();args.add_argument('--baseline',type=Path,required=True)
base=args.parse_args().baseline.resolve()
def runtime(root):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path=.....'/moonloader/lib/?.lua;'..package.path",root.as_posix())
    return lua
def native(value):
    return {str(k):native(v) for k,v in value.items()} if hasattr(value,'items') else value
def leaves(value,path=''):
    if isinstance(value,dict):
        if not value:return {path:('empty',)}
        out={}
        for k,v in value.items():out.update(leaves(v,path+'.'+k if path else k))
        return out
    return {path:(type(value).__name__,value)}
old,new=runtime(base),runtime(ROOT)
def transfer(v):
    if not hasattr(v,'items'):return v
    t=new.table()
    for k,x in v.items():t[k]=transfer(x)
    return t
count=0;changed=set()
allowed={'procedures.fine_command','procedures.fine_verified','procedures.fine_source'}
for case in ('stock','personal','disabled_custom_contract'):
    value=old.execute("local c=require 'pa26_core';local m=require 'pa26_bindings';return assert(m.validate(m.defaults(c.defaults()),c.defaults()))")
    old.globals().qa=value
    if case!='stock':old.execute("""
      qa.profile.name='Private_Name';qa.profile.callsign='PRIVATE';qa.notes[1].body='PRIVATE NOTE';
      qa.vehicle.copilot.enabled=false;qa.vehicle.copilot.templates.explain_stop='Личная причина {stop_ground}.';
      qa.vehicle.copilot.templates.miranda='Моя личная версия прав.';
      qa.settings.wheel_names={citizen='Мои секции'};qa.settings.wheel_child_limit=10;
      qa.settings.window_layout.windows.main={width=900,height=600,x=40,y=50,displayW=1920,displayH=1080};
      qa.partners={{id=1,nickname='Private_Partner',callsign='PRIVATE'}};qa.next_partner_id=2;
    """)
    if case=='disabled_custom_contract':old.execute("""
      qa.procedures.enabled=false;qa.procedures.fine_command='/ticket {id} {amount} Своя причина {basis}';
      qa.procedures.fine_verified=false;qa.procedures.fine_source='Моя проверка';qa.procedures.fine_passport_rp='/me моя личная отыгровка.';
    """)
    result=new.execute("local m=require 'pa26_bindings';return m.validate(...,require('pa26_core').defaults())",transfer(value))
    result,error=result if isinstance(result,tuple) else (result,None)
    assert result,error
    before,after=leaves(native(value)),leaves(native(result))
    for k,v in before.items():
        if after.get(k)!=v:
            assert case!='disabled_custom_contract' and k in allowed,(case,k,v,after.get(k))
            changed.add(k)
        count+=1
    twice=new.execute("local m=require 'pa26_bindings';return assert(m.validate(...,require('pa26_core').defaults()))",result)
    assert leaves(native(twice))==after
unchanged=['moonloader/lib/pa26_update_platform.lua','moonloader/resource/pa26/updater/pa26-update.ps1',
 'cef/assets/hud/pa26-chat.js','cef/assets/hud/pa26-chat-endpoint.js',
 'moonloader/config/police_assistant_2026.ini','presets/pa-binds.json','presets/pa-settings.json','presets/baseline.json',
 'tools/pa-setup.ps1','tools/pa-setup-window.ps1','tools/pa-start.ps1','tools/pa-seed-presets.ps1']
for name in unchanged:assert (ROOT/name).read_bytes()==(base/name).read_bytes(),name
previous=json.loads((base/'moonloader/resource/pa26/knowledge-base.json').read_text('utf-8-sig'))
current=json.loads((ROOT/'moonloader/resource/pa26/knowledge-base.json').read_text('utf-8-sig'))
def records(data,group):return {r['id']:r for r in data[group]}
articles=0
for group in ('articles','rules','radio','sources'):
    a,b=records(previous,group),records(current,group);assert set(a)==set(b)
    for key,row in a.items():
        clean=dict(b[key]);clean.pop('sanctions',None)
        original=dict(row);original.pop('sanctions',None)
        assert clean==original,(group,key)
        if group=='articles':articles+=1
report={'status':'passed','release':'0.42.2','baseline':'0.42.1','legacy_leaf_checks':count,
 'accepted_untouched_contract_upgrade':sorted(changed),'migration_idempotent':True,
 'source_articles_preserved':articles,'rules_radio_and_source_registry_preserved':True,
 'unchanged_files':unchanged,'local_game_updated':False}
(ROOT/'tests/PRESERVATION0422.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report))
