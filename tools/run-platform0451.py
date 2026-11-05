"""Run fixture-only Windows installer/updater checks. Never target a real game."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import argparse, datetime, json, os, subprocess, time

ROOT = Path(__file__).resolve().parents[1]
version=json.loads((ROOT/'INSTALL_MANIFEST.json').read_text('utf-8-sig'))['release']
short=version.replace('.','').zfill(4)
PS = Path('C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe')
TESTS = ['test_installer.ps1', 'test_author_install.ps1', 'test_setup.ps1',
         'test_setup_window.ps1', 'test_cef_installer0440.ps1', 'test_updater.ps1',
         'test_update_legacy_paths.ps1', 'test_update_progress.ps1']
parser=argparse.ArgumentParser()
parser.add_argument('--only', choices=TESTS)
parser.add_argument('--skip-installer', action='store_true', help='Run the separate installer rollback shards afterwards.')
args=parser.parse_args()

def run(name):
    start = time.monotonic()
    command = [str(PS), '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
               '-File', str(ROOT / 'tests' / name)]
    log = ROOT / 'tests' / (f'QA{short}-' + name.removesuffix('.ps1') + '.log')
    try:
        # Codex's PowerShell 7 module path must not shadow inbox Windows PS 5.1 modules.
        env = dict(os.environ)
        env['PSModulePath'] = str(Path(env.get('WINDIR', 'C:/Windows')) /
                                  'System32/WindowsPowerShell/v1.0/Modules')
        # MAX_PATH fixtures need a short workspace temp root, not the runner's
        # deeply nested redirected %TEMP%. Only these child processes see it.
        temp = Path(env.get('PA_QA_TEMP_ROOT', str(Path.home() / 'Documents/Codex/tmp45')))
        temp.mkdir(parents=True, exist_ok=True)
        env['TEMP'] = env['TMP'] = str(temp)
        timeout=1200 if name=='test_installer.ps1' else 600
        completed = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, timeout=timeout, env=env)
        log.write_bytes(completed.stdout)
        return {'test': name, 'status': 'passed' if completed.returncode == 0 else 'failed',
                'exit_code': completed.returncode, 'elapsed_seconds': round(time.monotonic()-start, 2),
                'log': log.relative_to(ROOT).as_posix()}
    except subprocess.TimeoutExpired as error:
        log.write_bytes(error.stdout or b'')
        return {'test': name, 'status': 'timeout', 'elapsed_seconds': timeout,
                'log': log.relative_to(ROOT).as_posix()}

previous_path=ROOT/f'tests/PLATFORM{short}.json'
previous=json.loads(previous_path.read_text('utf-8')) if args.only and previous_path.is_file() else {}
results = [row for row in previous.get('results',[]) if row['test']!=args.only] if args.only else []
with ThreadPoolExecutor(max_workers=3) as pool:
    selected=[args.only] if args.only else [name for name in TESTS if not args.skip_installer or name!='test_installer.ps1']
    for task in as_completed([pool.submit(run, name) for name in selected]):
        result = task.result()
        results.append(result)
        print(result['test'], result['status'], result['elapsed_seconds'], flush=True)
report = {'version': version, 'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'environment': 'Windows PowerShell 5.1; workspace fixtures only; no GUI launch',
          'game_started': False, 'live_game_written': False, 'results': sorted(results, key=lambda row: row['test'])}
if args.only:
    report['rerun']={'test':args.only,'previous_status':next((row['status'] for row in previous.get('results',[]) if row['test']==args.only),None),
                    'reason':'Allow full installer fault-injection suite to finish beyond original ten-minute runner limit.'}
(ROOT / f'tests/PLATFORM{short}.json').write_text(json.dumps(report, indent=2)+'\n', 'utf-8')
raise SystemExit(0 if all(row['status']=='passed' for row in results) else 1)
