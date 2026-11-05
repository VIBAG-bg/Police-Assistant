"""Regenerate public author defaults from the bundled authoritative source only."""
import json, re, hashlib, textwrap
from pathlib import Path

P = Path(__file__).resolve().parents[1]
SPEC = P/'docs/specs/PA-0.45.1-AUTHORITATIVE.md'
text = SPEC.read_text(encoding='utf-8-sig')

def read(name): return (P/name).read_text(encoding='utf-8-sig')
def write(name, value):
    q=P/name; q.parent.mkdir(parents=True,exist_ok=True)
    q.write_text(value,encoding='utf-8',newline='\n')
def patch(name, old, new):
    s=read(name)
    if old not in s:
        if new in s: return
        raise ValueError(f'Anchor missing: {name}: {old[:90]}')
    write(name,s.replace(old,new,1))
def lua(value):
    if isinstance(value,str): return json.dumps(value,ensure_ascii=False)
    if value is True:return 'true'
    if value is False:return 'false'
    if value is None:return 'nil'
    if isinstance(value,(int,float)):return str(value)
    if isinstance(value,list):return '{'+','.join(lua(v) for v in value)+'}'
    return '{'+','.join('['+lua(k)+']='+lua(v) for k,v in value.items())+'}'

parts=re.split(r'^### A(\d+) \(ID `(\d+)`\) — (.+)$',text,flags=re.M)
authors={}
for n in range(1,len(parts),4):
    aid,ident,name,body=parts[n:n+4]
    body=body.split('\n## 2.')[0]
    blocks=re.findall(r'```text\n(.*?)\n```',body,re.S)
    assert blocks and int(aid)==int(ident)
    authors[int(ident)]={'name':name,'scripts':blocks}
assert set(authors)==set(range(1,7))|set(range(12,89)),len(authors)
manual={}
section=re.split(r'^## 2\. ',text,flags=re.M)[1]
section=re.split(r'^## 3\. ',section,flags=re.M)[0]
for head,body in re.findall(r'^### \d+\. `/([^`]+)`[^\n]*\n(.*?)(?=^### |\Z)',section,re.M|re.S):
    manual[head]=[textwrap.dedent(b)for b in re.findall(r'```text\n(.*?)\n[ \t]*```',body,re.S)]
assert len(manual)==34,len(manual)

foot={
 'citizen':[1,14,2,17,15,45,13,18],
 'detention':[5,21,22,23,25,26,28,6,24,27,31,32],
 'frisk':[4,33,34,35,36,37,38,39],
 'wanted':[40,50,3,29,44,30,'procedure-wanted','pa-bulletins'],
 'documents':[51,16,58,59,60,65,61,62,12,63,64,66,73],
 'service':[52,53,19,20,54,55,56,57,67],
 'leadership':[76,77,78,79,80,81,41,42,43,82,83,84,85,86,87],
 'custom':[]}
car={
 'citizen':[46,'assist-traffic-nearest',55,49,15,'pa-finish-stop'],
 'detention':[50,47,48,53,'copilot-lost','copilot-finish'],
 'wanted':[40,3,'procedure-wanted',44,'procedure-wanted_list','pa-gps-clear'],
 'service':[54,56,57,'pa-call911','pa-share-coordinates',19],
 'leadership':['patrol-open','pa-patrol-busy','pa-copilot','pa-vehicle-bulletins','pa-custody-timers','copilot-patrol_continue'],
 'custom':[52,53,60,51,16,'sos']}
fnames=dict(zip(foot,['Контакт и 10-55','Задержание и конвой','Обыск и изъятие','Розыск и база КПК','Тактика и спецсредства','Рация и смена','Руководство и лекции','Свои бинды']))
cnames=dict(zip(car,['10-55 · Остановка','10-57 · Погоня и 10-66','Поиск · Пеленгация','Рация · Доклады','Патруль · Экипаж','SOS · Блокпост']))
def order(rows):return {'root':list(rows),**{g:[('b:'+str(i))if isinstance(i,int)else('s:'+i)for i in ids]for g,ids in rows.items()}}

