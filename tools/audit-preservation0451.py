"""Evidence for the frozen 0.45.0 baseline; no game access or writes."""
from pathlib import Path
import hashlib,json,re
ROOT=Path(__file__).resolve().parents[1]
sha=lambda data:hashlib.sha256(data).hexdigest()
base=json.loads((ROOT/'docs/qa/0.45.1/BASELINE.json').read_text('utf-8'))
checks=[]
def check(ok,name):
    assert ok,name
    checks.append(name)
for name,digest in base['protected_files'].items():check(sha((ROOT/name).read_bytes())==digest,name+' unchanged')
check(sha((ROOT/'docs/specs/PA-0.45.1-AUTHORITATIVE.md').read_bytes())==base['authoritative_spec_sha256'],'Authoritative document byte identical')
for name in ['CEF_CONTRACT.json','UPDATE_CEF_BASELINE.json','tools/cef-contract-engine.ps1',
             'tools/pa-cef-contract.ps1','tools/pa-setup.ps1','tools/pa-setup-window.ps1',
             'tools/pa-start.ps1','tools/pa-seed-presets.ps1']:
    if name in base['files']:check(sha((ROOT/name).read_bytes())==base['files'][name],name+' unchanged')
old=(ROOT/'docs/specs/PA-0.45.0-INSTALLER.txt').read_bytes()
check(sha(old)==base['files']['install.ps1'],'Installer reference matches baseline')
def without_owned(s):return re.sub(r'\$paOwned\s*=\s*@\(.*?\)\s*\r?\n','OWNED_ALLOWLIST\n',s.replace('\r\n','\n'),count=1,flags=re.S)
check(without_owned(old.decode('utf-8-sig'))==without_owned((ROOT/'install.ps1').read_text('utf-8-sig')),'Installer changes limited to owned PA file allowlist')
prior=json.loads((ROOT/'docs/specs/PA-0.45.0-AUTHOR-BASELINE.json').read_text('utf-8-sig'))
check(sha((ROOT/'docs/specs/PA-0.45.0-AUTHOR-BASELINE.json').read_bytes())==base['files']['presets/pa-binds.json'],'Prior public bindings are a verified stock snapshot')
current=json.loads((ROOT/'presets/pa-binds.json').read_text('utf-8'))
old40=next(b for b in prior['bindings']if b['id']==40)['script']
new40=next(b for b in current['bindings']if b['id']==40)['script']
a=json.loads((ROOT/'docs/specs/PA-0.45.0-SETTINGS-BASELINE.json').read_text('utf-8-sig'))
b=json.loads((ROOT/'presets/pa-settings.json').read_text('utf-8'))
check(sha((ROOT/'docs/specs/PA-0.45.0-SETTINGS-BASELINE.json').read_bytes())==base['files']['presets/pa-settings.json'],'Prior public settings snapshot verified')
check(a['settings']['data']['settings']['manual_actions']['rules']['setmark']['rp']==b['settings']['data']['settings']['manual_actions']['rules']['setmark']['rp'],'Protected manual setmark verbatim unchanged')
approved=a['settings']['data']['settings']['manual_actions']['rules']['setmark']['rp']
check('\n'.join(line for line in new40.splitlines() if line.startswith(('/me ','/do ')))==approved,'Author A40 uses the existing approved manual RP verbatim')
check(re.findall(r'@wait\(\d+\)',old40)==re.findall(r'@wait\(\d+\)',new40),'Existing A40 delay order preserved')
check(a['settings']['data']['settings']['window_layout']==b['settings']['data']['settings']['window_layout'],'Author F4/F9 layout unchanged')
check(a['config']==b['config'],'Author INI and HUD defaults unchanged')
check(len(current['bindings'])==83,'83 public author bindings')
check(len(json.loads((ROOT/'docs/qa/0.45.1/AUTHOR_ORACLE.json').read_text('utf-8'))['manual_source'])==34,'34 canonical manual actions')
check(current['schema']==b['schema']==2,'New public format rejects silent downgrade by old clients')
report=dict(version='0.45.1',status='PASS',checks=len(checks),items=checks,live_game_written=False,published=False)
(ROOT/'docs/qa/0.45.1/PRESERVATION.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n','utf-8')
print('Preservation PASS:',len(checks),'checks; CEF/GPS/updater byte-identical, setmark and geometry preserved.')
