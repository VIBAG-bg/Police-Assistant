local fixture=require 'support.fixture'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local function healthy(s)
    check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(s.invalidIOReads,0);eq(#s.sent,0)
end
local function click(s,label)s.click=label;s.render();eq(s.click,nil,'Missing control: '..label);healthy(s)end
local function setup()
    local lib=model.defaults(core.defaults());lib.patrol_events.enabled=true;lib.patrol_events.require_patrol=false
    lib.alerts.on_duty=true
    local s=fixture({demo=false,library=lib,alerts=true,notifications=true});s.step()
    check(s.workspace:selectTarget({id=s.id,ped=s.mappedPed,name=s.name}));s.step()
    s.page('addons');click(s,'Человек##toolidentity');return s
end
local s=setup();check(s.identity:view().record);eq(s.identity:view().record.passport_seen,'unknown')
s.edits={['##IC-имя и фамилия из паспорта##identity-ic_name']='John Smith',
    ['##Номер паспорта · если известен##identity-passport_number']='123456'};s.render();s.edits={};s.step()
eq(s.identity:view().record.ic_name,'John Smith');check(not s.identity:subject(s.workspace.selectedTarget,s.workspace.targets.revision))
click(s,'Да##Вы видели паспорт этого человека?##identity-passport_seenyes');s.step()
eq(s.identity:view().record.passport_seen,'yes');eq(s.identity:subject(s.workspace.selectedTarget,s.workspace.targets.revision),'John Smith')
-- No input-cache reset on every edit; the entered text remains the same owner.
local st=s.workspace.studio;local owner=st.identityOwner
s.edits={['##IC-имя и фамилия из паспорта##identity-ic_name']='John A. Smith'};s.render();s.edits={};s.step();eq(st.identityOwner,owner)
eq(s.identity:view().record.ic_name,'John A. Smith')
s.edits={['##Известные вашему персонажу приметы##identity-appearance']='Синяя куртка\nЧёрные брюки'};s.render();s.edits={};s.step()
eq(s.identity:view().record.appearance,'Синяя куртка\nЧёрные брюки')
-- Reuse in a report is explicit and carries manual source, never an automatic accusation.
s.page('partners');click(s,'События##Напарники и служба##partners-pageevents');click(s,'Подготовить событие##patrol-event-new')
eq(st.patrolEventForm.subject,'');click(s,'Подставить известное имя / приметы##patrol-event-identity')
eq(st.patrolEventForm.subject,'John A. Smith');eq(#s.patrolEvents.data.events,0)
click(s,'Открыть IC-сведения о человеке##patrol-event-identity-open');s.render();healthy(s)
-- Persistent settings; ephemeral identity facts never enter the personal library.
s.intEdits={['Срок каждой группы сведений, с##identity-expiry']=60};s.render();s.intEdits={};s.step()
eq(s.workspace.library.identity.expiry_ms,60000)
local saved=s.savedLibrary()
eq(saved.identity.expiry_ms,60000);eq(saved.identity.ic_name,nil);eq(saved.identity.passport_seen,nil)
for _,width in ipairs({760,1000,1600})do s.io.DisplaySize.x=width;s.io.DisplaySize.y=900;s.render();healthy(s)end
-- Quit/join invalidates evidence even if the rejoining player has the same nick/ID/ped.
s.events.onPlayerQuit(s.id,1);s.step();check(not s.identity:view().record)
check(s.workspace:selectTarget({id=s.id,ped=s.mappedPed,name=s.name}));s.step();eq(s.identity:view().record.passport_seen,'unknown');eq(s.identity:view().record.ic_name,'')
s.edits={['##IC-имя и фамилия из паспорта##identity-ic_name']='Reentered'};s.render();s.edits={};s.step()
click(s,'Очистить сведения о человеке##identity-clear');s.render();eq(s.identity:view().record.ic_name,'')
-- Tooltip is independent of its small information icon and closes cleanly.
s.hover='##settings-info-identity-source';s.render();healthy(s);s.hover=nil
onScriptTerminate(s.script)
local fresh=setup();eq(fresh.identity:view().record.passport_seen,'unknown');eq(fresh.identity:view().record.ic_name,'');healthy(fresh)
