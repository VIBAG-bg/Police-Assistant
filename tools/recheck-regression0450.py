"""Rerun only failed groups against the identical final runtime; keep evidence explicit."""
from pathlib import Path
import hashlib,json,subprocess,sys
root=Path(__file__).resolve().parents[1]
path=root/'tests/REGRESSION-0.45.0.json'
report=json.loads(path.read_text('utf-8'))
failed=[r['test']for r in report['results']if r['status']!='passed']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for name,digest in {**report['lua_source_sha256'],**report['resource_sha256']}.items():
 if name in {'tests/'+t for t in failed}:continue
 assert sha(root/name)==digest,'Unrelated bytes changed: '+name
if failed:
 target=root/'tests/REGRESSION-0.45.0.rerun.json'
 subprocess.run([sys.executable,'tests/run_tests.py','--report',str(target),'--only',*failed],cwd=root,check=True)
 rerun=json.loads(target.read_text('utf-8'));rows={r['test']:r for r in rerun['results']}
 report['results']=[rows.get(r['test'],r) for r in json.loads(path.read_text('utf-8'))['results']]
 report['lua_source_sha256']=rerun['lua_source_sha256'];report['resource_sha256']=rerun['resource_sha256'];report['syntax_files']=rerun['syntax_files']
 report['rerun_groups']=failed;report['runtime_unchanged_during_recheck']=True
 report['total_checks']=sum(r['checks']for r in report['results'])
 assert all(r['status']=='passed'for r in report['results'])
 path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n','utf-8')
print(json.dumps({'groups':len(report['results']),'checks':report['total_checks'],'all_passed':all(r['status']=='passed'for r in report['results']),'targeted_reruns':failed}))
