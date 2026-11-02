"""Record preservation/inventory evidence against the actual maintained 0.43.5."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,zipfile
from lupa.luajit21 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--baseline',type=Path,required=True);args=p.parse_args();base=args.baseline.resolve()
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def load(path):return json.loads(path.read_text('utf-8-sig'))
def default_leaves(root):
 lua=LuaRuntime(unpack_returned_tuples=True)
 lua.execute("package.path="+repr((root/'moonloader/lib/?.lua').as_posix())+"..';'..package.path")
 table=lua.execute("return require('pa26_bindings').defaults(require('pa26_core').defaults())")
 leaves={}
 def visit(v,path=''):
  if hasattr(v,'items'):
   for k,x in v.items():visit(x,(path+'.'if path else'')+str(k))
  else:leaves[path]=v
 visit(table);return leaves
before,after=default_leaves(base),default_leaves(ROOT)
assert all(key in after and after[key]==value for key,value in before.items()),'An existing default leaf changed'
added=set(after)-set(before)
assert {'settings.ui_icons','settings.window_layout.default_style'}<=added
assert all(k in {'settings.ui_icons','settings.window_layout.default_style'}or k.startswith('patrol_events.command_reports.')for k in added)
protected=['moonloader/lib/pa26_update_platform.lua','moonloader/resource/pa26/updater/pa26-update.ps1','moonloader/lib/pa26_chat_bridge.lua','CEF_CONTRACT.json',
 'cef/assets/hud/pa26-chat.js','cef/assets/hud/pa26-chat-endpoint.js','moonloader/resource/pa26/knowledge-base.json',
 'moonloader/resource/pa26/knowledge-policy.json','moonloader/resource/pa26/wanted-catalog.json']
protected+=[r['path']for r in load(base/'INSTALL_MANIFEST.json')['preset_files']if r['path']not in ('presets/pa-settings.json','presets/manifest.json')]
old_policy,new_policy=load(base/'UPDATE_CEF_BASELINE.json'),load(ROOT/'UPDATE_CEF_BASELINE.json')
assert new_policy['include_assets'] is False
assert all(new_policy[k]==v for k,v in old_policy.items()if k not in ('include_assets','policy','adapter_review'))
old_preset,new_preset=load(base/'presets/pa-settings.json'),load(ROOT/'presets/pa-settings.json')
import copy
old_clean,new_clean=copy.deepcopy(old_preset),copy.deepcopy(new_preset)
new_clean['settings']['data']['settings']['window_layout']=old_clean['settings']['data']['settings']['window_layout']
for k in ('x','y','scale','reference_width','reference_height','responsive'):
 if k in old_clean['config']['widget']:new_clean['config']['widget'][k]=old_clean['config']['widget'][k]
 else:new_clean['config']['widget'].pop(k,None)
assert new_clean==old_clean,'Only authorized shared-preset geometry may change'
assert new_preset['settings']['data']['settings']['window_layout']['default_style']=='author'
assert new_preset['settings']['data']['settings']['window_layout']['windows']=={}
protected += [p.relative_to(base).as_posix() for p in (base/'docs/sources/2026-10-28').iterdir()if p.is_file()]
rows=[]
import configparser
def ini_leaves(path):
 c=configparser.ConfigParser(interpolation=None);c.read_string(path.read_text('utf-8-sig'))
 return {s+'.'+k:v for s in c.sections()for k,v in c[s].items()}
ini='moonloader/config/police_assistant_2026.ini';old_ini,new_ini=ini_leaves(base/ini),ini_leaves(ROOT/ini)
geometry_changes={k:{'before':old_ini.get(k),'after':v}for k,v in new_ini.items()if old_ini.get(k)!=v}
assert set(geometry_changes)=={'widget.x','widget.y','widget.responsive','widget.reference_width','widget.reference_height'}
assert all(new_ini.get(k)==v for k,v in old_ini.items()if k not in geometry_changes),'A stock RP/config field changed'
for name in protected:
 assert (ROOT/name).read_bytes()==(base/name).read_bytes(),'Protected source changed: '+name
 rows.append({'file':name,'sha256':sha(ROOT/name),'status':'byte_identical'})
changed=[]
for file in (ROOT/'moonloader').rglob('*'):
 if file.is_file():
  name=file.relative_to(ROOT).as_posix();previous=base/name
  if not previous.exists()or file.read_bytes()!=previous.read_bytes():changed.append({'file':name,'sha256':sha(file),'kind':'changed'if previous.exists()else'added'})
archives=[]
old=base.parent/'Police-Assistant-2026-v0.43.2-dev/dist/Police-Assistant-v0.43.2.zip'
if old.exists():
 with zipfile.ZipFile(old)as z:
  entries={name:hashlib.sha256(z.read(name)).hexdigest()for name in ('cef/assets/hud/pa26-chat.js','cef/assets/hud/pa26-chat-endpoint.js')}
 archives.append({'file':old.name,'sha256':sha(old),'cef_entries':entries,'note':'Actual archived 0.43.2 assets; 0.44 preserves latest maintained 0.43.5 assets, not an older rollback.'})
manifest=load(ROOT/'INSTALL_MANIFEST.json')
with zipfile.ZipFile(ROOT/'pa26-update.zip')as z:
 paths=z.namelist();assert not any('/config/'in x.lower()or'presets/'in x.lower()for x in paths)
 report={'status':'passed','version':'0.44.0','baseline_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=base,text=True).strip(),
  'existing_default_leaves_preserved':len(before),'added_default_leaves':sorted(added),'protected_files':rows,'authorized_fresh_install_geometry_only':geometry_changes,
  'runtime_changes':changed,'archived_cef_provenance':archives,'update_program_entries':len(paths)-1,
  'personal_files_in_update':False,'live_game_modified':False,'published':False,
  'presets_policy':'Owner explicitly authorized public preset geometry refresh on 2026-11-02. Only window/HUD geometry changes; author RP, binds and all private data preserved.',
  'patrol_settings_routes':{'operational':['enabled','periodic','reporter_self','mode','station','unit','unit_number','channel','crew'],
   'operational_optional':['vehicle','sector','post'],
   'advanced':['hud','restore_offer','auto_resume_reload','pause_on_crew_change','count_map_time','confirmation','interrupt_grace_ms','reload_grace_ms','downed_hp','respawn_distance','respawn_position_tolerance','respawn_evidence_ms','interval_ms','map_max_gap_ms','bind_distance','grammar','start_template','resume_template','finish_template','crew_template','periodic_template','toggle_shortcut','pause_shortcut','finish_shortcut']}}
(ROOT/'docs/preservation-0.44.0.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n','utf-8')
print('Preserved',len(before),'default leaves and',len(rows),'frozen files; reviewed runtime changes:',len(changed))