deviations=[]
def compatible(script,where):
    lines=[]
    for line in script.splitlines():
        old=line
        # A badge number and a SA:MP routing ID are different facts. The new
        # profile field is deliberately empty until the officer enters it.
        if line.startswith('/do ') and ('бейдж' in line or 'значк' in line):
            line=line.replace('{my_id}','{badge_number}')
        if line.startswith('/todo ') and '*'in line:
            speech,action=line[6:].split('*',1)
            # Keep the full source phrase; the game's 60-char action limit is
            # never relaxed. Move only an overlong action to a separate /me.
            longest=re.sub(r'{gender:([^|{}]*)\|([^{}]*)}',lambda m:max(m.groups(),key=len),action)
            longest=re.sub(r'{(?:select_firstname|select_name|select_lastname)}','Demo Suspect',longest)
            if len(longest)>60:
                line='/me '+action+'\n'+speech
        if line!=old:deviations.append({'where':where,'source':old,'runtime':line,'reason':'Separate IC badge field'if'badge_number'in line else'Game /todo action limit: 60 characters; full action retained as /me'})
        lines.append(line)
    return '\n'.join(lines)

binds=json.loads(read('presets/pa-binds.json'));binds['schema']=2
old={b['id']:b for b in binds['bindings']}
for ident,a in authors.items():
    assert ident in old,ident
    b=old[ident];b['author_ref']=f'A{ident:02}';b['name']=a['name'];b['script']=compatible(a['scripts'][0],f'A{ident:02}')
    b['wheel_visible']=False;b['wheel_car_visible']=False
    b['wheel_group']='auto';b['wheel_car_group']='auto'
    for g,ids in foot.items():
        if ident in ids:b['wheel_visible']=True;b['wheel_group']=g
    cg=[g for g,ids in car.items()if ident in ids]
    if cg:b['wheel_car_visible']=True;b['wheel_car_group']=cg[0]
    b['wheel_car_extra_groups']=cg[1:]
    if ident in {68,69,70,71,72,74,75}:b['category']='Следствие и криминалистика'
    rc={}
    if len(a['scripts'])>1:
        assert ident in {14,46,48}
        rc={'vehicle':'traffic','bike_script':compatible(a['scripts'][1],f'A{ident:02} bike')}
    if ident==38:rc={'vehicle':'inspection'}
    if re.search(r'{select_(?:name|firstname|lastname)}',b['script']):rc['identity']=True
    # The source identifies an individual decision, not an automatic result.
    checks=[]
    if ident==48:
        checks=[{'before':i,'prompt':'Этап 10-66: обстановка позволяет передать это указание?'}for i in (1,2,3)]
    if ident==29:
        count=sum(not l.startswith('@')for l in b['script'].splitlines())
        checks=[{'before':count,'prompt':'Результат идентификации действительно получен по RP? Клиентский ник и ID не являются проверкой базы.'}]
    if ident in {30,36,39,70,71,72,75}:
        checks=[{'before':1,'prompt':'Факты для этой отыгровки подтверждены по RP? PA не определяет результаты экспертиз, документы и данные базы автоматически.'}]
    if ident==52:checks=[{'before':1,'prompt':'Есть действительная безотлагательная угроза сотруднику? Подтвердите основание для CODE 0.'}]
    if ident==50:checks=[{'before':1,'prompt':'Госномер и приметы подозреваемого действительно наблюдали по RP? ID не заменяет эти сведения.'}]
    if ident==15:rc['contact_phase']=True
    if checks:rc['checkpoints']=checks
    if rc:b['rp_context']=rc
    else:b.pop('rp_context',None)
