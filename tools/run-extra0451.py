"""Additional read-only CEF analysis and isolated setup fixtures; never install live."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import datetime, hashlib, json, os, subprocess, time
ROOT=Path(__file__).resolve().parents[1]
TESTS=['test_installer_legacy_paths.ps1','test_setup_launch.ps1',
       'test_cef_adaptive0451.ps1','test_cef_install_adaptive0451.ps1',
       'test_gps_patrol_install0450.ps1','test_allinone0451.ps1']
def run(name):
    env=dict(os.environ);env['PSModulePath']='C:/Windows/System32/WindowsPowerShell/v1.0/Modules'
    temp=Path.home()/'Documents/Codex/tmp451';temp.mkdir(exist_ok=True)
    env['TEMP']=env['TMP']=str(temp)
    start=time.monotonic();log=ROOT/'tests'/('QA0451-'+name.removesuffix('.ps1')+'.log')
    try:
        p=subprocess.run(['C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe',
            '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(ROOT/'tests'/name)],
            cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=1200)
        log.write_bytes(p.stdout)
        return dict(test=name,status='passed' if p.returncode==0 else 'failed',
                    exit_code=p.returncode,elapsed_seconds=round(time.monotonic()-start,2),log=log.relative_to(ROOT).as_posix())
    except subprocess.TimeoutExpired as error:
        log.write_bytes(error.stdout or b'')
        return dict(test=name,status='timeout',elapsed_seconds=1200,log=log.relative_to(ROOT).as_posix())
results=[]
with ThreadPoolExecutor(max_workers=2) as pool:
    for future in as_completed([pool.submit(run,name) for name in TESTS]):
        row=future.result();results.append(row);print(row['test'],row['status'],row['elapsed_seconds'],flush=True)
report=dict(version='0.45.1',at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
            environment='Windows PowerShell 5.1; fixture destinations only; HUD source read only',
            game_started=False,live_game_written=False,results=results)
reference=os.getenv('PA_QA_HUD_SOURCE')
report['cef_reference_sha256']=hashlib.sha256((Path(reference)/'main.js').read_bytes()).hexdigest() if reference else None
report['cef_reference_is_live_installation']=not bool(reference)
(ROOT/'tests/EXTRA0451.json').write_text(json.dumps(report,indent=2)+'\n','utf-8')
raise SystemExit(0 if all(r['status']=='passed' for r in results) else 1)
