"""Refresh hashes only after reviewing the candidate source changes."""
from pathlib import Path
import hashlib,json,re
P=Path(__file__).resolve().parents[1]
def read(name):return (P/name).read_text('utf-8-sig')
def write(name,value):(P/name).write_text(value,encoding='utf-8',newline='\n')
import shutil
for name in ['moonloader/lib/pa26_core.lua','moonloader/police_assistant_2026.lua']:
    s=read(name).replace("VERSION = '0.45.0'","VERSION = '0.45.1'").replace("script_version('0.45.0')","script_version('0.45.1')").replace("core.VERSION ~= '0.45.0'","core.VERSION ~= '0.45.1'")
    write(name,s)
manifest=json.loads(read('presets/manifest.json'));manifest.update(version='0.45.1',minimum_pa='0.45.1',settings_revision='2026-11-05-unified-rp-0451',binds_revision='2026-11-05-author-83-rp-0451')
for name in manifest['files']:
    data=(P/'presets'/name).read_bytes();manifest['files'][name]={'sha256':hashlib.sha256(data).hexdigest(),'size':len(data)}
write('presets/manifest.json',json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
m=json.loads(read('INSTALL_MANIFEST.json'));m['release']='0.45.1'
names={r['path']for r in m['files']}
for f in sorted((P/'moonloader/lib').glob('pa26_*.lua')):
    key='lib\\'+f.name
    if key not in names:m['files'].append({'path':key,'sha256':''});names.add(key)
m['files'].sort(key=lambda r:r['path'])
for prefix,key in [('moonloader','files'),('cef/assets/hud','cef_files')]:
    for r in m[key]:r['sha256']=hashlib.sha256((P/prefix/r['path'].replace('\\','/')).read_bytes()).hexdigest()
for r in m['preset_files']:r['sha256']=hashlib.sha256((P/r['path']).read_bytes()).hexdigest()
s=read('install.ps1')
replacement='$paOwned = @(\n'+',\n'.join("    '"+r['path']+"'"for r in m['files'])+'\n)\n'
s,n=re.subn(r'\$paOwned\s*=\s*@\(.*?\)\s*\r?\n',lambda _:replacement,s,count=1,flags=re.S);assert n==1
(P/'install.ps1').write_text(s,encoding='utf-8-sig',newline='')
for r in m['setup_files']:r['sha256']=hashlib.sha256((P/r['path']).read_bytes()).hexdigest()
write('INSTALL_MANIFEST.json',json.dumps(m,ensure_ascii=False,indent=2)+'\n')
print('Refreshed local 0.45.1 manifests. No installation or publication.')