binds['bindings']=[old[i]for i in authors]
binds['next_id']=89
write('presets/pa-binds.json',json.dumps(binds,ensure_ascii=False,indent=2)+'\n')
settings=json.loads(read('presets/pa-settings.json'));settings['schema']=2
lib=settings['settings']['data'];s=lib['settings']
for h,blocks in manual.items():
    s['manual_actions']['rules'].setdefault(h,{'enabled':True,'prefer_bind':False})['rp']=compatible(blocks[0],'/'+h)
    s['manual_actions']['rules'][h]['prefer_bind']=False
s['manual_actions']['frisk_primary_rp']=manual['frisk'][0]
s['manual_actions']['frisk_full_rp']=manual['frisk'][1]
cp=lib['vehicle']['copilot']['templates']
for key,ident,variant in [('stop_order',46,0),('stop_order_bike',46,1),('risk_single',48,0),('risk_multi',48,0),('risk_open',48,1)]:
    cp[key]='\n'.join(l[3:]for l in authors[ident]['scripts'][variant].splitlines()if l.startswith('/m '))
cp['risk_stage_question']='Обстановка позволяет передать следующий отдельный этап 10-66?'
cp['badge']='{gender:указал|указала} рукой на закреплённый на груди полицейский бейдж, демонстрируя его собеседнику.'
s.update(wheel_mode='categories',wheel_profile='full',wheel_names=fnames,wheel_child_limit=8,wheel_order=order(foot),
    wheel_car_separate=True,wheel_car_mode='categories',wheel_car_profile='extended',wheel_car_names=cnames,wheel_car_child_limit=6,wheel_car_order=order(car))
systemFoot={'copilot-approach':'citizen','copilot-documents':'citizen','copilot-explain_stop':'citizen', 'pa-bulletins':'wanted'}
for r in foot.values():
    for x in r:
        if isinstance(x,str):systemFoot[x]=next(g for g,v in foot.items()if x in v)
systemCar={x:g for g,ids in car.items()for x in ids if isinstance(x,str)}
s['wheel_system_groups'].update(systemFoot)
s['wheel_car_system_groups'].update(systemCar)
write('presets/pa-settings.json',json.dumps(settings,ensure_ascii=False,indent=2)+'\n')
catalog={'version':'0.45.1','bindings':{str(i):{'name':b['name'],'script':b['script'],**({'rp_context':b['rp_context']}if'rp_context'in b else{})} for i,b in old.items()if i in authors},
 'manual':{h:s['manual_actions']['rules'][h]['rp']for h in manual},'frisk_full':manual['frisk'][1],
 'foot':foot,'car':car,'foot_names':fnames,'car_names':cnames,'foot_order':order(foot),'car_order':order(car)}
previous=json.loads((P/'docs/specs/PA-0.45.0-AUTHOR-BASELINE.json').read_text('utf-8-sig'))
catalog['previous']={f"A{b['id']:02}":b for b in previous['bindings']}
write('moonloader/lib/pa26_author_rp.lua','-- Generated from docs/specs/PA-0.45.1-AUTHORITATIVE.md. Data only.\nreturn '+lua(catalog)+'\n')
write('docs/qa/0.45.1/AUTHOR_ORACLE.json',json.dumps({'spec_sha256':hashlib.sha256(SPEC.read_bytes()).hexdigest(),'source':authors,'manual_source':manual,'expected':catalog,'deviations':deviations},ensure_ascii=False,indent=2)+'\n')
write('docs/qa/0.45.1/RP-DEVIATIONS.md','# Технические уточнения 0.45.1\n\nИсходный документ сохранён дословно в docs/specs. Тексты ниже изменены только из-за различия номера значка и SA:MP ID либо ограничения действия /todo в 60 символов. Полный текст длинного действия сохранён отдельным /me, речь передаётся следующим сообщением. Паузы и порядок сохраняются.\n\n'+ '\n\n'.join('## '+d['where']+'\n\nПричина: '+d['reason']+'\n\nИсходник:\n```text\n'+d['source']+'\n```\nИтог:\n```text\n'+d['runtime']+'\n```'for d in deviations)+'\n')
print(json.dumps({'bindings':len(authors),'manual':len(manual),'deviations':len(deviations)},ensure_ascii=False))
