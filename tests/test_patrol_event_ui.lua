local fixture=require 'support.fixture'
local core=require 'pa26_core'
local model=require 'pa26_bindings'
local function healthy(s)
    check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(s.invalidIOReads,0)
end
local function click(s,label)s.click=label;s.render();eq(s.click,nil,'Missing control: '..label);healthy(s)end
local function setup(demo,extra)
    local lib=model.defaults(core.defaults());lib.patrol_session.enabled=true;lib.patrol_session.unit='A-1'
    lib.profile.name='Victor Auditore';lib.profile.callsign='A-1';lib.alerts.on_duty=true
    lib.patrol_events.enabled=true
    local options={demo=demo==true,library=lib,alerts=true,notifications=true,categoryWheel=true}
    for k,v in pairs(extra or {})do options[k]=v end
    local s=fixture(options);s.step();s.page('partners');click(s,'Патруль##Напарники и служба##partners-pagepatrol')
    click(s,'Начать патруль##patrol-start');s.expectedStart=model.copy(s.workspace.studio.patrolConfirm.prepared.lines);click(s,'ДА##confirm-yes');s.step();s.step(1500)
    click(s,'События##Напарники и служба##partners-pageevents')
    return s
end
local s=setup(false);local c=s.patrolEvents;local baseline=#s.sent;eq(baseline,#s.expectedStart);check(baseline>0)
for i,line in ipairs(s.expectedStart)do eq(s.sent[i].line,line,'Send exactly the start preview, with no invented direction')end
local st=s.workspace.studio;st.patrolEventKind='custom';s.render();click(s,'Подготовить событие##patrol-event-new')
check(st.patrolEventForm);eq(st.patrolEventForm.kind,'custom')
s.edits={['##Дополнительные сведения##patrol-event-details']='Проверка завершена'};s.render();s.edits={}
click(s,'Записать и передать доклад##patrol-event-report');check(st:hasWarning() and not st.patrolEventConfirm);eq(#c.data.events,0,'No acknowledgement = no fact')
click(s,'ОК##warning-ok');s.render()
s.toggle='Подтверждаю, что событие действительно произошло##patrol-event-ack';s.render()
click(s,'Записать и передать доклад##patrol-event-report');check(st:hasModal());eq(#s.sent,baseline)
click(s,'НЕТ##confirm-no');s.step();eq(#c.data.events,0);eq(#s.sent,baseline)
click(s,'Записать и передать доклад##patrol-event-report');click(s,'ДА##confirm-yes');eq(#s.sent,baseline)
s.step(1500);healthy(s);eq(c.data.facts.custom,1);eq(c.data.reports.custom,1);eq(#s.sent,baseline+1)
check(s.sent[#s.sent].line:find('Проверка завершена',1,true))
local saved=decodeJson(s.files['moonloader\\config\\police_assistant_2026_patrol_events.json'])
eq(saved.events[1].source,'manual');eq(saved.facts.custom,1);eq(saved.reports.custom,1)
click(s,'Записать и передать доклад##patrol-event-report');check(st:hasWarning() and not st.patrolEventConfirm);s.step();eq(c.data.facts.custom,1)
click(s,'ОК##warning-ok');s.render()
click(s,'Журнал и счётчики##События##patrol-event-pagehistory');healthy(s)
s.page('stats');check(table.concat(s.drawnText,'\n'):find('События патруля',1,true))
click(s,'Открыть журнал событий патруля##stats-patrol-events');s.render();healthy(s)
-- Native command offers a check; no automatic radio, fact or target assertion.
check(s.workspace:selectTarget({id=s.id,ped=s.mappedPed,name=s.name}))
s.step();eq(s.events.onSendCommand(codec.encode('/cuff '..s.id)),nil)
eq(#c.attempts,1);eq(c.data.facts.detention,nil);eq(#s.sent,baseline+1)
st.patrolEventPage='work';s.render();click(s,'Задержание · проверить##patrol-attempt-'..c.attempts[1].id)
eq(st.patrolEventForm.subject,'','IC name is not inferred from a nickname')
eq(st.patrolEventForm.target,nil,'Native command arguments have not been parsed')
click(s,'Связать с Player_Name [37]##patrol-event-bind-target')
s.edits={['##Человек · IC-имя или известные приметы##patrol-event-subject']='Человек в синей куртке'};s.render();s.edits={}
s.toggle='Подтверждаю, что событие действительно произошло##patrol-event-ack';s.render()
click(s,'Записать без доклада##patrol-event-local');click(s,'ДА##confirm-yes');s.step()
eq(c.data.facts.detention,1);eq(c.data.reports.detention,nil);eq(#s.sent,baseline+1)
-- New feature text, conditions and key have real persistent GUI controls.
click(s,'Настройки##События##patrol-event-pagesettings')
s.edits={['##Текст доклада##patrol-event-template-custom']='{unit}: новый шаблон {details}.'};s.render();s.edits={};s.step(700)
eq(s.workspace.library.patrol_events.events.custom.template,'{unit}: новый шаблон {details}.')
saved=s.savedLibrary()
eq(saved.patrol_events.events.custom.template,'{unit}: новый шаблон {details}.')
for _,w in ipairs({760,1000,1600})do s.io.DisplaySize.x=w;s.io.DisplaySize.y=900;s.render();healthy(s)end
click(s,'Назначить##patrol-events-key');check(st.keyCapture);eq(st.keyCapture.request.group,'patrol_events');click(s,'Отмена##capture-cancel')
-- Previous RPC handlers retain priority; rejected commands never become attempts.
s=setup(true,{sendCommandHandler=function()return false end});eq(s.events.onSendCommand(codec.encode('/cuff 37')),false);eq(#s.patrolEvents.attempts,0)
st=s.workspace.studio;st.patrolEventKind='custom';s.render();click(s,'Подготовить событие##patrol-event-new')
s.edits={['##Дополнительные сведения##patrol-event-details']='Демо'};s.render();s.edits={}
s.toggle='Подтверждаю, что событие действительно произошло##patrol-event-ack';s.render()
click(s,'Записать и передать доклад##patrol-event-report');click(s,'ДА##confirm-yes');s.step(1500)
eq(#s.sent,0);eq(s.patrolEvents.data.facts.custom,nil);eq(s.patrolEvents.data.reports.custom,nil);eq(#s.patrolEvents.data.events,1)
-- End before dispatch does not commit a fact or leave a delayed radio intent.
s=setup(false);baseline=#s.sent;st=s.workspace.studio;st.patrolEventKind='custom';s.render()
click(s,'Подготовить событие##patrol-event-new')
s.edits={['##Дополнительные сведения##patrol-event-details']='Отменяемое событие'};s.render();s.edits={}
s.toggle='Подтверждаю, что событие действительно произошло##patrol-event-ack';s.render()
click(s,'Записать и передать доклад##patrol-event-report');click(s,'ДА##confirm-yes')
s.step(16,{[0x23]=true});eq(#s.patrolEvents.data.events,0);check(not s.patrolEvents.intent)
s.step(1500);eq(#s.sent,baseline)
