local knowledge=require 'pa26_knowledge'
local edits=require 'pa26_knowledge_edits'
local model=require 'pa26_bindings'
local raw=TEST_JSON_DECODE(TEST_KNOWLEDGE_JSON)
local function joined(lines)
    local out={};for _,line in ipairs(lines)do out[#out+1]=line.label..' '..line.text end;return table.concat(out,'\n')
end
local k=knowledge.new();k:activate(assert(knowledge.validate(raw)))
local key='rules:force';local row=k.byKey[key]
check(joined(k:detail(row)):find('Для EPD',1,true))
check(joined(k:detail(row)):find('Для FBI',1,true))
check(not joined(k:detail(row,'EPD')):find('Для FBI',1,true))
check(not joined(k:detail(row,'FBI')):find('Для EPD',1,true))
check(not joined(k:detail(row,'Alcatraz')):find('Для FBI',1,true))
-- Department-only words must not produce a hit under the other filter.
local data=model.copy(raw)
for _,item in ipairs(data.rules)do if item.id=='document_basis'then
    item.department_notes={{department='EPD',text='эпдпроверкатест',sources={{source_id='541',url=k.sources['541'].url,locator='EPD note'}}},
        {department='FBI',text='фбипроверкатест',sources={{source_id='358',url=k.sources['358'].url,locator='FBI note'}}}}
end end
check(knowledge.validate(data));k:activate(data)
eq(#k:search('эпдпроверкатест',{department='EPD'}),1)
eq(#k:search('эпдпроверкатест',{department='FBI'}),0)
eq(#k:search('фбипроверкатест',{department='all'}),1)
eq(#k:search('фбипроверкатест',{department='EPD'}),0)
local refs=k:sourceLines(k.byKey['rules:document_basis'],'EPD');local hasEPD=false
for _,r in ipairs(refs)do check(r.locator~='FBI note');if r.locator=='EPD note'then hasEPD=true end end
check(hasEPD)
-- Imported documents cannot smuggle duplicate or unknown department records.
local original=k.byKey['rules:document_basis'].item
for _,bad in ipairs({
    {{department='Other',text='x',sources={}}},
    {{department='EPD',text='x',sources={}},{department='EPD',text='y',sources={}}},
    {{department='EPD',text=string.rep('x',8001),sources={}}},
    {{department='EPD',text='x',sources={{source_id='missing',url=k.sources['541'].url}}}},
    {{department='EPD',text='x',sources={{source_id='541',url='javascript:bad'}}}},
    {{department='EPD',text='x',sources='not-an-array'}}})do
    local broken=model.copy(data)
    for _,r in ipairs(broken.rules)do if r.id==original.id then r.department_notes=bad end end
    eq(knowledge.validate(broken),nil)
end
local old=model.copy(data);for _,r in ipairs(old.rules)do r.department_notes=nil end
check(knowledge.validate(old),'old catalogues must remain readable')
-- Notes are separately editable and source changes invalidate their old local interpretation.
local stamps=edits.sourceStamp(original,k.sources,'rules');local found=false
for _,s in ipairs(stamps)do if s.id=='358'then found=true end end;check(found)
local files={bundle=TEST_JSON_ENCODE(data)}
local fs={exists=function(p)return files[p]~=nil end,read=function(p)return files[p]end,
    write=function(p,v)files[p]=v;return true end,remove=function(p)files[p]=nil;return true end,
    rename=function(a,b)if not files[a]or files[b]then return nil end;files[b]=files[a];files[a]=nil;return true end}
local options={json={encode=function(v)return TEST_JSON_ENCODE(v)end,decode=function(v)return TEST_JSON_DECODE(v)end},fs=fs,path='active',bundle='bundle',personalPath='kb_personal.json'}
k=knowledge.new(options);check(k:load())
local item=model.copy(k.byKey['rules:document_basis'].item);item.department_notes[1].text='Мой порядок EPD'
k.editAction={kind='save',key='rules:document_basis',group='rules',item=item,expected=k:editSnapshot('rules:document_basis','rules')};k:tick()
check(k.editResult.ok,k.editResult.error)
local recovered=knowledge.new(options);check(recovered:load())
check(joined(recovered:detail(recovered.byKey['rules:document_basis'],'EPD')):find('Мой порядок EPD',1,true))
eq(files.bundle,TEST_JSON_ENCODE(data))
local changed=model.copy(data);for _,s in ipairs(changed.sources)do if s.id=='358'then s.snapshot_sha256=string.rep('b',64)end end
k:activate(changed);eq(k.byKey['rules:document_basis'].edit.status,'conflict')
-- An unreviewed source is visible as a warning, never as a reviewed green card.
k=knowledge.new();k:activate(data);local pending=model.copy(k.byKey[key]);pending.item.verification_status='needs_review'
eq(knowledge.tone(pending),'warning');check(knowledge.status(pending):find('изменился',1,true))
check(joined(k:detail(pending)):find('Нужно сравнение',1,true))
for _,r in ipairs(k:search('',{status='conflict'}))do check(r.item.type~='resolved')end
-- GUI exposes the fields, saves from the main loop, and never sends game text.
local fixture=require 'support.fixture';local s=fixture();s.step();s.page('knowledge')
s.edits={['##kb-search']='Выбор меры и пределов силы'};s.render();s.edits={};s.render()
local actual=k.byKey[key]
s.click=actual.title..'\n'..knowledge.status(actual)..'##kb-row-'..key;s.render();s.render();eq(s.click,nil)
s.click='Редактировать карточку##kb-edit';s.render();s.render();eq(s.click,nil)
s.click='Пояснения для EPD, FBI и Alcatraz##kb-edit-departments';s.render();eq(s.click,nil)
require('support.knowledge_reader').filters(s)
s.edits={['##kb-edit-department-EPD']='Моё отдельное пояснение EPD'};s.render();s.edits={}
s.click='Alcatraz##kb-choice-ВедомствоAlcatraz';s.render();eq(s.click,nil)
check(table.concat(s.drawnText,'\n'):find('Моя версия карточки',1,true),'filter must retain the open editor')
s.click='Сохранить карточку##kb-edit-save';s.render();s.step();s.render()
local path='moonloader\\config\\police_assistant_2026_knowledge_edits.json'
local personal=TEST_JSON_DECODE(assert(s.files[path]));local notes=personal.entries[key].patch.department_notes
eq(notes[1].text,'Моё отдельное пояснение EPD');eq(notes[2].department,'FBI')
eq(#s.sent,0);check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0)
-- An ordinary detail outside the new department is cleared, without sending.
s=fixture();s.step();s.page('knowledge')
local academy=k.byKey['rules:fbi_academy']
s.edits={['##kb-search']=academy.title};s.render();s.edits={};s.render()
s.click=academy.title..'\n'..knowledge.status(academy)..'##kb-row-'..academy.key;s.render();s.render();eq(s.click,nil)
require('support.knowledge_reader').filters(s)
s.drawnText={};s.click='EPD##kb-choice-ВедомствоEPD';s.render();eq(s.click,nil)
local visible=table.concat(s.drawnText,'\n');check(visible:find('Выберите запись слева',1,true));check(not visible:find('Пункт 8.4',1,true))
eq(#s.sent,0);eq(#s.scopes,0)
-- A shipped update is previewed explicitly; an existing active base is retained.
local prior=model.copy(data);prior.catalog_version='older-active';files.active=TEST_JSON_ENCODE(prior)
k=knowledge.new(options);check(k:load());eq(k.data.catalog_version,'older-active')
k:note('rules:document_basis','Сохранить личную заметку');check(k:flush())
k.action='preview_bundle';k:tick();check(k.candidate);eq(k.candidate.catalog_version,data.catalog_version)
eq(k.data.catalog_version,'older-active');eq(TEST_JSON_DECODE(files.active).catalog_version,'older-active')
k.action='apply_import';k:tick();eq(k.data.catalog_version,data.catalog_version)
eq(k.personal.notes['rules:document_basis'],'Сохранить личную заметку')
s=fixture();s.step();s.page('knowledge');s.click='Данные##kb-mode';s.render()
s.click='Посмотреть базу из обновления PA##kb-bundle';s.render();eq(s.click,nil);s.step();s.render()
check(table.concat(s.drawnText,'\n'):find('База из установленной сборки PA',1,true))
eq(s.files['moonloader\\config\\police_assistant_2026_knowledge.json'],nil);eq(#s.sent,0)
-- Alternative sanctions are visible and editable, rather than silently lost.
k=knowledge.new();k:activate(raw)
local disorder=k.byKey['offenses:AK:20'];check(joined(k:detail(disorder)):find('альтернатива: предупреждение',1,true))
check(joined(k:detail(disorder)):find('обязательные работы',1,true))
local broken=model.copy(raw);broken.offenses[1].sanctions[1].alternative=true;eq(knowledge.validate(broken),nil)
eq(edits.validField('sanctions',{{kind='fine',alternative=true}}),false)
broken=model.copy(raw);broken.offenses[1].sanctions[1].min=100;eq(knowledge.validate(broken),nil)
s=fixture();s.step();s.page('knowledge');s.edits={['##kb-search']='АК ст. 20'};s.render();s.edits={};s.render()
s.click=disorder.item.reference..' · '..disorder.title..'\n'..knowledge.status(disorder)..'##kb-row-'..disorder.key;s.render();s.render();eq(s.click,nil)
s.click='Редактировать карточку##kb-edit';s.render();s.click='Изменить санкции##kb-edit-sanctions';s.render()
s.edits={['##kb-edit-sanction-1-alternative']='Моя альтернатива по проверенной норме'};s.render();s.edits={}
s.click='Сохранить карточку##kb-edit-save';s.render();s.step();s.render()
personal=TEST_JSON_DECODE(assert(s.files[path]));eq(personal.entries[disorder.key].patch.sanctions[1].alternative,'Моя альтернатива по проверенной норме')
eq(#s.sent,0);check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0)
