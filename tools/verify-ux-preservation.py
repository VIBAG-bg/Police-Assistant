"""Compare pure models and protected content with a supplied 0.39 checkout."""
from pathlib import Path
import argparse, hashlib, json
from lupa.luajit21 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--baseline',type=Path,required=True)
args=parser.parse_args()
base=args.baseline.resolve()

def snapshot(root):
    lua=LuaRuntime(encoding='utf-8',unpack_returned_tuples=True)
    lua.globals().QA_LIB=(root/'moonloader/lib/?.lua').as_posix()
    lua.execute("package.path=QA_LIB..';'..package.path")
    def convert(v):
        if hasattr(v,'items'): return {str(k):convert(x) for k,x in v.items()}
        return v
    return convert(lua.execute("""
        local c=require 'pa26_core';local m=require 'pa26_bindings'
        local binds={};for _,r in ipairs(require('pa26_rp_presets').items)do
          if r.binding_id then binds[tostring(r.binding_id)]=r end
        end
        return {ini=c.defaults(),library=assert(m.validate(m.defaults(c.defaults()),c.defaults())),new_binding=m.newBinding(1),actions=c.actions,
          variables=m.variables,radioVariables=require('pa26_preferences').radioVariables,bindPresets=binds}
    """))

def leaves(v,p=''):
    if isinstance(v,dict):
        out={}
        if not v:return {p:'empty_table'}
        for k,x in v.items(): out.update(leaves(x,p+'.'+k if p else k))
        return out
    return {p:type(v).__name__}

old,new=snapshot(base),snapshot(ROOT)
old_paths=leaves({'core_ini':old['ini'],'validated_library':old['library'],'new_binding_shape':old['new_binding']})
new_paths=leaves({'core_ini':new['ini'],'validated_library':new['library'],'new_binding_shape':new['new_binding']})
added={k:v for k,v in new_paths.items() if k not in old_paths}
allowed=('validated_library.vehicle.copilot.','validated_library.settings.manual_actions.frisk_','validated_library.assist.evidence.')
for k in added:assert k.startswith(allowed) or k=='validated_library.settings.updates.show_progress_window','Unexpected setting: '+k
assert {k:new_paths.get(k) for k in old_paths}==old_paths,'Existing config path/type changed'
assert new['library']['settings']['updates']['show_progress_window'] is True
assert old['ini']==new['ini'],'Core INI defaults changed'
assert old['actions']==new['actions'],'Six base actions changed'
assert old['library']['bindings']==new['library']['bindings'],'Base bind/female RP changed'
assert old['variables']==new['variables'] and old['radioVariables']==new['radioVariables'],'Variables changed'
for key,row in old['bindPresets'].items():
    expected=dict(row)
    if expected.get('binding_id')==3:
        expected['text']=expected['text'].removesuffix('\n/wanted {id}')
    assert expected==new['bindPresets'][key],f'Binding RP preset changed: {key}'
protected=['moonloader/lib/pa26_update_platform.lua','moonloader/lib/pa26_bindings.lua',
    'moonloader/resource/pa26/knowledge-base.json','moonloader/resource/pa26/knowledge-policy.json',
    'moonloader/config/police_assistant_2026.ini','cef/assets/hud/pa26-chat.js','cef/assets/hud/pa26-chat-endpoint.js']
hashes={}
for name in protected:
    a=(base/name).read_bytes();b=(ROOT/name).read_bytes();assert a==b,f'Protected file changed: {name}'
    hashes[name]=hashlib.sha256(b).hexdigest()
result={'status':'passed','baseline':str(base),'config_paths':len(old_paths),'same_path_types':True,'added_settings':added,
    'base_actions_unchanged':True,'default_bindings_unchanged':True,'bind_presets_rp_unchanged':True,
    'variables_unchanged':True,'protected_sha256':hashes,'game_written':False}
path=ROOT/'tests/PRESERVATION040.json';path.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'Preservation: {len(old_paths)} configuration paths/types, base binds, variables, frozen loader and knowledge bytes match 0.39.')
