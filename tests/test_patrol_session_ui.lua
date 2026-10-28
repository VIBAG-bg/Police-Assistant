local fixture=require 'support.fixture'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local function healthy(s)
    check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(s.invalidIOReads,0)
end
local function click(s,label)s.click=label;s.render();eq(s.click,nil,'Not visible: '..label);healthy(s)end
local function setup(demo)
    local lib=model.defaults(core.defaults());lib.patrol_session.enabled=true;lib.patrol_session.unit='A-1'
    -- Existing queue assertions use a one-line user template. The urgent suite
    -- separately covers the new default and its multi-part radio delivery.
    for key,text in pairs({start='{local_tag}{unit}: начинаю патрулирование. Экипаж: {crew}. 10-20: {area}.',resume='{local_tag}{unit}: продолжаю патрулирование. Экипаж: {crew}. 10-20: {area}.',periodic='{local_tag}{unit}: продолжаю службу. Экипаж: {crew}. 10-20: {area}.',finish='{local_tag}{unit}: патрулирование завершено. Время на службе: {duration}.'})do lib.patrol_session[key..'_template']=text end
    lib.patrol_session.interval_ms=60000;lib.patrol_session.confirmation=false
    lib.profile.name='Victor Auditore';lib.profile.callsign='A-1';lib.alerts.on_duty=true
    lib.alerts.patrol.enabled=true -- Old and new producers must not both run.
    local s=fixture({demo=demo==true,library=lib,alerts=true,notifications=true,categoryWheel=true})
    s.step();s.page('partners');click(s,'Патруль##Напарники и служба##partners-pagepatrol')
    return s
end
local s=setup(false);local c=s.patrolSession;check(c);check(not s.patrol.active,'No report before explicit start')
click(s,'Начать патруль##patrol-start');check(s.workspace.studio:hasModal());eq(#s.sent,0)
click(s,'НЕТ##confirm-no');check(not s.workspace.studio:hasModal());s.step();check(not c.data.active);eq(#s.sent,0)
click(s,'Начать патруль##patrol-start');click(s,'ДА##confirm-yes');eq(#s.sent,0,'GUI confirms intent, never sends')
s.step();healthy(s);check(c.data.active,c.message);eq(#s.sent,1);check(s.sent[1].line:find('/r ',1,true)==1)
s.step(1500);eq(c.data.active.report_status,'Передан клиенту');s.step();check(s.hud.patrol.visible);check(s.hud.patrol.crew)
check(s.patrol.active);eq(s.patrol.env.settings().police_interval_ms,60000)
click(s,'Пауза патруля');s.step();eq(c.data.active.status,'paused');check(not s.patrol.active);eq(#s.sent,2)
click(s,'Продолжить патруль');click(s,'НЕТ##confirm-no');s.step();eq(c.data.active.status,'paused')
click(s,'Продолжить патруль');click(s,'ДА##confirm-yes');s.step(1500);s.step(1500);eq(c.data.active.status,'active');eq(#s.sent,4)
-- Auto-send requires a painted thirty-second warning, then remains cancellable.
for _=1,31 do s.step(1000)end
check(s.radioGuard:view().visible,s.patrol.phase..' '..tostring(s.patrol.remaining));eq(#s.sent,4)
check(s.radioGuard:cancel());for _=1,40 do s.step(1000)end;eq(#s.sent,4)
-- All editable outgoing templates and behavior fields persist in personal storage.
s.edits={['##Периодический доклад##session-template-periodic']='{unit}: участок {area}.'};s.render();s.edits={};s.step(700)
eq(s.workspace.library.patrol_session.periodic_template,'{unit}: участок {area}.')
local stored=s.savedLibrary()
eq(stored.patrol_session.periodic_template,'{unit}: участок {area}.')
-- Narrow windows use wrapping and the same adaptive green/red confirmation.
for _,width in ipairs({760,1000,1600})do
    s.io.DisplaySize.x=width;s.io.DisplaySize.y=900;s.render();healthy(s)
end
click(s,'Завершить без доклада##patrol-discard');click(s,'ДА##confirm-yes');s.step()
check(not c.data.active);eq(#c.data.history,1);eq(#s.sent,4)
check(s.files['moonloader\\config\\police_assistant_2026_patrol.json'])
-- Configured key uses the same foreground form, no report shortcut bypass.
s=setup(true);s.workspace.library.patrol_session.toggle_shortcut={key=0x50,ctrl=true,alt=false,shift=false}
s.commands.pa26();s.step();s.physicalDown={[0x11]=true,[0x50]=false};s.step()
s.physicalDown[0x50]=true;s.step();healthy(s);eq(#s.sent,0)
local cat=s.runtime.env.wheelCatalog();check(cat.bySystem['patrol-open']);eq(cat.bySystem['patrol-open'].kind,'patrol')
check(require('pa26_wheel').available(cat,{kind='patrol',id='patrol-open',category='service'},true,nil))
-- Overflow from the wheel must retain system actions in its searchable list.
s=setup(true);click(s,'Начать патруль##patrol-start');click(s,'ДА##confirm-yes');s.step();s.step()
s.commands.pa26quick();s.workspace.studio.quickWheelCategory='service';s.workspace.studio.quickWheelProfile='compact';s.render()
click(s,'Завершить патруль##quick-system-patrol-finish');check(s.workspace.studio.patrolConfirm);eq(#s.sent,0)
click(s,'НЕТ##confirm-no');eq(s.patrolSession.data.active.status,'active')
-- Form previews and clicks consume the main-loop scene snapshot, not native reads.
local lib=model.defaults(core.defaults());lib.patrol_session.enabled=true
lib.profile.name='Victor Auditore';lib.patrol_session.unit='A-1';lib.alerts.on_duty=true
lib.partners={{id=1,nickname='Player_Name',callsign='A-2'}};lib.next_partner_id=2
lib.patrol_session.crew={{contact_id=1,ic_name='John Smith',role='Напарник'}}
s=fixture({demo=true,library=lib,alerts=true});s.step();s.page('partners')
click(s,'Патруль##Напарники и служба##partners-pagepatrol')
local originals,reads={},0
for _,name in ipairs({'sampGetMaxPlayerId','sampIsPlayerConnected','sampGetPlayerNickname','sampGetCharHandleBySampPlayerId'})do
    local original=_G[name];originals[name]=original
    _G[name]=function(...)reads=reads+1;return original(...)end
end
s.render();click(s,'Начать патруль##patrol-start')
check(s.workspace.studio.patrolConfirm,'Crew resolves from the cached main-loop observations')
eq(s.workspace.studio.patrolConfirm.record.crew[1].player_id,s.id)
eq(reads,0,'GUI rendering and preparation must not call native player APIs')
click(s,'НЕТ##confirm-no');for name,original in pairs(originals)do _G[name]=original end
-- Esc on the tick immediately after DA cancels the intent before a patrol starts.
s=setup(false);click(s,'Начать патруль##patrol-start');click(s,'ДА##confirm-yes')
s.step(16,{[0x1B]=true});check(not s.patrolSession.data.active);check(not s.patrolSession.intent);eq(#s.sent,0)
