from pathlib import Path
import json,hashlib,re
root=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
p=root/'INSTALL_MANIFEST.json';m=json.loads(p.read_text('utf-8-sig'));m['release']='0.45.0'
known={r['path']for r in m['files']}
graph=root/'moonloader/resource/pa26/roads.bin'
assert graph.stat().st_size==589664 and sha(graph)=='c1d347286ccb0349940800570078c6872bef31c12ac6d6f77a4b1cf8b857d7db'
if 'resource\\pa26\\roads.bin'not in known:
 m['files'].append({'path':'resource\\pa26\\roads.bin','sha256':sha(graph)})
 known.add('resource\\pa26\\roads.bin')
for f in sorted((root/'moonloader/lib').glob('pa26_*.lua')):
 name='lib\\'+f.name
 if name not in known:m['files'].append({'path':name,'sha256':sha(f)});known.add(name)
m['files'].sort(key=lambda r:r['path'])
for prefix,key in [('moonloader','files'),('cef/assets/hud','cef_files')]:
 for r in m[key]:r['sha256']=sha(root/prefix/r['path'].replace('\\','/'))
for r in m['preset_files']:assert sha(root/r['path'])==r['sha256'],r['path']
installer=root/'install.ps1';text=installer.read_text('utf-8-sig')
replacement='$paOwned = @(\n'+',\n'.join("    '"+r['path']+"'"for r in m['files'])+'\n)\n'
text,count=re.subn(r'\$paOwned\s*=\s*@\(.*?\)\s*\r?\n',lambda _:replacement,text,count=1,flags=re.S);assert count==1
installer.write_text(text,'utf-8-sig',newline='')
for r in m['setup_files']:r['sha256']=sha(root/r['path'])
p.write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n','utf-8')
print('0.45.0 manifest/installer allowlists synchronized:',len(m['files']),'runtime entries; presets untouched')
