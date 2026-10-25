local knowledge=require 'pa26_knowledge'
local edits=require 'pa26_knowledge_edits'
local model=require 'pa26_bindings'
local raw=TEST_JSON_DECODE(TEST_KNOWLEDGE_JSON)
local files={bundle=TEST_KNOWLEDGE_JSON};local failing=false
local fs={exists=function(p)return files[p]~=nil end,read=function(p)return files[p]end,
    write=function(p,s)if failing then return nil end;files[p]=s;return true end,
    rename=function(a,b)if not files[a]or files[b]then return nil end;files[b]=files[a];files[a]=nil;return true end,
    remove=function(p)files[p]=nil;return true end}
local options={json={encode=function(v)return TEST_JSON_ENCODE(v)end,decode=function(v)return TEST_JSON_DECODE(v)end},fs=fs,path='active',bundle='bundle',personalPath='kb_personal.json',
    stamp=function()return '2026-10-15T01:00:00Z'end}
local k=knowledge.new(options);check(k:load())
local function action(a)k.editAction=a;k:tick();return k.editResult end
local function save(key,group,item,expected)
    return action({kind='save',key=key,group=group,item=item,expected=expected or(key and k:editSnapshot(key,group))})
end
local key='rules:document_basis';local original=model.copy(k.byKey[key].item)
local item=model.copy(original);item.title='Проверка документов: моё пояснение';item.aliases={'чей паспорт','моя памятка'};item.local_text='Проверить законное основание, затем попросить документ.'
local result=save(key,'rules',item);check(result.ok,result.error)
eq(k.byKey[key].title,item.title);eq(knowledge.status(k.byKey[key]),'Моя правка')
eq(k.data.rules[4].title,raw.rules[4].title);check(edits.equal(k.baseByKey[key],original))
eq(files.bundle,TEST_KNOWLEDGE_JSON);eq(#k:search('моя памятка',{group='rules'}),1)
eq(#k:search('',{status='personal'}),1)
local persisted=files.kb_edits_json or files['kb_edits.json'];check(persisted)
local recovered=knowledge.new(options);check(recovered:load());eq(recovered.byKey[key].title,item.title)
-- Ordinary updates merge untouched fields; new values never get frozen by the override.
local nextData=model.copy(raw);nextData.catalog_version='update-unrelated'
for _,row in ipairs(nextData.rules)do if row.id=='document_basis'then row.text='Новый текст неотредактированного поля.'end end
k:activate(nextData);eq(k.byKey[key].item.text,'Новый текст неотредактированного поля.')
eq(k.byKey[key].title,item.title);eq(k.byKey[key].edit.status,'override')
-- A changed edited field requires an explicit choice. Until then the new base is shown.
for _,row in ipairs(nextData.rules)do if row.id=='document_basis'then row.title='Новая официальная подпись'end end
nextData.catalog_version='update-same-field';k:activate(nextData)
eq(k.byKey[key].edit.status,'conflict');eq(k.byKey[key].title,'Новая официальная подпись')
eq(#k:search('',{status='personal_conflict'}),1)
local snap=k:editSnapshot(key,'rules')
result=action({kind='resolve',key=key,choices={},expected=snap});check(not result.ok)
result=action({kind='resolve',key=key,choices={title='mine'},expected=snap});check(result.ok,result.error)
eq(k.byKey[key].title,item.title);eq(k.byKey[key].edit.status,'override')
eq(k.byKey[key].item.text,'Новый текст неотредактированного поля.')
-- A read/check timestamp alone does not invalidate personal text; content changes do.
local sid=k.byKey[key].refs[1].source_id
nextData=model.copy(nextData)
for _,s in ipairs(nextData.sources)do if s.id==sid then s.last_checked_utc='2026-10-16T00:00:00Z'end end
k:activate(nextData);eq(k.byKey[key].edit.status,'override')
for _,s in ipairs(nextData.sources)do if s.id==sid then s.snapshot_sha256=string.rep('a',64)end end
k:activate(nextData);check(k.byKey[key].edit.sourceChanged)
snap=k:editSnapshot(key,'rules')
result=action({kind='resolve',key=key,choices={},expected=snap});check(not result.ok)
result=action({kind='resolve',key=key,choices={},ackSource=true,expected=snap});check(result.ok,result.error)
eq(k.byKey[key].edit.status,'override')
-- A stale editor cannot silently overwrite a newer personal revision.
snap=k:editSnapshot(key,'rules');item=model.copy(k.byKey[key].item);item.local_text='Правка номер два.'
result=save(key,'rules',item);check(result.ok)
item.local_text='Старое окно пытается записать текст.';result=save(key,'rules',item,snap)
check(not result.ok);eq(k.byKey[key].item.local_text,'Правка номер два.')
local before=files['kb_edits.json'];failing=true
item.local_text='Сбой записи';result=save(key,'rules',item);check(not result.ok)
eq(k.byKey[key].item.local_text,'Правка номер два.');eq(files['kb_edits.json'],before);failing=false
-- Missing originals remain in the edits file and export; reappearing originals reattach.
local removed=model.copy(nextData)
for n,row in ipairs(removed.rules)do if row.id=='document_basis'then table.remove(removed.rules,n);break end end
k:activate(removed);eq(k.byKey[key],nil);eq(#k.detachedEdits,1);check(k.edits.state.entries[key])
result=action({kind='export'});check(result.ok);check(TEST_JSON_DECODE(files['kb_edits_export.json']).entries[key])
k:activate(nextData);check(k.byKey[key]);eq(k.byKey[key].edit.status,'override')
result=action({kind='reset',key=key});check(result.ok);eq(k.byKey[key].title,'Новая официальная подпись')
eq(k.edits.state.entries[key],nil);eq(files.bundle,TEST_KNOWLEDGE_JSON)
-- Every supported category has a useful editable record; sources/profile cannot be forged.
local ids={}
for _,g in ipairs({'rules','offenses','commands','articles','radio','drafts','scenario_catalog','gaps'})do
    local v=edits.newItem(g);v.title='Моя карточка '..g;v.local_text='Текст, введённый игроком.'
    if g=='offenses'then v.criterion='Мой разбор';v.reference='АК ст. 43';v.local_source_url=raw.offenses[1].source.url;v.sanctions={{kind='fine',min=2,max=5,unit='PM',condition='По обстоятельствам'}}end
    if g=='drafts'then v.steps={{type='speech',text='Тестовая реплика.'}}end
    result=save(nil,g,v);check(result.ok,result.error);ids[g]=result.key
    eq(knowledge.status(k.byKey[result.key]),'Моя карточка');eq(k.baseByKey[result.key],nil)
end
eq(#k.records,1378) -- 1370 catalog rows after forum refresh + eight personal cards
local composed,err=k:compose(k.byKey[ids.offenses],{kind='fine',identity='passport',ic_name='Alex Smith',part='',reason='',fine='100',command='/fine {select_id} {param1} {param2}'},500,codec)
check(composed,err);eq(composed.knowledge.personal_origin,'custom');check(composed.knowledge.personal_updated_at)
local withoutReference=model.copy(k.byKey[ids.offenses]);withoutReference.item.reference=''
local rejected,why=k:compose(withoutReference,{kind='fine'},501,codec);eq(rejected,nil);check(why:find('номер статьи',1,true))
local count=k.edits.state.next_id;result=action({kind='reset',key=ids.radio});check(result.ok)
result=save(nil,'radio',{title='Следующая моя запись',meaning='Значение'});check(result.ok)
check(result.key:find(string.format('%06d',count),1,true));check(result.key~=ids.radio)
result=save(nil,'sources',{title='Подменный источник'});check(not result.ok)
result=save(nil,'patrol',{title='Подменный профиль'});check(not result.ok)
-- Imported edits cannot mutate verification flags or the quoted source recommendation.
local state=model.copy(k.edits.state);state.entries['drafts:rights']={kind='override',group='drafts',id='rights',
    updated_at='now',base_version='test',base_item=model.copy(raw.drafts[1]),base_sources={},patch={verification_status='source_recommendation_confirmed'}}
eq(edits.validate(state),nil)
state.entries['drafts:rights'].patch={source_recommended_text='Ложная цитата.'};eq(edits.validate(state),nil)
state.entries['drafts:rights'].patch={title=42};eq(edits.validate(state),nil)
state.entries['drafts:rights'].patch={sanctions={}};eq(edits.validate(state),nil)
-- Validation failure and damaged files preserve both active data and user bytes.
files['kb_edits_import.json']='{broken';local kept=files['kb_edits.json']
result=action({kind='preview_import'});check(not result.ok);eq(files['kb_edits.json'],kept)
files['kb_edits_import.json']=files['kb_edits_export.json'];result=action({kind='preview_import'});check(result.ok)
result=action({kind='import'});check(result.ok);check(k.edits.state.entries[key]);eq(files.bundle,TEST_KNOWLEDGE_JSON)
files['kb_edits.json']='{damaged';files['kb_edits.json.bak']=nil;files['kb_edits.json.rollback']=nil
local damaged=knowledge.new(options);check(damaged:load());check(damaged.edits.blocked);eq(#damaged.records,1370)
damaged.editAction={kind='save',group='radio',item={title='Нельзя затереть файл',meaning='Тест'}};damaged:tick()
check(not damaged.editResult.ok);eq(files['kb_edits.json'],'{damaged')
damaged.editCandidate=edits.defaults();damaged.editAction={kind='import'};damaged:tick();check(damaged.editResult.ok)
check(not damaged.edits.blocked);eq(files['kb_edits.json.rejected'],'{damaged')
local invalid=edits.defaults();invalid.next_id=2
invalid.entries['commands:local-000001']={kind='custom',group='commands',id='local-000001',updated_at='now',item={id='local-000001',title='Команда без названия',rp_required=true}}
damaged.editCandidate=invalid;damaged.editAction={kind='import'};damaged:tick();check(damaged.editResult.ok)
eq(#damaged.detachedEdits,1);eq(damaged.detachedEdits[1].status,'invalid');eq(#damaged.records,1370)
local v=model.copy(damaged.byKey['drafts:rights'].item);v.steps={{type='speech',text='Моя реплика, а не цитата.'}}
damaged.editAction={kind='save',key='drafts:rights',group='drafts',item=v,expected=damaged:editSnapshot('drafts:rights','drafts')};damaged:tick()
check(damaged.editResult.ok)
local labels={};for _,line in ipairs(damaged:detail(damaged.byKey['drafts:rights']))do labels[line.label]=line.text end
check(labels['Мой вариант для бинда']);eq(labels['Вариант для бинда'],nil)
eq(labels['Текст из темы форума'],raw.drafts[1].source_recommended_text)
eq(edits.validField('sanctions',{{kind='fine',min=5,max=2,unit='PM'}}),false)
