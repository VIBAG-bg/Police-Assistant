"""Offline integrity + bounded public-source audit. Never changes source records."""
from pathlib import Path
import concurrent.futures, datetime, hashlib, html.parser, json, re, sys, urllib.request
from lupa.luajit21 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
def load(p):return json.loads(p.read_text('utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def norm(s):return re.sub(r'[^\w]+','',s.casefold())
kb=load(ROOT/'moonloader/resource/pa26/knowledge-base.json')
snap=ROOT/'docs/sources/2026-10-28';manifest=load(snap/'manifest.json')
hashes=[dict(file=d['file'],expected=d['sha256'],actual=sha(snap/d['file']),status='passed' if sha(snap/d['file'])==d['sha256'] else 'failed') for d in manifest['documents']]
assert all(d['status']=='passed' for d in hashes)
sources={str(s['id']):s for s in kb['sources']}
counts={k:len(kb[k]) for k in ['sources','articles','commands','rules','radio','offenses','scenario_catalog','gaps','unresolved_values']}
counts['wanted']=len(load(ROOT/'moonloader/resource/pa26/wanted-catalog.json')['rows'])
ids=[r['id'] for r in kb['articles']];assert len(ids)==len(set(ids))
orphans=[]
for group in ['articles','rules','commands','radio','offenses']:
 for r in kb[group]:
  refs=([r['source']]if r.get('source')else [])+r.get('sources',[])
  for ref in refs:
   if str(ref['source_id'])not in sources:orphans.append((group,r['id'],ref))
assert not orphans
lua=LuaRuntime(unpack_returned_tuples=True)
def to_lua(v):
 if isinstance(v,dict):return lua.table_from({k:to_lua(x) for k,x in v.items()})
 if isinstance(v,list):return lua.table_from([to_lua(x) for x in v])
 return v
def from_lua(v):
 if hasattr(v,'items'):
  d={k:from_lua(x) for k,x in v.items()}
  if d and all(isinstance(k,int)for k in d)and sorted(d)==list(range(1,len(d)+1)):return [d[k] for k in range(1,len(d)+1)]
  return d
 return v
lua.execute("package.path='moonloader/lib/?.lua;'..package.path")
lua.globals().RAW=to_lua(kb)
lua.globals().ENCODE=lambda x:json.dumps(from_lua(x),ensure_ascii=False,separators=(',',':'))
data=lua.execute("local k=require('pa26_knowledge').new({json={encode=ENCODE}});k:activate(RAW);return require('pa26_knowledge_important').build(k)")
presentation=from_lua(data)
coverage=[]
for card in presentation['cards']:
 for section in card['sections']:
  for row in section['rows'] or []:
   coverage.append(dict(card=card['id'],section=section['id'],row=row['id'],key=row['key'],references=row.get('refs',[]),
    provenance=row.get('provenance',[]),classification=row.get('verification'),note=row.get('note'),edit_status=row.get('edit_status')))
matrix=load(snap/'COMMAND_RP_MATRIX.json')
report={'version':'0.44.0','audited_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'counts':counts,'snapshot_hashes':hashes,'article_id_collisions':0,'orphan_article_sources':orphans,
 'coverage':coverage,'unique_display_rows':len(presentation['rows']), 'public_sources':[],
 'matrix':matrix,'preserved_unknowns':kb['unresolved_values'],
 'policy':load(ROOT/'moonloader/resource/pa26/knowledge-policy.json'),
 'warning':'Integrity is not a manual legal review or live game-command acceptance.'}
files={'113':'administrative.txt','111':'criminal.txt','604':'police.txt','97':'fbi.txt','603':'prison.txt','100':'labor.txt',
 '725':'constitution.txt','201':'rules.txt','472':'manual1.txt','496':'manual2.txt','541':'manual3.txt','555':'manual4.txt'}
for row in coverage:
 for ref in row['provenance']or []:
  ref['file']='docs/sources/2026-10-28/'+files[ref['source_id']]if ref['source_id']in files else None
report['AK_fines']=[]
for a in kb['articles']:
 if a.get('code')=='AK'and a.get('article','').isdigit()and 20<=int(a['article'])<=62:
  branches=a.get('sanctions',[])
  report['AK_fines'].append({'id':a['id'],'reference':a['reference'],'branches':branches,
   'all_branch_excerpts_in_source':all(norm(b['source_excerpt'])in norm(a['text'])for b in branches),
   'currency_conversion':None,'classification':'verified_snapshot_only'})
assert len(report['AK_fines'])==43 and all(a['branches']and a['all_branch_excerpts_in_source']for a in report['AK_fines'])
wanted=load(ROOT/'moonloader/resource/pa26/wanted-catalog.json')
report['wanted_rows']=[dict(id=r['id'],title=r['title'],stars=r['stars'],refs=r['refs'],
 game_verification='verified_snapshot_only',observation_date=wanted['observed_on'],
 legal_association='suggested'if r['refs']else'unmapped',mapping_status=r['mapping_status'])for r in wanted['rows']]
class Text(html.parser.HTMLParser):
 def __init__(self):super().__init__();self.parts=[];self.skip=0
 def handle_starttag(self,tag,attrs):
  if tag in ('script','style'):self.skip+=1
 def handle_endtag(self,tag):
  if tag in ('script','style'):self.skip=max(0,self.skip-1)
 def handle_data(self,data):
  if not self.skip:self.parts.append(data)
def fetch(s):
 row={'source_id':str(s['id']),'url':s['url'],'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
 try:
  req=urllib.request.Request(s['url'],headers={'User-Agent':'PoliceAssistant-SourceReview/0.44.0 (public read-only)'})
  with urllib.request.urlopen(req,timeout=18)as response:
   raw=response.read(4_000_000);row['http_status']=response.status
  doc=Text();doc.feed(raw.decode('utf-8','replace'));text=' '.join(doc.parts);normalized=norm(text)
  row['response_sha256']=hashlib.sha256(raw).hexdigest();row['response_bytes']=len(raw)
  if len(text)<3000 or 'checkingyourbrowser'in normalized or 'accessdenied'in normalized or 'youmustbeloggedin'in normalized:
   row['classification']='access_blocked';row['reason']='No verifiable public body / challenge or login page';return row
  articles=[a for a in kb['articles'] if str(a.get('source',{}).get('source_id'))==row['source_id'] and a.get('text')]
  checked=[]
  for a in articles:
   expected=norm(a['text']);match=len(expected)>40 and expected in normalized
   checked.append({'id':a['id'],'classification':'verified_current' if match else 'needs_manual_review',
    'method':'normalized complete supplied article substring in public page'})
  row['article_comparisons']=checked
  row['classification']='verified_current' if checked and all(a['classification']=='verified_current'for a in checked)else 'needs_manual_review'
  row['reason']='Public page read; only exact complete normalized article matches are current-verified. Other text requires manual comparison.'
 except Exception as exc:row.update(classification='access_blocked',reason=str(exc)[:400])
 return row
if '--online'in sys.argv:
 unique={s['url']:s for s in kb['sources']}
 assert all(u.startswith('https://forum.exsellentrp.com/')for u in unique)
 with concurrent.futures.ThreadPoolExecutor(max_workers=4)as pool:
  for row in pool.map(fetch,unique.values()):
   report['public_sources'].append(row);print(row['source_id'],row['classification'],flush=True)
else:
 prior=ROOT/'docs/knowledge-audit-0.44.0.json'
 if prior.exists():report['public_sources']=load(prior).get('public_sources',[])
by_source={s['source_id']:s for s in report['public_sources']}
for r in coverage:
 statuses=[by_source.get(str(p['source_id']),{}).get('classification','verified_snapshot_only')for p in r['provenance']or []]
 if r['classification']in ('missing','conflict'):continue
 r['classification']='conflict'if r.get('note')and('расхож' in r['note']or'сравнен' in r['note'])else ('verified_current'if statuses and all(x=='verified_current'for x in statuses)else 'verified_snapshot_only')
(ROOT/'docs/knowledge-audit-0.44.0.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n','utf-8')
print('Counts:',counts,'; coverage:',len(coverage),'; unique:',report['unique_display_rows'])
