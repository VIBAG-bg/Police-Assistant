local fixture=require 'support.fixture'
local core=require 'pa26_core'
local model=require 'pa26_bindings'
local function healthy(s)
    check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(s.invalidIOReads,0)
end
local function click(s,label)s.click=label;s.render();eq(s.click,nil,'Missing control: '..label);healthy(s)end
local function setup(extra)
    local lib=model.defaults(core.defaults());lib.operations.enabled=true
    local options={demo=false,library=lib,alerts=true,categoryWheel=true}
    for k,v in pairs(extra or {})do options[k]=v end
    local s=fixture(options);s.step();s.page('addons');click(s,'Действия##tooloperations');return s
end
local s=setup();local c=s.workspace.operations;local st=s.workspace.studio
eq(s.events.onSendCommand(codec.encode('/cuff 37')),nil);s.step();eq(#c.data.rows,1)
eq(c.data.rows[1].transport,'observed');eq(c.data.rows[1].target,nil);eq(c.data.rows[1].source,'none');eq(#s.sent,0)
click(s,'#1 · /cuff · '..c.data.rows[1].date..'##operation-row-1')
click(s,'Проверить и сохранить оценку##operation-review');check(st:hasWarning() and not st.operationConfirm,'Missing explanation must not prepare a decision')
click(s,'ОК##warning-ok');s.render()
s.edits={['##По чему вы установили результат?##operation-note']='Сервер отказал: нет доступа'};s.render();s.edits={}
click(s,'Отказ##Какой результат вы установили?##operation-outcomefailure')
click(s,'Проверить и сохранить оценку##operation-review');check(st:hasModal());eq(c.data.rows[1].source,'none')
click(s,'НЕТ##confirm-no');s.step();eq(c.data.rows[1].source,'none');eq(#s.sent,0)
click(s,'Проверить и сохранить оценку##operation-review');click(s,'ДА##confirm-yes');eq(c.data.rows[1].source,'none')
s.step();eq(c.data.rows[1].status,'manual_failure');eq(c.data.rows[1].source,'manual');eq(#s.sent,0)
eq(s.workspace.journal.data.counters.cuff,nil);eq(#s.patrolEvents.data.events,0,'A local assessment is not a new patrol fact')
click(s,'Экспорт истории##operations-export');s.step()
check(s.files['moonloader\\config\\police_assistant_2026_operations_export.json'])
check(c:save(true));local saved=decodeJson(s.files['moonloader\\config\\police_assistant_2026_operations.json'])
eq(saved.rows[1].source,'manual');eq(saved.rows[1].status,'manual_failure')
click(s,'Настройки##Журнал действий##operations-pagesettings')
s.intEdits={['Срок ожидания оценки, с##operations-setting-timeout_ms']=45,['Сколько записей хранить##operations-setting-history_limit']=100};s.render();s.intEdits={};s.step()
eq(s.workspace.library.operations.timeout_ms,45000);eq(s.workspace.library.operations.history_limit,100)
s.edits={['##Наблюдаемые команды · одно имя на строку##operations-commands']='cuff\nfrisk\nsetmark'};s.render();s.edits={};s.step(700)
eq(#s.workspace.library.operations.commands,3)
s.edits={['##Наблюдаемые команды · одно имя на строку##operations-commands']='cuff 37'};s.render();s.edits={};s.step(700)
eq(#s.workspace.library.operations.commands,3,'Invalid command list cannot replace last valid settings')
for _,width in ipairs({760,1050,1680})do s.io.DisplaySize.x=width;s.io.DisplaySize.y=900;s.render();healthy(s);eq(#s.sent,0)end
local librarySaved=s.savedLibrary()
eq(librarySaved.operations.timeout_ms,45000);eq(librarySaved.operations.history_limit,100)
check(c:observe('/cuff 38','manual',nil,'observed'));check(c:save(true))
local persisted=decodeJson(s.files['moonloader\\config\\police_assistant_2026_operations.json'])
s=setup({operations=persisted,library=librarySaved});c=s.workspace.operations
eq(#c.data.rows,2);eq(c.data.rows[1].status,'manual_failure');eq(c.data.rows[2].status,'interrupted');eq(#s.sent,0)
eq(s.workspace.library.operations.timeout_ms,45000);eq(s.workspace.library.operations.history_limit,100)
click(s,'#1 · /cuff · '..c.data.rows[1].date..'##operation-row-1')
s.drawnText={};s.edits={['##ПОИСК: команда, текст или человек##operations-search']='no-such-operation'};s.render();s.edits={}
check(not table.concat(s.drawnText,'\n'):find('Сервер отказал: нет доступа',1,true),'Hidden selection cannot leave an unrelated detail card')
s.edits={['##ПОИСК: команда, текст или человек##operations-search']=''};s.render();s.edits={}
local prior=s.files['moonloader\\config\\police_assistant_2026_operations.json']
s.libraryWriteFail=true;check(c:observe('/frisk 38','manual',nil,'observed'));check(not c:save(true))
eq(s.files['moonloader\\config\\police_assistant_2026_operations.json'],prior,'Failed replacement preserves the saved history')
c:requestExport();s.step();check(c.message:find('Экспорт не выполнен',1,true));eq(#s.sent,0)
s.libraryWriteFail=false;s.step(5001);check(not c.dirty);check(not c.saveError)
eq(#decodeJson(s.files['moonloader\\config\\police_assistant_2026_operations.json']).rows,3)
-- An earlier handler can cancel or rewrite the observed command; do not log the unmodified input.
s=setup({sendCommandHandler=function()return false end});eq(s.events.onSendCommand('/cuff 37'),false,'An earlier handler cancels the command');eq(#s.workspace.operations.data.rows,0,'Cancelled commands are not observed')
s=setup({sendCommandHandler=function()return {'/frisk 38'}end});s.events.onSendCommand('/cuff 37')
eq(#s.workspace.operations.data.rows,1);eq(s.workspace.operations.data.rows[1].command,'frisk')
-- Owned executor sends are observed once, with a captured target; native callback does not add another row.
s=setup();c=s.workspace.operations
local lib=model.copy(s.workspace.library);local b=lib.bindings[1];b.script='/cuff {select_id}';b.require_target=true
check(s.workspace:save(lib));check(s.workspace:selectTarget({id=s.id,ped=s.mappedPed,name=s.name}))
check(s.workspace:request({kind='prepare',id=b.id,args={},start=true}));s.step();s.step(120)
check(s.workspace.studio.confirmPlan,'A real command needs the common confirmation')
click(s,'ДА##confirm-yes');s.step();s.step(120);s.step(1500)
eq(#c.data.rows,1);eq(c.data.rows[1].transport,'client');eq(c.data.rows[1].target.id,s.id);eq(c.data.rows[1].source,'none')
eq(#s.sent,1);eq(c:view().totals.success,0);healthy(s)
local function owned(extra)
    local f=setup(extra);local l=model.copy(f.workspace.library);local b=l.bindings[1]
    b.script='/cuff {select_id}';b.require_target=true
    check(f.workspace:save(l));check(f.workspace:selectTarget({id=f.id,ped=f.mappedPed,name=f.name}))
    check(f.workspace:request({kind='prepare',id=b.id,args={},start=true}));f.step();f.step(120)
    click(f,'ДА##confirm-yes');f.step();f.step(120);f.step(1500);return f
end
s=owned({sendCommandHandler=function()return false end});eq(#s.workspace.operations.data.rows,0);eq(#s.sent,0);healthy(s)
s=owned({sendCommandHandler=function()return {'/frisk 38'}end});eq(#s.workspace.operations.data.rows,0)
eq(#s.sent,0,'A rewritten owned command is not the frozen, reviewed operation');check(s.hasLog('другой обработчик'));healthy(s)
s=owned({sendCommandHandler=function(raw)return {raw}end});eq(#s.workspace.operations.data.rows,1)
eq(#s.sent,1,'An unchanged wrapper remains compatible');healthy(s)
local capture=model.defaults(core.defaults());capture.operations.enabled=true;capture.operations.capture_chat=true
capture.operations.commands={'help','cuff'};capture.filters={{enabled=true,prefix='HIDE'}}
s=setup({library=capture});c=s.workspace.operations;s.events.onSendCommand('/help');s.step()
eq(s.events.onServerMessage(-1,codec.encode('HIDE скрытый текст')),false);eq(#c.data.rows[1].chat,0)
eq(s.events.onServerMessage(-1,codec.encode('Команда /su: параметры нужно проверить')),nil);eq(#c.data.rows[1].chat,1)
eq(c.data.rows[1].source,'none');eq(c:view().totals.success,0)
click(s,'#1 · /help · '..c.data.rows[1].date..'##operation-row-1');check(c:save(true))
check(table.concat(s.drawnText,'\n'):find('для самостоятельной проверки',1,true))
s=setup({library=capture,serverMessageHandler=function()return false end});c=s.workspace.operations;s.events.onSendCommand('/help')
eq(s.events.onServerMessage(-1,'cancelled'),false);eq(#c.data.rows[1].chat,0)
s=setup({library=capture,serverMessageHandler=function(color)return {color,codec.encode('Заменённый видимый текст')}end})
c=s.workspace.operations;s.events.onSendCommand('/help');s.events.onServerMessage(-1,'original')
eq(c.data.rows[1].chat[1].text,'Заменённый видимый текст');eq(#s.sent,0);healthy(s)
click(s,'Настройки##Журнал действий##operations-pagesettings')
s.intEdits={['Собирать чат после команды, с##operations-setting-chat_window_ms']=15,['Строк чата на команду##operations-setting-chat_limit']=4}
s.render();s.intEdits={};s.step(700)
local captureSaved=s.savedLibrary()
eq(captureSaved.operations.chat_window_ms,15000);eq(captureSaved.operations.chat_limit,4);check(captureSaved.operations.capture_chat)
s=setup({library=captureSaved});eq(s.workspace.library.operations.chat_window_ms,15000);eq(s.workspace.library.operations.chat_limit,4)
s.events.onSendCommand('/help');s.events.onServerMessage(-1,codec.encode('Справка'))
eq(#s.workspace.operations.data.rows[1].chat,1);eq(s.workspace.operations.data.rows[1].source,'none');healthy(s)
s=setup();c=s.workspace.operations;local id=c:observe('/cuff 37','manual',nil,'observed')
local proposal=assert(c:propose(id,'success','Ручная проверка'));check(c:accept(proposal));s.step(16,{[0x23]=true})
eq(c:find(id).source,'none','End cancels an accepted local assessment before the main loop applies it');eq(c.intent,nil);eq(#s.sent,0)
onScriptTerminate(s.script)
return TEST_CHECKS
