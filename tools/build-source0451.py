"""Build a local source/context archive without .git, personal data or test output."""
from pathlib import Path
import hashlib, json, zipfile

ROOT=Path(__file__).resolve().parents[1]
version=json.loads((ROOT/'INSTALL_MANIFEST.json').read_text('utf-8-sig'))['release']
baseline=json.loads((ROOT/f'docs/qa/{version}/BASELINE.json').read_text('utf-8'))
allowed_roots={'moonloader','cef','presets','docs','tests','tools','.github'}
root_files={'AGENTS.md','README.md','CHANGELOG.md','INSTALL_MANIFEST.json','CEF_CONTRACT.json','UPDATE_CEF_BASELINE.json',
 'DEPENDENCIES.json','install.ps1','Установить PA.cmd','Показать обновление PA.cmd','requirements-dev.txt',
 '.gitignore','.gitattributes','LICENSE','LICENSE.md','LICENSE.txt'}
blocked={'install-sandbox','update-sandbox','cef-contract-sandbox','native0440','home0440','font-upstream',
 '__pycache__','node_modules','installation-backups','dist'}
names=set(baseline['files'])
for folder in allowed_roots:
    names.update(p.relative_to(ROOT).as_posix() for p in (ROOT/folder).rglob('*') if p.is_file())
files=[]
for name in sorted(names):
    p=ROOT/name;parts=p.relative_to(ROOT).parts
    if not p.is_file() or p.is_symlink(): continue
    if len(parts)==1 and name not in root_files: continue
    if len(parts)>1 and parts[0] not in allowed_roots: continue
    if any(part in blocked or part.startswith(('.pa26-','roads-native32-')) for part in parts): continue
    if p.suffix.lower() in {'.dll','.exe','.zip','.log','.bak','.rollback','.pending','.verts','.indices','.rgba'}: continue
    if parts[0]=='tests' and len(parts)==2 and p.suffix not in {'.lua','.py','.js','.ps1'}: continue
    if name.startswith('moonloader/config/') and name!='moonloader/config/police_assistant_2026.ini':
        raise AssertionError('Refusing personal configuration in archive')
    files.append(p)
out=ROOT/'dist';out.mkdir(exist_ok=True)
archive=out/f'Police-Assistant-v{version}-source.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for p in files: z.write(p,p.relative_to(ROOT).as_posix())
print('Source/context:',len(files),'files;',hashlib.sha256(archive.read_bytes()).hexdigest())
