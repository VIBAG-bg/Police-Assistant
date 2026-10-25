local fixture=require 'support.fixture'
local model=require 'pa26_bindings';local core=require 'pa26_core'
local preferences=require 'pa26_procedure_settings'
-- Real GUI editing, autosave, persisted file, then real main/executor timing.
local seed=model.defaults(core.defaults());seed.alerts.on_duty=true;seed.weapons.enabled=true
local s=fixture({demo=false,library=seed,alerts=true});s.step();s.page('settings')
s.click='Оружие##settings-tab-weapons';s.render();eq(s.click,nil)
local original=s.imgui.SliderInt;local edited=false
s.imgui.SliderInt=function(label,value,min,max)
    if label=='Оружие в руках, с##weapons-delay_ms'then
        eq(min,1);eq(max,30)
        if not edited then value[0]=1;edited=true;return true end
    end
    return original(label,value,min,max)
end
s.render();s.step(700);check(edited);eq(s.workspace.library.weapons.delay_ms,1000)
eq(s.savedLibrary().weapons.delay_ms,1000);eq(s.savedLibrary().weapons.cooldown_ms,seed.weapons.cooldown_ms)
s.imgui.SliderInt=original;s.commands.pa26();s.step();check(not s.frames[1].condition())
s.weapon=31;local start=s.now;s.step();s.step(999);eq(#s.sent,0)
s.step(1);s.step();check(#s.sent>0,'One-second setting did not reach the real scheduler')
check(s.sent[1].time-start>=1000);check(s.sent[1].time-start<1500,'New setting still used the old five-second delay')
check(s.sent[1].line:match('^/me '));onScriptTerminate(s.script)

-- The multiline reminder GUI must save line breaks, with the exact preview text.
s=fixture({library=model.defaults(core.defaults()),alerts=true});s.step();s.page('addons')
s.click='Процедуры##toolprocedures';s.render();eq(s.click,nil)
s.click='Розыск · настройки##Процедуры##case-pagewanted_settings';s.render();eq(s.click,nil)
local body='Проверь результат на сервере.\nЗатем проверь необходимость снятия звёзд.'
s.edits={['##Текст напоминания##wanted-reminder-text']=body};s.render();s.edits={};s.step(700)
eq(s.savedLibrary().procedures.wanted_reminder_text,body)
eq(s.workspace.library.procedures.wanted_reminder_text,body);eq(#s.sent,0)
check(not s.hasLog('Ошибка интерфейса'));onScriptTerminate(s.script)
local cfg=preferences.defaults();cfg.wanted_reminder_text='Первая\r\nВторая'
eq(assert(preferences.validate(cfg)).wanted_reminder_text,'Первая\nВторая')
for _,bad in ipairs({' \n ', 'text\ttext', 'text\0',string.rep('я',701)})do cfg.wanted_reminder_text=bad;check(not preferences.validate(cfg))end

-- An older active knowledge file gets the observed cards in memory only.
local knowledge=require 'pa26_knowledge';local raw=TEST_JSON_DECODE(TEST_KNOWLEDGE_JSON)
local rules={};for _,r in ipairs(raw.rules)do if not r.id:match('^game_wanted_')then rules[#rules+1]=r end end;raw.rules=rules
local commands={};for _,r in ipairs(raw.commands)do if r.command~='/wanted'then commands[#commands+1]=r end end;raw.commands=commands
raw.catalog_version='older-active-personal-catalog';raw.offenses[1].notes='Сохранённое пояснение в активной базе.'
local oldBytes=TEST_JSON_ENCODE(raw);local personal=knowledge.personalDefaults()
personal.notes['offenses:UK:39']='Моя заметка';personal.favorites={'offenses:UK:39'}
local personalBytes=TEST_JSON_ENCODE(personal);local files={active=oldBytes,personal=personalBytes,bundle=TEST_KNOWLEDGE_JSON}
local fs={exists=function(p)return files[p]~=nil end,read=function(p)return files[p]end,
    write=function()error('Overlay must not write any file')end,rename=function()error('No rename')end,remove=function()error('No removal')end}
local k=knowledge.new({path='active',bundle='bundle',personalPath='personal',fs=fs,
    json={encode=function(v)return TEST_JSON_ENCODE(v)end,decode=function(v)return TEST_JSON_DECODE(v)end}})
check(k:load());eq(k.data.catalog_version,raw.catalog_version);eq(files.active,oldBytes);eq(files.personal,personalBytes)
eq(k.data.offenses[1].notes,raw.offenses[1].notes);eq(k.personal.notes['offenses:UK:39'],'Моя заметка')
local catalog=require 'pa26_wanted_catalog'
for _,r in ipairs(catalog.rows)do check(k.byKey[r.knowledge_key])end
local wanted=0;for _,r in ipairs(k.data.commands)do if r.command=='/wanted'then wanted=wanted+1 end end;eq(wanted,1)
k:activate(k.data);eq(#k.records,1318,'Repeated activation must not duplicate observed cards')
