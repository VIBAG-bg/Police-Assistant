"""Run the same twelve independent rollback points in three isolated folders."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import os,json,subprocess,hashlib,time,datetime
r=Path(__file__).resolve().parents[1];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest=sha(r/'INSTALL_MANIFEST.json');installer=sha(r/'install.ps1');started=time.monotonic()
def run(i):
 env=dict(os.environ);env['PSModulePath']='C:/Windows/System32/WindowsPowerShell/v1.0/Modules'
 env['TEMP']=env['TMP']=str(r.parents[1]/'tmp-installer-shards');Path(env['TEMP']).mkdir(exist_ok=True)
 args=['C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(r/'tests/test_installer.ps1'),'-ShardIndex',str(i),'-ShardCount','3']
 with (r/f'tests/INSTALLER-shard{i}.log').open('wb')as f:proc=subprocess.run(args,cwd=r,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=1200)
 assert proc.returncode==0,f'Installer shard {i} failed; inspect log'
 d=json.loads((r/f'tests/INSTALLER_RESULTS-shard{i}.json').read_text('utf-8-sig'))
 assert d['status']=='passed'and d['manifest_sha256'].lower()==manifest and d['installer_sha256'].lower()==installer
 print('Installer shard',i,'PASS',d['rollback_after'],flush=True);return d
with ThreadPoolExecutor(max_workers=3)as pool:rows=list(pool.map(run,range(3)))
assert manifest==sha(r/'INSTALL_MANIFEST.json')and installer==sha(r/'install.ps1')
points=sorted(n for row in rows for n in row['rollback_after']);assert len(points)==len(set(points))==12
d=rows[0];d.update(rollback_after=points,independent_process_shards=3,sandbox='three independent workspace fixture folders')
(r/'tests/INSTALLER_RESULTS.json').write_text(json.dumps(d,indent=2)+'\n','utf-8')
p=r/'tests/PLATFORM0450.json';report=json.loads(p.read_text('utf-8'));report['results']=[x for x in report['results']if x['test']!='test_installer.ps1']
report['results'].append({'test':'test_installer.ps1','status':'passed','exit_code':0,'elapsed_seconds':round(time.monotonic()-started,2),'log':'tests/INSTALLER-shard0.log','independent_process_shards':3})
report['at_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();p.write_text(json.dumps(report,indent=2)+'\n','utf-8')
print('All twelve final-source rollback points PASS.',flush=True)
