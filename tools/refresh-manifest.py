"""Refresh explicit runtime hashes; never rebaseline public/personal presets."""
from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1];p=root/'INSTALL_MANIFEST.json';m=json.loads(p.read_text('utf-8-sig'))
for prefix,key in [('moonloader','files'),('cef/assets/hud','cef_files')]:
 for row in m[key]:row['sha256']=hashlib.sha256((root/prefix/row['path'].replace('\\','/')).read_bytes()).hexdigest()
for row in m['setup_files']:row['sha256']=hashlib.sha256((root/row['path']).read_bytes()).hexdigest()
for row in m['preset_files']:
 assert hashlib.sha256((root/row['path']).read_bytes()).hexdigest()==row['sha256'],'Do not overwrite owner presets: '+row['path']
p.write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n','utf-8')
print('Explicit runtime manifest refreshed; preset hashes preserved.')
