local fixture=require 'support.fixture'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local function healthy(s)
    check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(s.invalidIOReads,0)
end
local function click(s,label)s.click=label;s.render();eq(s.click,nil,'Not visible: '..label..'\n'..table.concat(s.logs,'\n'));healthy(s)end
local function toggle(s,label)s.toggle=label;s.render();eq(s.toggle,nil,'Not visible: '..label);healthy(s)end
local function edit(s,values)s.edits=values;s.render();for k in pairs(s.edits)do error('Not visible input: '..k)end;s.edits={};healthy(s)end
local function open(s,page)
    s.commands.pa26();s.render();s.page('addons');click(s,'Открыть быстрое окно помощников (F4)##assist-open')
    click(s,({evidence='Фиксация',training='Обучение',megaphone='Мегафон'})[page]..'##assist-tabs'..page)
end
local lib=model.defaults(core.defaults());lib.vehicle.enabled=true;lib.vehicle.require_patrol=false
lib.profile.name='Victor Auditore';lib.alerts.enabled=true;lib.alerts.on_duty=true;lib.patrol_session.station='SFPS';lib.patrol_session.unit='P-01'
lib.assist.evidence.enabled=true
local s=fixture({demo=false,library=lib,alerts=true,notifications=true,categoryWheel=true,evidenceFiles=function(state)
    return {clock=function()check(not state.rendererContext,'File clock must be read by the main loop');return 100000 end,
        verify=function(path)check(not state.rendererContext,'File IO from renderer');if not state.image then return nil,'Нет нового снимка'end;return {key='new1',path=path,size=600}end}
end})
s.step();s.page('addons');click(s,'Открыть быстрое окно помощников (F4)##assist-open')
click(s,'Фиксация##assist-tabsevidence')
edit(s,{['##Что фиксируем##evidence-label']='Проверка документов'})
click(s,'Подготовить фиксацию##evidence-start');check(s.workspace.studio.assistConfirm);eq(#s.sent,0)
click(s,'НЕТ##confirm-no');s.step();check(not s.evidence.active);eq(#s.sent,0)
click(s,'Подготовить фиксацию##evidence-start');click(s,'ДА##confirm-yes');s.step();eq(#s.sent,0)
s.step(1600);s.step();check(s.evidence.active);eq(#s.sent,0)
s.drawnText={};s.render();check(table.concat(s.drawnText,'\n'):find('Нажмите F8',1,true),'A local hint must remain visible after PA closes')
open(s,'evidence');edit(s,{['##Путь к созданному снимку##evidence-file']='C:\\SAMP\\sa-mp-001.png'})
click(s,'Проверить новый файл##evidence-check');s.step();check(not s.evidence.pendingRecord);eq(#s.workspace.library.assist.history,0)
click(s,'ОК##warning-ok');s.render()
s.image=true;click(s,'Проверить новый файл##evidence-check');s.step();s.step(500)
eq(#s.workspace.library.assist.history,1);check(s.workspace.library.assist.history[1].verified);eq(#s.sent,0)
-- Edits are retained, command verification cannot silently enable a send.
edit(s,{['##Команда времени без аргументов##evidence-command']='/time'});toggle(s,'Отправлять команду времени после ДА##evidence-time-enabled')
s.step(700);check(s.workspace.studio.autosaves.evidence.failed);check(not s.workspace.library.assist.evidence.time_enabled)
click(s,'ОК##warning-ok');s.render()
edit(s,{['##Где проверена команда: /help или ответ сервера##evidence-source']='/help, проверил на сервере'})
toggle(s,'Я проверил эту команду на сервере##evidence-verified');s.step(700)
check(s.workspace.library.assist.evidence.time_enabled)
click(s,'Подготовить фиксацию##evidence-start');click(s,'ДА##confirm-yes');s.step();s.step(1500)
eq(#s.sent,1);eq(s.sent[1].line,'/time');s.step(1600);check(s.evidence.active)
-- End cancels the wait even when no chat command remains in the queue.
s.step(16,{[0x23]=true});s.step();check(not s.evidence.active);eq(#s.sent,1)
open(s,'training');click(s,'Добавить учебную карточку##study-add');s.step()
eq(#s.workspace.library.assist.training.cards,1)
edit(s,{['##Название карточки##study-name']='Моя карточка',['##Вопрос##study-question']='Вопрос?\nВторая строка.',
    ['##Ответ##study-answer']='Проверяемый ответ.',['##Ссылка или название источника##study-source']='Мой конспект',
    ['##Редакция / дата источника##study-revision']='20.10.2026'})
toggle(s,'Использовать в занятиях##study-card-enabled');s.step(700)
check(s.workspace.library.assist.training.cards[1].enabled)
click(s,'Начать занятие##study-start');check(s.workspace.studio.study.session)
click(s,'Показать ответ##study-reveal');click(s,'Знал ответ##study-known');s.step()
eq(s.workspace.library.assist.training.progress['1'].known,1)
eq(s.workspace.studio.study.session.known,1)
-- Revision invalidation, autosave and destructive confirmation use the same GUI.
edit(s,{['##Ответ##study-answer']='Ответ изменён.'});s.step(700)
check(not s.workspace.library.assist.training.progress['1'])
click(s,'ОК##warning-ok');s.render()
click(s,'Удалить карточку##study-delete');click(s,'НЕТ##confirm-no');eq(#s.workspace.library.assist.training.cards,1)
click(s,'Удалить карточку##study-delete');click(s,'ДА##confirm-yes');eq(#s.workspace.library.assist.training.cards,0)
local stored=s.savedLibrary()
check(stored.assist.evidence.time_verified);eq(#stored.assist.training.cards,0);eq(#stored.assist.history,2)
-- An incomplete active draft can be deleted without first inventing an answer/source.
click(s,'Добавить учебную карточку##study-add');s.step();toggle(s,'Использовать в занятиях##study-card-enabled');s.step(700)
check(s.workspace.studio.autosaves.training.failed)
click(s,'ОК##warning-ok');s.render()
click(s,'Удалить карточку##study-delete');click(s,'ДА##confirm-yes');eq(#s.workspace.library.assist.training.cards,0)
click(s,'Фиксация##assist-tabsevidence')
edit(s,{['##Команда времени без аргументов##evidence-command']='/clock'});s.step(700)
check(not s.workspace.library.assist.evidence.time_verified);check(not s.workspace.library.assist.evidence.time_enabled)
-- Helper window follows normal screen bounds and releases cursor through F9.
for _,resolution in ipairs({{800,600},{1280,720},{1920,1080}})do
    s.io.DisplaySize={x=resolution[1],y=resolution[2]};s.render();healthy(s)
end
s.commands.pa26();s.render();healthy(s);eq(#s.sent,1);onScriptTerminate(s.script)
