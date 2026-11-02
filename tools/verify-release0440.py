"""Final local-only release gate. No publishing or installed-game writes."""
from pathlib import Path
import hashlib,json,subprocess,sys,zipfile
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text('utf-8-sig'))
subprocess.run([sys.executable,str(ROOT/'tools/verify-package.py')],check=True)
state=read(ROOT/'docs/qa/0.44.0/STATE.json');assert state['version']=='0.44.0'
assert state['status']=='passed_local_automated_qa'and not state['published']and not state['live_game_written']
assert sha(ROOT/'INSTALL_MANIFEST.json')==state['install_manifest_sha256']
assert sha(ROOT/'pa26-update.zip')==state['update_sha256']
for name,h in state['runtime_sha256'].items():assert sha(ROOT/name)==h,name
for name,h in state['evidence_files'].items():assert sha(ROOT/'docs/qa/0.44.0'/name)==h,name
for image in state['images']:assert sha(ROOT/image['file'])==image['sha256']
rows=[]
for name in ['Police-Assistant-v0.44.0.zip','pa26-update.zip','Police-Assistant-v0.44.0-source.zip']:
 p=ROOT/'dist'/name
 with zipfile.ZipFile(p)as z:
  names=z.namelist();assert len(names)==len(set(names))and not z.testzip()
  assert all('..'not in Path(n).parts and not n.startswith('/')for n in names)
  assert not any('/update-sandbox/'in n or'/install-sandbox/'in n or'/home0440/'in n or'/native0440/'in n for n in names)
  if name=='pa26-update.zip':assert sha(p)==state['update_sha256']and not any('/config/'in n or n.startswith('presets/')for n in names)
  else:
   assert read(ROOT/'INSTALL_MANIFEST.json')['release']=='0.44.0'
   assert 'docs/qa/0.44.0/STATE.json'in names and 'docs/RELEASE-0.44.0.md'in names
   for image in state['images']:assert hashlib.sha256(z.read(image['file'])).hexdigest()==image['sha256']
 rows.append({'file':name,'size':p.stat().st_size,'sha256':sha(p)})
for name in ['pa-binds.json','pa-settings.json']:
 p=ROOT/'dist'/name;assert p.read_bytes()==(ROOT/'presets'/name).read_bytes();rows.append({'file':name,'size':p.stat().st_size,'sha256':sha(p)})
(ROOT/'dist/SHA256SUMS.txt').write_text(''.join(x['sha256']+'  '+x['file']+'\n'for x in rows),'utf-8')
(ROOT/'dist/LOCAL-RELEASE-0.44.0.json').write_text(json.dumps({'version':'0.44.0','status':'ready_for_owner_game_acceptance','local_only':True,'published':False,'live_game_written':False,'files':rows},indent=2)+'\n','utf-8')
print('Local release 0.44.0 verified:',len(rows),'artifacts. GTA/Win7 acceptance remains manual; nothing published or installed.')
