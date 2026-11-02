"""Collect content-free QA evidence and bind it to the final program bytes."""
from pathlib import Path
import hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[1];out=ROOT/'docs/qa/0.44.0';out.mkdir(parents=True,exist_ok=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text('utf-8-sig'))
reg=read(ROOT/'tests/REGRESSION-0.44.0.json');assert len(reg['results'])==196 and all(x['status']=='passed'for x in reg['results'])
for name,digest in {**reg['lua_source_sha256'],**reg['resource_sha256']}.items():assert sha(ROOT/name)==digest,'Stale regression: '+name
required=['REGRESSION-0.44.0.json','ICONS_NATIVE32_0440.json','UX_NATIVE32_0440.json','GEOMETRY_NATIVE32_0440.json',
 'IMPORTANT_NATIVE32_RESULTS.json','F9_NATIVE32_RESULTS.json','WINDOW_NATIVE32_RESULTS.json','HOME_PREVIEWS0440.json','COPILOT_NATIVE32_0440.json',
 'CEF_BROWSER_RESULTS.json','CEF_PERFORMANCE0440.json','LUA_PERFORMANCE0440.json','USER_DATA_PRESERVATION0440.json',
 'LIVE_CEF_REFERENCE0440.json','PREVIOUS_WORKER0440_FROM0432.json','PREVIOUS_WORKER0440_FROM0435.json','AUTHOR_INSTALL_RESULTS.json',
 'INSTALLER_RESULTS.json','UPDATER_WORKER_RESULTS.json','SETUP_RESULTS.json','SETUP_WINDOW_RESULTS.json','SETUP_LAUNCH_RESULTS.json',
 'INSTALLER_LEGACY_PATH_RESULTS.json','UPDATE_LEGACY_PATH_RESULTS.json','UPDATE_PROGRESS_RESULTS.json',
 'CUSTODY_CEF0440.json','CEF_INSTALLER0440.json','CEF_CONTRACT_NATIVE32_0440.json','CUSTODY_GUI0440.json','CUSTODY_NATIVE32_0440.json']
for name in required:
 p=ROOT/'tests'/name;d=read(p)
 if 'status'in d:assert d['status']=='passed',name
 if name.startswith('PREVIOUS_WORKER'):assert d['package_sha256']==sha(ROOT/'pa26-update.zip'),'Stale upgrade evidence'
 # Fixture paths are implementation-local, not useful in a distributable report.
 def sanitize(v):
  if isinstance(v,dict):return {k:sanitize(x)for k,x in v.items()if k not in ('sandbox','root','job_path')}
  if isinstance(v,list):return [sanitize(x)for x in v]
  return v
 (out/name).write_text(json.dumps(sanitize(d),ensure_ascii=False,indent=2)+'\n','utf-8')
for name in ['preservation-0.44.0.json','knowledge-audit-0.44.0.json']:shutil.copyfile(ROOT/'docs'/name,out/name)
for p in sorted((ROOT/'tests').glob('*COPILOT*NATIVE*.json')):shutil.copyfile(p,out/p.name)
for p in sorted((ROOT/'tests').glob('*NATIVE*COPILOT*.json')):shutil.copyfile(p,out/p.name)
images=[]
from PIL import Image
for size in [(1920,1080),(2560,1440)]:
 p=ROOT/f'docs/screenshots/0.44.0/F9-Home-{size[0]}x{size[1]}.png';assert Image.open(p).size==size
 images.append({'file':p.relative_to(ROOT).as_posix(),'sha256':sha(p),'kind':'synthetic_native_cpu_preview','resolution':size})
rows=read(ROOT/'tests/HOME_PREVIEWS0440.json')['results']
assert all(len(x['navigation'])==8 and x['navigation_scroll']<=1 and x['content_scroll']<=1 for x in rows)
manifest=read(ROOT/'INSTALL_MANIFEST.json')
runtime={('moonloader/'+r['path'].replace('\\','/')):r['sha256']for r in manifest['files']}
runtime.update({'cef/assets/hud/'+r['path']:r['sha256']for r in manifest['cef_files']})
assert all(sha(ROOT/n)==h for n,h in runtime.items())
report={'version':'0.44.0','status':'passed_local_automated_qa','runtime_sha256':runtime,'install_manifest_sha256':sha(ROOT/'INSTALL_MANIFEST.json'),
 'update_sha256':sha(ROOT/'pa26-update.zip'),'images':images,'evidence_files':{p.name:sha(p)for p in out.iterdir()if p.is_file()and p.name!='STATE.json'},
 'gta_validation':'not_run','windows7_vm':'not_run','published':False,'live_game_written':False}
(out/'STATE.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n','utf-8')
print('Final source-bound QA collected:',len(runtime),'runtime entries;',len(required),'required reports; two synthetic F9 previews.')
