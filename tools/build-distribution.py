"""Build an install archive using explicit program and documentation allowlists."""
from pathlib import Path
import hashlib, json, subprocess, sys, zipfile

ROOT=Path(__file__).resolve().parents[1]
subprocess.run([sys.executable,str(ROOT/'tools/verify-package.py')],check=True)
m=json.loads((ROOT/'INSTALL_MANIFEST.json').read_text('utf-8-sig'))
files=[ROOT/'moonloader'/r['path'].replace('\\','/') for r in m['files']]
files += [ROOT/'cef/assets/hud'/r['path'] for r in m['cef_files']]
files += [ROOT/n for n in ['README.md','CHANGELOG.md','install.ps1','Установить PA.cmd','INSTALL_MANIFEST.json','CEF_CONTRACT.json']]
files += [p for p in (ROOT/'docs').rglob('*') if p.is_file()]
out=ROOT/'dist';out.mkdir(exist_ok=True)
archive=out/f'Police-Assistant-v{m["release"]}.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for p in sorted(set(files)):
        z.write(p,p.relative_to(ROOT).as_posix())
update=ROOT/'pa26-update.zip'
assert update.is_file(), 'Build pa26-update.zip first'
copy=out/update.name
copy.write_bytes(update.read_bytes())
with zipfile.ZipFile(copy) as z:
    names=z.namelist()
    assert all('/config/' not in p.lower() for p in names)
    um=json.loads(z.read('pa26-update.json'))
    assert um['version']==m['release']
    assert len(um['files'])==len(m['files'])-1+len(m['cef_files'])
    assert len(names)==len(um['files'])+1
    for row in um['files']:
        data=z.read(row['path'])
        assert len(data)==row['size'] and hashlib.sha256(data).hexdigest()==row['sha256']
rows=[f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}' for p in [archive,copy]]
(out/'SHA256SUMS.txt').write_text('\n'.join(rows)+'\n',encoding='utf-8')
print('\n'.join(rows))
