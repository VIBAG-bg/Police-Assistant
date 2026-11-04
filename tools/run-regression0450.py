"""Run the unchanged isolated-test protocol in independent process shards."""
from pathlib import Path
import argparse,ast,concurrent.futures,hashlib,json,os,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--jobs',type=int,choices=[1,2,3,4],default=2);args=p.parse_args()
tree=ast.parse((ROOT/'tests/run_tests.py').read_text('utf-8'));names=[]
for node in tree.body:
 if isinstance(node,ast.Assign)and any(isinstance(t,ast.Name)and t.id=='test_names'for t in node.targets):names=ast.literal_eval(node.value)
 if isinstance(node,ast.Expr)and isinstance(node.value,ast.Call):
  c=node.value
  if isinstance(c.func,ast.Attribute)and isinstance(c.func.value,ast.Name)and c.func.value.id=='test_names':
   value=ast.literal_eval(c.args[0])
   if c.func.attr=='append':names.append(value)
   elif c.func.attr=='extend':names.extend(value)
assert names and len(names)==len(set(names))
shards=[names[i::args.jobs]for i in range(args.jobs)]
before={f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest()for f in (ROOT/'moonloader').rglob('*.lua')}
def run(index):
 report=ROOT/f'tests/REGRESSION-0.45.0.part{index}.json';report.unlink(missing_ok=True)
 with (ROOT/f'tests/RUN-0450-part{index}.log').open('w',encoding='utf-8')as output:
  proc=subprocess.run([sys.executable,'tests/run_tests.py','--keep-going','--report',str(report),'--only',*shards[index]],cwd=ROOT,stdout=output,stderr=subprocess.STDOUT)
 if not report.exists():raise RuntimeError(f'Shard {index} did not complete; inspect its log')
 return proc.returncode,json.loads(report.read_text('utf-8'))
with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs)as pool:reports=list(pool.map(run,range(args.jobs)))
base=reports[0][1];found={}
for code,r in reports:
 assert r['lua_source_sha256']==base['lua_source_sha256']and r['resource_sha256']==base['resource_sha256'],'Different sources across shards'
 for row in r['results']:assert row['test']not in found;found[row['test']]=row
assert set(found)==set(names),'Missing or repeated test groups'
assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==v for n,v in before.items()),'Runtime changed during regression'
base['results']=[found[n]for n in names];base['total_checks']=sum(x['checks']for x in base['results']);base['independent_process_shards']=args.jobs
(ROOT/'tests/REGRESSION-0.45.0.json').write_text(json.dumps(base,ensure_ascii=False,indent=2)+'\n','utf-8')
failed=[r for r in base['results']if r['status']!='passed']
print(json.dumps({'groups':len(names),'checks':base['total_checks'],'failed':failed,'syntax_files':base['syntax_files']},ensure_ascii=False),flush=True)
sys.exit(1 if failed or any(code for code,_ in reports)else 0)
