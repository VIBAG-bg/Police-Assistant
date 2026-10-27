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
assert re.fullmatch(r'\d+\.\d+\.\d+(?:-[\w.-]+)?', manifest['release'])
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
assert "VERSION = '%s'"%manifest['release'] in core
assert "repository='VIBAG-bg/Police-Assistant'" in (ROOT/'moonloader/lib/pa26_updater.lua').read_text('utf-8')
links=0
for p in [ROOT/'README.md', *(ROOT/'docs').rglob('*.md')]:
    for link in re.findall(r'\]\(([^)]+)\)',p.read_text('utf-8')):
        if re.match(r'[a-zA-Z]+:|#',link):continue
        target=link.split('#')[0]
        assert (p.parent/target).exists(), f'Broken link in {p.relative_to(ROOT)}: {target}'
        links+=1
for row in manifest['setup_files']:
    assert row['path'] in {'tools/pa-setup.ps1','tools/pa-setup-window.ps1','tools/pa-start.ps1','tools/pa-seed-presets.ps1','DEPENDENCIES.json'}
    assert hashlib.sha256((ROOT/row['path']).read_bytes()).hexdigest()==row['sha256']
print(f'Package verified: {count} runtime entries, version {manifest["release"]}, {links} local documentation links.')

for row in manifest['preset_files']:
    assert row['path'] in {'presets/manifest.json','presets/pa-binds.json','presets/pa-settings.json','presets/baseline.json'}
    assert hashlib.sha256((ROOT/row['path']).read_bytes()).hexdigest()==row['sha256']
