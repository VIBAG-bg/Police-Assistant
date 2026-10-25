local fixture=require 'support.fixture'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local function healthy(s)
    check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(s.invalidIOReads,0)
    eq(#s.patrolEvents.data.events,0);eq(#s.sent,0)
end
local function click(s,label)s.click=label;s.render();eq(s.click,nil,'Missing control: '..label);healthy(s)end
local function setup(mode)
    local lib=model.defaults(core.defaults());lib.patrol_events.enabled=true;lib.patrol_events.require_patrol=false
    lib.patrol_events.toast_mode=mode or 'confirm';lib.alerts.on_duty=true;lib.weapon_warning.enabled=false
    local s=fixture({demo=false,library=lib,alerts=true});s.step()
    check(s.workspace:selectTarget({id=s.id,ped=s.mappedPed,name=s.name}));s.step()
    if s.frames[1].condition()then s.commands.pa26();s.step()end
    return s
end
local function attempt(s)
    s.chat=true;s.step();eq(s.events.onSendCommand(codec.encode('/cuff 37')),nil)
    eq(#s.patrolEvents.attempts,1);s.step();check(not s.notifications:view().visible)
    s.chat=false;s.step();s.step(150);check(s.notifications:view().visible);eq(s.notifications.active.owner,'patrol');healthy(s)
end
local function key(s,k)
    s.physicalDown={};s.step(150);s.physicalDown={[k]=true};s.step();s.physicalDown={};s.step();healthy(s)
end
local s=setup();attempt(s);key(s,0x4e)
check(not s.notifications:view().visible);eq(#s.patrolEvents.attempts,1);check(not s.workspace.studio.patrolEventForm)
s=setup();s.physicalDown={[0x59]=true};attempt(s);s.step(200);check(not s.workspace.studio.patrolEventForm)
key(s,0x59);local st=s.workspace.studio;check(st.patrolEventForm);eq(st.patrolEventForm.kind,'detention')
check(not st.patrolEventForm.acknowledged);eq(st.patrolEventForm.target,nil,'No unverified command argument parser')
click(s,'Связать с Player_Name [37]##patrol-event-bind-target');eq(st.patrolEventForm.target.id,37)
-- Buttons work through Alt; drawing enqueues a click, never opens/sends itself.
s=setup('buttons');attempt(s);s.physicalDown={[0x12]=true};s.step(150)
local b=s.notifications.buttons.yes;check(b)
s.io.MousePos={x=b.x+b.w/2,y=b.y+b.h/2};s.step(150)
s.mouseClicks={[0]=true};s.render();check(not s.workspace.studio.patrolEventForm);s.mouseClicks={};s.step()
check(s.workspace.studio.patrolEventForm);healthy(s)
-- A critical Y/N takes priority and does not use the event toast's answer.
s=setup();attempt(s);local remaining=s.patrolEvents.attempts[1].notice_remaining
s.commands.pa26sos();s.step();check(s.alerts.pending);check(not s.notifications:view().visible)
s.step(1000);eq(s.patrolEvents.attempts[1].notice_remaining,remaining)
key(s,0x4e);check(not s.alerts.pending);check(not s.workspace.studio.patrolEventForm);healthy(s)
-- Existing form answers survive accepting another command reminder.
s=setup();s.commands.pa26();s.step();s.page('partners');click(s,'События##Напарники и служба##partners-pageevents')
st=s.workspace.studio;st.patrolEventKind='custom';s.render();click(s,'Подготовить событие##patrol-event-new')
s.edits={['##Дополнительные сведения##patrol-event-details']='Не терять эту запись'};s.render();s.edits={};local old=st.patrolEventForm
s.commands.pa26();s.step();attempt(s);key(s,0x59);eq(st.patrolEventForm,old,'Existing form object is retained');eq(old.details,'Не терять эту запись','Existing typed answers survive')
-- Settings persist from GUI and info tooltips stay readable independently.
s=setup();s.commands.pa26();s.step();s.page('partners');click(s,'События##Напарники и служба##partners-pageevents')
click(s,'Настройки##События##patrol-event-pagesettings')
s.edits={['##Вопрос после команды##patrol-event-toast_template']='Проверить {event}?\nКоманда: {command}',
    ['##Заголовок уведомления##patrol-event-toast_title']='Проверка события'};s.render();s.edits={}
s.intEdits={['Сколько показывать уведомление, с##patrol-event-toast-duration']=15};s.render();s.intEdits={};s.step(700)
eq(s.workspace.library.patrol_events.toast_ms,15000)
local saved=s.savedLibrary()
eq(saved.patrol_events.toast_title,'Проверка события');eq(saved.patrol_events.toast_ms,15000)
s.hover='##settings-info-patrol-event-toast';s.render();healthy(s);s.hover=nil
for _,width in ipairs({760,1000,1600})do s.io.DisplaySize.x=width;s.io.DisplaySize.y=900;s.render();healthy(s)end
