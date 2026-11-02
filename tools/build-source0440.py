"""Build a reviewable source/context ZIP; exclude live data, caches and fixtures' output."""
from pathlib import Path
import hashlib,json,subprocess,zipfile
ROOT=Path(__file__).resolve().parents[1];out=ROOT/'dist';out.mkdir(exist_ok=True)
listed=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=ROOT).decode('utf-8').split('\0')
allowed_roots={'moonloader','cef','presets','docs','tests','tools','.github'}
root_files={'README.md','CHANGELOG.md','INSTALL_MANIFEST.json','CEF_CONTRACT.json','UPDATE_CEF_BASELINE.json','DEPENDENCIES.json',
 'install.ps1','Установить PA.cmd','Показать обновление PA.cmd','requirements-dev.txt','.gitignore','.gitattributes','LICENSE','LICENSE.md','LICENSE.txt'}
files=[]
for name in sorted(set(listed)):
 if not name:continue
 path=ROOT/name;parts=Path(name).parts
 if not path.is_file()or path.is_symlink():continue
 if len(parts)==1 and name not in root_files:continue
 if len(parts)>1 and parts[0]not in allowed_roots:continue
 if any(x in {'install-sandbox','update-sandbox','cef-contract-sandbox','native0440','home0440','font-upstream','__pycache__','node_modules','installation-backups'}for x in parts):continue
 if parts[0]=='tests'and path.suffix not in {'.lua','.py','.js','.ps1'}and len(parts)==2:continue
 if path.suffix.lower()in {'.dll','.exe','.zip','.log','.bak','.rollback','.verts','.indices','.rgba'}:continue
 if name.startswith('moonloader/config/')and name!='moonloader/config/police_assistant_2026.ini':raise AssertionError('Personal config in source list')
 files.append(path)
archive=out/'Police-Assistant-v0.44.0-source.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9)as z:
 for p in files:z.write(p,p.relative_to(ROOT).as_posix())
print('Source/context archive:',len(files),'files;',hashlib.sha256(archive.read_bytes()).hexdigest())
