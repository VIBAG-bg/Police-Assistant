"""Validate owned runtime, public files and local documentation before publication."""
from pathlib import Path
import hashlib, json, re

ROOT=Path(__file__).resolve().parents[1]
# PowerShell 5.1 treats scripts without a BOM as the ANSI code page.
for script in [ROOT/'install.ps1', *(ROOT/'tools').glob('*.ps1'), *(ROOT/'moonloader/resource/pa26/updater').glob('*.ps1')]:
    data=script.read_bytes()
    if any(b>=128 for b in data):
        assert data.startswith(b'\xef\xbb\xbf'), f'Windows PowerShell needs UTF-8 BOM: {script}'
manifest=json.loads((ROOT/'INSTALL_MANIFEST.json').read_text('utf-8-sig'))
if manifest['release'] in {'0.45.0','0.45.1','0.45.2'}:
    graph=ROOT/'moonloader/resource/pa26/roads.bin'
    assert graph.stat().st_size==589664 and hashlib.sha256(graph.read_bytes()).hexdigest()=='c1d347286ccb0349940800570078c6872bef31c12ac6d6f77a4b1cf8b857d7db'
    assert sum(row['path']=='resource\\pa26\\roads.bin' for row in manifest['files'])==1
    assert hashlib.sha256((ROOT/'moonloader/lib/pa26_update_platform.lua').read_bytes()).hexdigest()=='995b131aa0250b7ea407915ad7d109de71a8e43cec088603bc99cc489e60565f'
if manifest.get('update_carried_assets'):
    fm=json.loads((ROOT/'moonloader/resource/pa26/fonts/manifest.json').read_text('utf-8'))
    font=(ROOT/'moonloader/resource/pa26/fonts/fa-solid-900.ttf').read_bytes()
    carrier=(ROOT/'moonloader/lib/pa26_icon_font.lua').read_text('utf-8')
    data=carrier.split('data=table.concat({',1)[1].split('}),license=',1)[0]
    decoded=bytes(int(n) for n in re.findall(r'\\(\d{3})',data))
    assert decoded==font and hashlib.sha256(font).hexdigest()==fm['sha256'], 'Font carrier must contain the original pinned bytes'
    license_text=(ROOT/'moonloader/resource/pa26/fonts/LICENSE.txt').read_text('utf-8')
    assert carrier.split('license=[==[',1)[1].split(']==]',1)[0]==license_text, 'Full original font license must travel in updates'
    assert carrier.split('manifest=[==[',1)[1].split(']==]',1)[0]==(ROOT/'moonloader/resource/pa26/fonts/manifest.json').read_text('utf-8')
    assert {r['path'] for r in manifest['update_carried_assets']}=={'resource\\pa26\\fonts\\'+n for n in ('fa-solid-900.ttf','LICENSE.txt','manifest.json')}
assert re.fullmatch(r'\d+\.\d+\.\d+(?:-[\w.-]+)?', manifest['release'])
installer=(ROOT/'install.ps1').read_text('utf-8-sig')
owned=re.search(r'\$paOwned\s*=\s*@\((.*?)\)\s*\r?\n',installer,re.S)
assert owned, 'Installer runtime allowlist is missing'
allowed=re.findall(r"'([^']+)'",owned.group(1))
assert len(allowed)==len(set(allowed)) and set(allowed)=={r['path'] for r in manifest['files']}, 'Installer allowlist and release manifest differ'
count=0
for prefix,key in [('moonloader','files'),('cef/assets/hud','cef_files')]:
    names=set()
    for row in manifest[key]:
        rel=row['path'].replace('\\','/')
        assert not rel.startswith('/') and '..' not in rel.split('/')
        assert rel.lower() not in names;names.add(rel.lower())
        p=ROOT/prefix/rel
        assert p.is_file(), p
        assert hashlib.sha256(p.read_bytes()).hexdigest()==row['sha256'], p
        if 'config/' in rel:assert rel=='config/police_assistant_2026.ini'
        count+=1
for p in (ROOT/'moonloader/config').iterdir():
    assert p.name=='police_assistant_2026.ini', 'Personal config must not be published'
main=(ROOT/'moonloader/police_assistant_2026.lua').read_text('utf-8')
core=(ROOT/'moonloader/lib/pa26_core.lua').read_text('utf-8')
assert "script_version('%s')"%manifest['release'] in main
assert "core.VERSION ~= '%s'"%manifest['release'] in main, 'Bootstrap version guard differs from release'
assert "VERSION = '%s'"%manifest['release'] in core
assert "repository='VIBAG-bg/Police-Assistant'" in (ROOT/'moonloader/lib/pa26_updater.lua').read_text('utf-8')
links=0
for p in [ROOT/'README.md', *(ROOT/'docs').rglob('*.md')]:
    for link in re.findall(r'\]\(([^)]+)\)',p.read_text('utf-8')):
        if re.match(r'[a-zA-Z]+:|#',link):continue
        target=link.split('#')[0]
        assert (p.parent/target).exists(), f'Broken link in {p.relative_to(ROOT)}: {target}'
        links+=1
setup_files={'tools/pa-setup.ps1','tools/pa-setup-window.ps1','tools/pa-start.ps1','tools/pa-seed-presets.ps1','DEPENDENCIES.json'}
if manifest['release']=='0.45.1':
    setup_files.update({'tools/pa-legacy-0440.json','tools/pa-legacy-migration.ps1','tools/pa-legacy-lua.ps1','tools/pa-legacy-presets.lua'})
assert len(manifest['setup_files'])==len(setup_files)
assert {row['path'] for row in manifest['setup_files']}==setup_files
for row in manifest['setup_files']:
    assert hashlib.sha256((ROOT/row['path']).read_bytes()).hexdigest()==row['sha256']
print(f'Package verified: {count} runtime entries, version {manifest["release"]}, {links} local documentation links.')

for row in manifest['preset_files']:
    assert row['path'] in {'presets/manifest.json','presets/pa-binds.json','presets/pa-settings.json','presets/baseline.json'}
    assert hashlib.sha256((ROOT/row['path']).read_bytes()).hexdigest()==row['sha256']
