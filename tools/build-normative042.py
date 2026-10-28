"""Build the dated, immutable user-supplied normative snapshot. Never edits personal data."""
from pathlib import Path
import hashlib
import json
import re
from collections import Counter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'docs/sources/2026-10-28'
KB = ROOT / 'moonloader/resource/pa26/knowledge-base.json'

def lua_data():
    from lupa.luajit21 import LuaRuntime
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path=.....';'..package.path",(ROOT/'moonloader/lib/?.lua').as_posix())
    value = lua.eval("require('pa26_operational')")
    def convert(v):
        if hasattr(v, 'items'):
            items = list(v.items())
            if items and all(isinstance(k,int) for k,_ in items):
                return [convert(v[i]) for i in range(1,len(items)+1)]
            return {k:convert(x) for k,x in items}
        return v
    return convert(value)

def main():
    d = json.loads(KB.read_text('utf-8-sig'))
    manifest = json.loads((SOURCE/'manifest.json').read_text('utf-8'))
    entries = {e['key']:e for e in manifest['documents']}
    for e in entries.values():
        assert hashlib.sha256((SOURCE/e['file']).read_bytes()).hexdigest()==e['sha256']
    src = {str(s['id']):s for s in d['sources']}
    if '725' not in src:
        row = dict(id='725',title='Конституция Республики Exsellent · 84 статьи',group='Законодательство',kind='IC_law',
                   url='https://forum.exsellentrp.com/threads/konstitutsiya-respubliki-exsellent.725/')
        d['sources'].append(row);src['725']=row
    src['95']['kind']='archived_law';src['95']['verification_status']='historical_source_index'
    for a in d['articles']:
        if a.get('code')=='constitution':a['verification_status']='historical_source_index'
    laws={'police':('police604','604','Закон о полиции'),'criminal':('UK','111','Уголовный кодекс'),
          'administrative':('AK','113','Административный кодекс'),'labor':('labour','100','Трудовой кодекс'),
          'fbi':('fbi','97','Закон о ФБР'),'prison':('prison603','603','Пенитенциарная система'),
          'constitution':('constitution725','725','Конституция · действующая редакция')}
    articles={a['id']:a for a in d['articles']}
    counts={}
    for key,(code,sid,label) in laws.items():
        text=(SOURCE/entries[key]['file']).read_text('utf-8-sig')
        matches=list(re.finditer(r'^Статья\s+(\d+(?:\.\d+)*)\.\s+([^\r\n]+)',text,re.M))
        counts[key]=len(matches)
        src[sid].update(article_count=len(matches),read_on='2026-10-28',source_reviewed_on='2026-10-28',
                        snapshot_sha256=entries[key]['sha256'],capture_scope='user_supplied_current_text; no new live crawl',verification_status='snapshot_reviewed')
        for n,m in enumerate(matches):
            number=m[1];body=text[m.start():matches[n+1].start() if n+1<len(matches) else len(text)].rstrip()
            assert len(body.encode())<=64000,(key,number)
            identity=f'{code}:{number}'
            row=articles.get(identity,{})
            row.update(id=identity,code=code,article=number,reference=f'{label} ст. {number}',title=m[2].strip('\u200b .'),law_label=label,
                       source=dict(source_id=sid,url=src[sid]['url'],locator=f'Статья {number}'),text=body,
                       verification_status='reviewed_source_summary',reviewed_on='2026-10-28',origin='user_supplied_verbatim',
                       source_text_sha256=hashlib.sha256(body.encode()).hexdigest())
            if code=='constitution725' and number in ('30','31'):
                row['verification_status']='historical_source_index';row['notes']='Утратила силу указом № 6 от 27.10.2026.'
            if identity not in articles:d['articles'].append(row);articles[identity]=row
    # Stable legacy radio identities remain available, including their personal edits.
    for r in d['radio']:
        if not r['id'].startswith('manual4:'):
            r['verification_status']='historical_source_index'
            r['origin']='Ранее импортированный радио-справочник; см. актуальный Мануал т. 4'
    d['radio']=[r for r in d['radio'] if not r['id'].startswith('manual4:')]
    appendix=json.loads((SOURCE/'RADIO_APPENDIX.json').read_text('utf-8'))
    for group in ('decimal','three_digit','situational_including_clearing'):
        for r in appendix[group]:
            d['radio'].append(dict(id='manual4:'+r['code'],title=r['code'],meaning=r['meaning'],aliases=[r['code']],
                verification_status='reviewed_source_summary',origin='Мануал т. 4 · актуальный текст 28.10.2026',topic='radio',
                source=dict(source_id='555',url=src['555']['url'],locator='Том 4 · 110 · полный радио-аппендикс')))
    # Include the full marking table as source text, without guessing missing images.
    d['rules']=[r for r in d['rules'] if not r['id'].startswith(('manual-current:','operation:','reg-current:'))]
    for key,sid,volume in [('manual1','472',1),('manual2','496',2),('manual3','541',3),('manual4','555',4)]:
        text=(SOURCE/entries[key]['file']).read_text('utf-8-sig')
        headings=list(re.finditer(r'^(\d{3}(?:\.\d+)*)\.?\s+([^\r\n]+)',text,re.M))
        occurrences=Counter()
        for i,m in enumerate(headings):
            number=m[1];occurrences[number]+=1
            body=text[m.start():headings[i+1].start() if i+1<len(headings) else len(text)].rstrip()
            assert len(body.encode())<=64000,(key,number)
            heading=m[2].strip('\u200b .')
            title=heading if len(heading.encode())<=900 else heading.split('. ',1)[0][:180]+'…'
            d['rules'].append(dict(id=f'manual-current:{volume}:{number}:{occurrences[number]}',title=title,
                reference=f'Мануал т. {volume}, {number} · {occurrences[number]}',text=body,manual_volume=volume,occurrence=occurrences[number],
                verification_status='reviewed_source_summary',origin='user_supplied_verbatim',topic='law',
                source=dict(source_id=sid,url=src[sid]['url'],locator=f'Том {volume}, {number}, {m[2][:100]}, вхождение {occurrences[number]}')))
        src[sid].update(read_on='2026-10-28',source_reviewed_on='2026-10-28',snapshot_sha256=entries[key]['sha256'])
    radio_text=(SOURCE/entries['manual4-radio']['file']).read_text('utf-8-sig')
    d['rules'].append(dict(id='manual-current:radio-full',title='Полный радио-аппендикс и маркировки (ROBERT = IAD)',
        text=radio_text,topic='radio',verification_status='reviewed_source_summary',origin='user_supplied_verbatim',
        source=dict(source_id='555',url=src['555']['url'],locator='Том 4 · 110 · полный аппендикс')))
    # Preserve all supplied OOC rules in readable bounded chunks, including XI/XIV.
    chunks=[];chunk=''
    for line in (SOURCE/entries['rules']['file']).read_text('utf-8-sig').splitlines(keepends=True):
        if chunk and len((chunk+line).encode())>11000:chunks.append(chunk);chunk=''
        chunk+=line
    if chunk:chunks.append(chunk)
    for i,text in enumerate(chunks,1):
        d['rules'].append(dict(id=f'reg-current:{i:02}',title=f'Правила EPD/FBI · точный текст · часть {i}',
            text=text,topic='law',verification_status='reviewed_source_summary',origin='user_supplied_verbatim',
            source=dict(source_id='201',url=src['201']['url'],locator=f'Переданный текст · фрагмент {i} из {len(chunks)}')))
    # The matrix classifies the need for RP only; it does not verify command arguments.
    matrix=json.loads((SOURCE/'COMMAND_RP_MATRIX.json').read_text('utf-8'))
    by_command={c['command']:c for c in d['commands']}
    for row in matrix['normalized_rows']:
        c=by_command[row['command']];assert c['rp_required']==row['rp_required']
        c['sources']=[dict(source_id='201',url=src['201']['url'],locator='Раздел XI · таблица пользователя 28.10.2026')]
        c['reviewed_on']='2026-10-28';c['note']='Раздел XI: классификация отыгровки. Аргументы и ответы сервера этим не подтверждены.'
    op=lua_data()
    for card in op['cards']:
        refs=[dict(source_id=sid,url=src[sid]['url'],locator=loc) for sid,loc in card.pop('sources')]
        d['rules'].append(dict(card,verification_status='reviewed_source_summary',origin='PA interpretation; see verbatim sources',
                              text=card['brief'],sources=refs,operation_id=card['id']))
    # Previous recommendations keep their original identities and quotations.
    # They must not appear as the newly supplied Miranda / constitutional basis.
    for row in d['drafts']:
        if row['id']=='rights':row['verification_status']='historical_source_index'
    for row in d['rules']:
        if row['id']=='miranda':row['verification_status']='historical_source_index'
    d['drafts']=[r for r in d['drafts'] if r['id']!='rights_manual_20261028']
    manual4=(SOURCE/entries['manual4']['file']).read_text('utf-8-sig')
    quote=re.search(r'Полный текст миранды:\s*"(.*?)"\.',manual4,re.S).group(1)
    d['drafts'].append(dict(id='rights_manual_20261028',title='Полная Миранда · Мануал 210 · 28.10.2026',topic='rights',
        origin='forum_recommendation',verification_status='source_recommendation_confirmed',source_recommended_text=quote,
        legal_disclaimer='Миранда цитируется из Мануала. Срок звонка и право обжалования разъясняются отдельно, не дописываются в цитату.',
        binder_variant_note='Редактируемая произносимая версия; источник выше остаётся дословным.',
        legal_basis=['ЗоП ст. 22 ч. 3','Конституция ст. 10 ч. 3, 15–16','Мануал т. 4, 210: адвокат 5/10 мин, звонок до 3 мин до ареста'],
        steps=[dict(type='speech',text=line) for line in op['miranda'].splitlines()],
        sources=[dict(source_id='555',url=src['555']['url'],locator='Том 4 · 210 · полный текст Миранды'),
                 dict(source_id='725',url=src['725']['url'],locator='10 ч. 3, 15–16')]))
    for gap in d['gaps']:
        if gap['id'] in ('radio_manual_variants','miranda_manual_update'):
            gap['type']='resolved';gap['resolution']='Уточнено переданными 28.10.2026 текстами Мануала. Актуальные записи опубликованы отдельно, прежние ключи сохранены как архив.'
    d['sources_full_text_republished']=True
    d['catalog_version']='erp-20261028-normative-0420'
    d['runtime_release']='PA 0.42.0; offline verification is separate from GTA acceptance'
    d['research_period']='Актуальные тексты переданы пользователем 28.10.2026. Новый обход форума не заявляется.'
    d['normative_snapshot']={'date':'2026-10-28','law_articles':counts,'radio_counts':appendix['counts'],
       'command_count':50,'rp_required':21,'rp_free':29,'source_manifest':'docs/sources/2026-10-28/manifest.json',
       'vehicle_wanted_override':'User-selected PA RP convention; generated plate is not server registration evidence'}
    # Reject accidental key collisions / uncontrolled data growth before writing.
    for group in ('articles','radio','rules'):
        ids=[r['id'] for r in d[group]];assert len(ids)==len(set(ids)),group
    data=(json.dumps(d,ensure_ascii=False,indent=2)+'\n').encode()
    assert len(data)<4*1024*1024
    KB.write_bytes(data)
    print(json.dumps({'bytes':len(data),'articles':len(d['articles']),'radio':len(d['radio']),'rules':len(d['rules']),'counts':counts}))

if __name__=='__main__':main()
