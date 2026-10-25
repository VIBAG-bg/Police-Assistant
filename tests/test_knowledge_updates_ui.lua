local fixture=require 'support.fixture'
local M=require 'pa26_knowledge'
local model=require 'pa26_bindings'
local function has(s,text)
    for _,line in ipairs(s.drawnText)do if line:find(text,1,true)then return true end end
    return false
end
local s=fixture();s.step();s.page('knowledge');s.click='Данные##kb-mode';s.render()
s.click='Проверить файл импорта##kb-import';s.render();s.step();check(has(s,'Файл не найден'))
s.click='ОК##warning-ok';s.render();s.render()
local raw=TEST_JSON_DECODE(TEST_KNOWLEDGE_JSON);raw.catalog_version='test-native-next'
s.files['moonloader\\config\\police_assistant_2026_knowledge_import.json']=TEST_JSON_ENCODE(raw)
s.click='Проверить файл импорта##kb-import';s.render();s.step()
s.click='Применить базу##kb-apply';s.render();check(s.modalOpen);eq(s.click,nil)
local yes,no
for _,b in ipairs(s.buttonCalls)do if b.label=='ДА##kb-confirm'then yes=b end;if b.label=='НЕТ##kb-confirm'then no=b end end
check(yes and no);check(yes.color.g>yes.color.r);check(no.color.r>no.color.g)
s.click='НЕТ##kb-confirm';s.render();check(not s.modalOpen)
eq(s.files['moonloader\\config\\police_assistant_2026_knowledge.json'],nil);eq(#s.sent,0)
s.click='Применить базу##kb-apply';s.render();check(s.modalOpen)
s.keyMessage(27,true);s.render();check(not s.modalOpen);s.keyMessage(27,false);s.step()
check(s.frames[1].condition(),'Escape should dismiss modal and retain main page')
s.click='Применить базу##kb-apply';s.render();s.click='ДА##kb-confirm';s.render();check(not s.modalOpen)
s.step();eq(TEST_JSON_DECODE(s.files['moonloader\\config\\police_assistant_2026_knowledge.json']).catalog_version,'test-native-next')
eq(#s.sent,0);eq(#s.scopes,0);check(not s.hasLog('Ошибка интерфейса'))
-- Every category has a native detail card, including a conflict and a source.
s=fixture();s.step();s.page('knowledge')
local index=M.new();index:activate(assert(M.validate(TEST_JSON_DECODE(TEST_KNOWLEDGE_JSON))))
for _,group in ipairs(M.groups)do
    s.combo='##kb-choice-Раздел';s.click=group[2]..'##kb-choice-Раздел'..group[1];s.render();s.combo=nil;s.render()
    eq(s.click,nil,'category choice must work')
    local rows=index:search('',{group=group[1]});check(#rows>0)
    local target=rows[1];local ref=target.item.reference or target.item.command or(target.group=='radio'and target.item.id or'')
    local title=target.title==ref and ref or(ref~=''and ref..' · '..target.title or target.title)
    s.click=title..'\n'..M.status(target)..'##kb-row-'..target.key;s.render();s.render()
    eq(s.click,nil,'detail must open for '..group[1]);check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0)
end
eq(#s.sent,0)
-- Knowledge links open the assistant; old amount/article drafts are not made.
s=fixture({demo=false});s.step();s.commands.pa26select('37');s.step();s.page('knowledge')
s.edits={['##kb-search']='УБИЛ'};s.render();s.edits={}
s.click='УК ст. 39 · Убийство\nРазобран источник##kb-row-offenses:UK:39';s.render();s.render()
local count=#s.workspace.library.bindings
s.click='Розыск##kb-action';s.render();eq(s.click,nil);s.render()
check(has(s,'Введите /su ID'));eq(#s.sent,0);eq(#s.workspace.library.bindings,count)
s.click='Новая форма##case-new';s.render();eq(s.click,nil)
local form=s.workspace.studio.caseForm;check(form);eq(form.stage,'identity');eq(form.target.id,37)
check(not form.life_ack);eq(form.passport_seen,'unknown');check(not form.ic_name or form.ic_name=='')
-- A specific observed game card suggests only its reason, with fresh identity.
s.page('knowledge');s.edits={['##kb-search']='01.01'};s.render();s.edits={}
local catalog=require 'pa26_wanted_catalog';local card=index.byKey[catalog.rows[1].knowledge_key]
s.click=card.title..'\n'..M.status(card)..'##kb-row-'..card.key;s.render();s.render();eq(s.click,nil)
s.click='Открыть помощник с этим пунктом##kb-wanted-reason';s.render();eq(s.click,nil)
check(not s.workspace.studio.caseForm)
s.click='Новая форма##case-new';s.render();form=s.workspace.studio.caseForm
eq(form.reason_id,'01.01');eq(form.stage,'identity');check(not form.life_ack)
eq(#s.workspace.library.bindings,count);eq(#s.sent,0)
-- Target changes cannot reuse prior passport details or consent.
form.passport_seen='yes';form.ic_name='Alex Smith';form.mask='no';form.life_ack=true
s.id=38;s.name='Second_Player';s.mappedPed=99;s.commands.pa26select('38');s.step()
local preview=s.caseForms:preview(form);eq(preview,nil)
s.click='Новая форма##case-new';s.render();form=s.workspace.studio.caseForm
check(form);eq(form.target.id,38);eq(form.passport_seen,'unknown');check(not form.life_ack)
check(not form.ic_name or form.ic_name=='');check(not s.hasLog('Ошибка интерфейса'));eq(#s.sent,0)
