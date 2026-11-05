"""Verify local archives byte-for-byte. This tool does not publish or install."""
from pathlib import Path, PurePosixPath
import datetime, hashlib, json, zipfile

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'dist'
def sha(data): return hashlib.sha256(data).hexdigest()
install=json.loads((ROOT/'INSTALL_MANIFEST.json').read_text('utf-8-sig'))
state=json.loads((ROOT/'docs/qa/0.45.2/STATE.json').read_text('utf-8'))
assert install['release']==state['version']=='0.45.2'
assert state['lua_regression']==state['installer_updater_fixtures']=='PASS'
assert not state['installed'] and not state['published'] and not state['live_game_written']
archives=['Police-Assistant-v0.45.2.zip','pa26-update.zip','Police-Assistant-v0.45.2-source.zip']
records=[]
for name in archives:
    path=OUT/name
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None, 'ZIP CRC failure'
        names=z.namelist()
        assert len({n.casefold() for n in names})==len(names), 'Case-insensitive duplicate ZIP entry'
        for entry in names:
            parts=PurePosixPath(entry).parts
            assert not entry.startswith(('/', '\\')) and '\\' not in entry and ':' not in entry
            assert all(p not in {'.','..'} for p in parts)
            assert not any(p in {'installation-backups','install-sandbox','update-sandbox','cef-contract-sandbox','.git','.env','node_modules','__pycache__'} or p.startswith('.pa26-') for p in parts)
            assert not entry.endswith(('.log','.bak','.rollback','.pending','.pa26-previous','.pa26-next'))
            assert not entry.lower().endswith('exsellentgps.asi')
        graphs=[n for n in names if PurePosixPath(n).name.lower()=='roads.bin']
        expected='MoonLoader/resource/pa26/roads.bin'if name=='pa26-update.zip'else'moonloader/resource/pa26/roads.bin'
        assert graphs==[expected], 'Exactly one bundled runtime graph is required'
        assert len(z.read(expected))==589664 and sha(z.read(expected))=='c1d347286ccb0349940800570078c6872bef31c12ac6d6f77a4b1cf8b857d7db'
        if name=='pa26-update.zip':
            manifest=json.loads(z.read('pa26-update.json'))
            assert manifest['version']=='0.45.2'
            assert len(names)==len(manifest['files'])+1
            assert all('/config/' not in entry.lower() and not entry.lower().startswith(('cef/','tools/','presets/')) for entry in names)
            for row in manifest['files']:
                data=z.read(row['path'])
                assert len(data)==row['size'] and sha(data)==row['sha256']
                assert data==(ROOT/row['path']).read_bytes(), row['path']
        else:
            assert z.read('INSTALL_MANIFEST.json')==(ROOT/'INSTALL_MANIFEST.json').read_bytes()
            for row in install['files']:
                entry='moonloader/'+row['path'].replace('\\','/')
                assert sha(z.read(entry))==row['sha256'], entry
            for row in install['cef_files']:
                assert sha(z.read('cef/assets/hud/'+row['path']))==row['sha256']
            for entry in names:
                assert (ROOT/entry).is_file() and z.read(entry)==(ROOT/entry).read_bytes(), entry
                if entry.lower().startswith('moonloader/config/'):
                    assert entry=='moonloader/config/police_assistant_2026.ini', 'Personal config in ZIP'
            assert json.loads(z.read('docs/qa/0.45.2/STATE.json'))['version']=='0.45.2'
            for row in install['preset_files']+install['setup_files']:
                assert z.read(row['path'])==(ROOT/row['path']).read_bytes(), row['path']
        records.append({'name':name,'files':len(names),'bytes':path.stat().st_size,'sha256':sha(path.read_bytes()),'status':'passed'})
for name in ['pa-binds.json','pa-settings.json']:
    assert (OUT/name).read_bytes()==(ROOT/'presets'/name).read_bytes()
    records.append({'name':name,'bytes':(OUT/name).stat().st_size,'sha256':sha((OUT/name).read_bytes()),'status':'passed'})
baseline=json.loads((ROOT/'docs/qa/0.45.2/BASELINE.json').read_text('utf-8'))
assert sha((OUT/'pa-binds.json').read_bytes())==baseline['files']['presets/pa-binds.json']
assert all(sha((ROOT/name).read_bytes())==digest for name,digest in baseline['protected'].items())
report={'version':'0.45.2','at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'passed',
        'crc_and_all_entries_verified':True,'runtime_matches_tested_source':True,'personal_user_files_included':False,
        'public_presets_match_manifest':True,'installed':False,'published':False,'artifacts':records}
(OUT/'ARTIFACT_VERIFICATION0452.json').write_text(json.dumps(report,indent=2)+'\n','utf-8')
(OUT/'SHA256SUMS.txt').write_text('\n'.join(row['sha256']+'  '+row['name'] for row in records)+'\n','utf-8')
print('All local archives verified; CRC, manifests, sources, reviewed public presets, and private-data exclusions passed.')
for row in records:
    print(row['name'],row['bytes'],'bytes',row['sha256'])
