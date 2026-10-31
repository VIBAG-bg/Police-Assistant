"""Run the new behavioural regressions against the untouched published baseline."""
from pathlib import Path
import hashlib,json,os
root=Path(__file__).resolve().parents[1]
baseline=root.parent/'Police-Assistant-2026-v0.43.2-dev'
runner=root/'tests/run_tests.py'
scope={'__file__':str(runner),'__name__':'reproduction'}
exec(compile(runner.read_text('utf-8').split('results = []')[0],str(runner),'exec'),scope)
rows=[]
for name in ['test_direction0433.lua','test_staff0433.lua','test_streamout0433.lua','test_ground_drafts0433.lua','test_cef_budget0433.lua']:
    os.chdir(baseline)
    lua=scope['runtime']()
    try:
        lua.execute((root/'tests'/name).read_bytes())
    except Exception as exc:
        rows.append({'test':name,'reproduced':True,'error':str(exc),'new_test_sha256':hashlib.sha256((root/'tests'/name).read_bytes()).hexdigest()})
        print(name+': baseline failure reproduced')
    else:
        rows.append({'test':name,'reproduced':False})
os.chdir(root)
report={'baseline':'0.43.2','baseline_commit':'93ca2a3c707c93ebb79bfd3cb501c0ac2ee8c3a6','all_reproduced':all(r['reproduced'] for r in rows),'results':rows,'game_written':False}
(root/'tests/REPRODUCTION0433.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert report['all_reproduced']
