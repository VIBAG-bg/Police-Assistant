local events=require 'pa26_patrol_events'
local prefs=require 'pa26_patrol_event_settings'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local function equal(a,b)
    if type(a)~=type(b)then return false end
    if type(a)~='table'then return a==b end
    for k,v in pairs(a)do if not equal(v,b[k])then return false end end
    for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local function fixture()
    local s={now=1000,cfg=prefs.defaults(),target={id=4,ped=5,name='Player_Name'},stamp=1}
    s.cfg.enabled=true;s.cfg.require_patrol=false
    s.state={session='erp:7777',ped=1,alive=true,demo=false,focused=true,paused=false,blocked=false,typing=false,
        modal=false,recording=false,editingHud=false,draggingHud=false,local_nick='Officer_One',patrol_id='1'}
    local c=events.new({settings=function()return s.cfg end,patrol=function()return {id=1}end,
        target=function()return s.target end,targetStamp=function()return s.stamp end,
        validTarget=function(t)return s.target and t.id==s.target.id and t.name==s.target.name and t.ped==s.target.ped end,
        equal=equal,codec=codec,start=function()error('A reminder must never start a report')end})
    function s.tick(ms)s.now=s.now+(ms or 16);c:tick(s.state,s.now)end
    function s.fact(kind)
        local f,err=c:form(kind);check(f,err);f.subject='Человек в синей куртке';f.basis='Основание проверено';f.destination='дежурному';f.acknowledged=true
        local p,err=c:propose(f,false);check(p,err);eq(#c.followups,0,'Preparing does not commit the first fact')
        check(c:accept(p));s.tick();return c.followups[#c.followups]
    end
    s.tick();return c,s
end
for _,patch in ipairs({{followup_ms=999},{followup_ttl_ms=0},{followup_snooze_ms=300001},{followup_limit=0},
    {followup_enabled=1},{rights_reminder=''}, {followup_title='\255'},{followup_ttl_ms=60000,followup_snooze_ms=60001}})do
    local cfg=prefs.defaults();for k,v in pairs(patch)do cfg[k]=v end;check(not prefs.validate(cfg))
end
local c,s=fixture();check(c:command('/cuff 4','native',s.target));eq(#c.followups,0)
c.attempts={};local r=s.fact('detention');check(r);eq(r.kind,'rights');eq(#c.data.events,1);eq(c.data.facts.detention,1);eq(c.data.reports.detention,nil)
local v=c:candidates()[1];eq(v.mode,'action');eq(v.yes,'Готово');eq(v.no,'Позже');check(v.priority<50)
check(v.body:find('Человек в синей куртке',1,true));check(not v.body:find('Player_Name',1,true))
check(not c:decideNotice(r.token,true),'A reminder cannot be acknowledged before rendering')
s.tick(1000);eq(r.remaining,s.cfg.followup_ms)
c:shown(r.token);s.tick(1000);eq(r.remaining,s.cfg.followup_ms-1000)
c:shown(r.token);s.state.alertPending=true;s.tick(1000);eq(r.remaining,s.cfg.followup_ms-1000)
s.state.alertPending=false;s.tick();c:shown(r.token);check(c:decideNotice(r.token,false));eq(#c:candidates(),0)
check(not c:decideNotice(r.token,false),'A snoozed, hidden reminder cannot be postponed again')
s.tick(29999);eq(#c:candidates(),0);s.tick(1);eq(#c:candidates(),1)
c:shown(r.token);check(c:decideNotice(r.token,true));eq(#c.followups,0);check(not c:decideNotice(r.token,true));eq(#c.data.events,1)
for _,change in ipairs({'stamp','target','session','life','config','disable','ttl','clock'})do
    c,s=fixture();r=s.fact('jail');check(r);eq(r.kind,'clear')
    if change=='stamp'then s.stamp=s.stamp+1
    elseif change=='target'then s.target.name='Other_Player'
    elseif change=='session'then s.state.session='other:7777'
    elseif change=='life'then s.state.alive=false
    elseif change=='config'then s.cfg.followup_title='Новый заголовок'
    elseif change=='disable'then s.cfg.followup_enabled=false
    elseif change=='clock'then s.now=-100 end
    s.tick(change=='ttl'and s.cfg.followup_ttl_ms or 0);eq(#c.followups,0,change);check(not c:decideNotice(r.token,true))
end
c,s=fixture();s.state.demo=true;s.tick();eq(s.fact('detention'),nil);eq(#c.followups,0);eq(c.data.facts.detention,nil)
c,s=fixture();s.cfg.rights_reminder_enabled=false;s.tick();eq(s.fact('detention'),nil)
c,s=fixture();s.cfg.remind_clear=false;s.tick();eq(s.fact('jail'),nil)
c,s=fixture();r=s.fact('detention')
for _=1,20 do c:shown(r.token);s.tick(1000)end
eq(#c.followups,0,'Visible expiry retires, rather than repeats, the reminder');eq(#c.data.events,1)

local native=require 'support.fixture'
local seed=model.defaults(core.defaults());seed.patrol_events.enabled=true;seed.patrol_events.require_patrol=false
local f=native({library=seed,demo=false,alerts=true,notifications=true});f.step()
check(f.workspace:selectTarget({id=f.id,ped=f.mappedPed,name=f.name}));f.step()
c=f.patrolEvents;local form=assert(c:form('detention'));form.subject='Человек в куртке';form.basis='Проверенное основание';form.acknowledged=true
local p,err=c:propose(form,false);check(p,err);check(c:accept(p));f.step()
check(f.notifications.active);check(f.notifications.active.token:find('patrol-followup:',1,true));eq(#f.sent,0)
if f.frames[1].condition()then f.commands.pa26();f.step()end
f.physicalDown={[0x12]=true};f.step(150);local button=f.notifications.buttons.yes;check(button)
f.io.MousePos={x=button.x+button.w/2,y=button.y+button.h/2};f.step(150)
f.mouseClicks={[0]=true};f.render();f.mouseClicks={};f.step();eq(#c.followups,0);eq(#f.sent,0);eq(c.data.facts.detention,1)
f.physicalDown={};f.commands.pa26();f.step();f.page('partners')
local function click(label)f.click=label;f.render();eq(f.click,nil,label);check(not f.hasLog('Ошибка интерфейса'))end
click('События##Напарники и служба##partners-pageevents');click('Настройки##События##patrol-event-pagesettings')
f.edits={['##Напоминание о правах##patrol-followup-rights']='Проверить разъяснение прав.'};f.render();f.edits={}
f.intEdits={['Напомнить позже через, с##patrol-event-followup_snooze_ms']=45};f.render();f.intEdits={};f.step(700)
local saved=f.savedLibrary()
eq(saved.patrol_events.rights_reminder,'Проверить разъяснение прав.');eq(saved.patrol_events.followup_snooze_ms,45000)
eq(#f.sent,0);eq(#f.scopes,0);eq(f.invalidIOReads,0);onScriptTerminate(f.script)
return TEST_CHECKS
