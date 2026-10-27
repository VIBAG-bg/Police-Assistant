"""Capture a coherent, validated author preset without notes or identity data."""
from pathlib import Path
import argparse, hashlib, json, time
from lupa.luajit21 import LuaRuntime

root=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser();ap.add_argument('--config',type=Path,required=True);args=ap.parse_args()
paths={k:args.config/f'police_assistant_2026_{k}.json' for k in ('binds','settings')}
paths['config']=args.config/'police_assistant_2026.ini'
for attempt in range(3):
    if (args.config/'police_assistant_2026_files_pending.json').exists():raise SystemExit('An unfinished personal-data save must be recovered first.')
    before={k:p.read_bytes() for k,p in paths.items()};time.sleep(.2)
    if before=={k:p.read_bytes() for k,p in paths.items()}:break
else:raise SystemExit('Source files are changing; repeat after saving PA.')
lua=LuaRuntime(encoding='utf-8',unpack_returned_tuples=True)
lua.globals().QA_LIB=(root/'moonloader/lib/?.lua').as_posix();lua.execute("package.path=QA_LIB..';'..package.path")
def to_lua(x):
    if isinstance(x,dict):return lua.table_from({k:to_lua(v) for k,v in x.items()})
    if isinstance(x,list):return lua.table_from([to_lua(v) for v in x])
    return x
def plain(x):
    if not hasattr(x,'items'):return x
    d={k:plain(v) for k,v in x.items()}
    if d and set(d)==set(range(1,len(d)+1)):return [d[i] for i in range(1,len(d)+1)]
    return d
lua.globals().SOURCE_BINDS=to_lua(json.loads(before['binds'].decode('utf-8-sig')))
lua.globals().SOURCE_SETTINGS=to_lua(json.loads(before['settings'].decode('utf-8-sig')))
lua.globals().SOURCE_INI=before['config'].decode('utf-8-sig')
data=plain(lua.execute("""
local model=require 'pa26_bindings';local files=require 'pa26_user_files';local core=require 'pa26_core'
local cfg,notes=core.normalizeConfig(assert(require('pa26_config').parse(SOURCE_INI)))
assert(#notes==0,table.concat(notes,', '));assert(core.validateSettings(cfg))
local stockCfg=core.defaults();local stock=files.partition(model.defaults(stockCfg))
local b=assert(files.validate('binds',SOURCE_BINDS,cfg));local s=assert(files.validate('settings',SOURCE_SETTINGS,cfg))
local protected={'profile','partners','next_partner_id','wanted_reminders','filters'}
for _,key in ipairs(protected)do s.data[key]=model.copy(stock.settings.data[key])end
s.data.assist.history=model.copy(stock.settings.data.assist.history)
s.data.settings.updates=model.copy(stock.settings.data.settings.updates)
cfg.main.demo_mode=true
assert(files.validate('settings',s,cfg))
for _,row in ipairs(b.bindings)do assert(require('pa26_binder').parse(row.script))end
return {binds=b,settings={format='police-assistant.author-settings',schema=1,settings=s,config=cfg},
 baseline={format='police-assistant.preset-baseline',schema=1,binds=stock.binds,settings=stock.settings,notes=stock.notes,config=stockCfg}}
"""))
out=root/'presets';out.mkdir(exist_ok=True)
for name,key in [('pa-binds.json','binds'),('pa-settings.json','settings'),('baseline.json','baseline')]:
    (out/name).write_text(json.dumps(data[key],ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
meta={'format':'police-assistant.author-presets','schema':1,'version':'0.40.3','minimum_pa':'0.40.3',
      'files':{name:{'sha256':hashlib.sha256((out/name).read_bytes()).hexdigest(),'size':(out/name).stat().st_size} for name in ('pa-binds.json','pa-settings.json','baseline.json')}}
(out/'manifest.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
report={'source_sha256':{k:hashlib.sha256(v).hexdigest() for k,v in before.items()},'binds':len(data['binds']['bindings']),
        'personal_notes_read':False,'published_standard_notes':len(data['baseline']['notes']['notes']),
        'excluded':['profile','partners','wanted_reminders','filters','assist.history','personal knowledge','logs','update preferences']}
(root/'tests/PRESET_CAPTURE_RESULTS.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f"Captured {report['binds']} binds; complete UI/settings; two stock notes; identity and contacts excluded.")
