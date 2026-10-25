local module=require 'pa26_patrol_events'
local prefs=require 'pa26_patrol_event_settings'
local model=require 'pa26_bindings'
local function equal(a,b)
    if type(a)~='table'or type(b)~='table'then return a==b end
    for k,v in pairs(a)do if not equal(v,b[k])then return false end end
    for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local function fixture()
    local s={now=1000,stamp=1,cfg=prefs.defaults(),patrol={id=1},plans={},cancelled=0,target={id=4,ped=5,name='John_Smith'}}
    s.cfg.enabled=true
    s.state={session='erp:7777',local_nick='Officer_One',ped=1,alive=true,demo=false,focused=true,paused=false,
        blocked=false,typing=false,modal=false,recording=false,editingHud=false,draggingHud=false,onDuty=true,radioEnabled=true,
        unit='A-1',area='Ganton',patrol_id='1',officer='Officer One',crew='Officer One',duration='00:00:01'}
    local c
    s.env={settings=function()return s.cfg end,patrol=function()return s.patrol end,target=function()return model.copy(s.target)end,
        validTarget=function(t)return t and s.target and t.id==s.target.id and t.name==s.target.name and t.ped==s.target.ped end,
        targetStamp=function()return s.stamp end,equal=equal,codec=codec,date=function()return '15.10.2026 19:00:00'end,
        start=function(plan)check(c:validPlan(plan));if s.error then return nil,s.error end;s.plans[#s.plans+1]=plan;return true end,
        cancel=function()s.cancelled=s.cancelled+1;c:onExecution('cancelled',{plan=s.plans[#s.plans]})end}
    c=module.new(s.env)
    function s.tick(ms)s.now=s.now+(ms or 1000);c:tick(s.state,s.now)end
    function s.form(kind,attempt)
        local f,err=c:form(kind or 'detention',attempt);check(f,err)
        f.subject='John Smith';f.basis='УК, проверенное основание';f.destination='дежурному';f.details='Проверка закончена';f.acknowledged=true
        return f
    end
    function s.offer(f,report)local p,err=c:propose(f,report);check(p,err);return p end
    function s.commit(f,report)local p=s.offer(f,report);check(c:accept(p));s.tick(0);return s.plans[#s.plans],p end
    function s.sent(plan)c:onExecution(s.state.demo and 'preview_line'or 'sent_line',{plan=plan or s.plans[#s.plans],demo=s.state.demo})end
    s.tick(0);return c,s
end
-- Preferences are optional, bounded, editable and never accept an extra command.
check(not prefs.validate(false));local p=prefs.defaults();p.events.frisk.command='/frisk';check(not prefs.validate(p))
p=prefs.defaults();p.events.frisk.template='/frisk 3';check(not prefs.validate(p))
p=prefs.defaults();p.events.frisk.template='{nickname_is_identity}';check(not prefs.validate(p))
p=prefs.defaults();p.events.frisk.command='pa26restart';check(not prefs.validate(p))
p=prefs.defaults();p.attempt_ttl_ms=1;check(not prefs.validate(p))
check(prefs.validate(nil));check(module.validate(module.defaults()))
local c,s=fixture()
check(c:command('/cuff 4','native',s.target));eq(#c.attempts,1);eq(#c.data.events,0);eq(#s.plans,0);eq(c.data.facts.detention,nil)
check(not c:command('/r /cuff 4'));check(not c:command(' /cuff 4'));check(not c:command('/cuffevil 4'));check(not c:command('/cuff 4\n/r spam'))
check(not c:command('/cuff-evil 4'));check(not c:command('/cuff; /r spam'))
local f=s.form('detention',c.attempts[1].id);check(not f.target or f.target.name=='John_Smith')
f.acknowledged=false;check(not c:propose(f,true));f.acknowledged=true
p=s.offer(f,true);eq(#s.plans,0);eq(#c.data.events,0)
check(c:accept(p));check(not c:accept(p));eq(#s.plans,0)
s.tick(0);eq(#c.data.events,1);eq(c.data.facts.detention,1);eq(c.data.reports.detention,nil);eq(c.data.events[1].source,'manual')
eq(#s.plans,1);eq(c.data.events[1].report_status,'pending');check(not c:accept(p),'No repeat of one confirmed event')
s.sent();eq(c.data.reports.detention,1);eq(c.data.facts.detention,1);eq(c.data.events[1].report_status,'client')
s.sent();eq(c.data.reports.detention,1,'Duplicate executor callback cannot increment radio count')
s.tick();eq(#c.attempts,0);check(not c:propose(f,false),'Old form cannot create a second fact')
f=s.form();check(not c:propose(f,false),'Matching fact is protected from double counting')
s.tick(5000);s.commit(f,false);eq(#s.plans,1);eq(c.data.facts.detention,2);eq(c.data.events[2].report_status,'local')
-- Local confirmation remains a fact if radio fails or is cancelled.
c,s=fixture();s.error='queue error';s.commit(s.form(),true);eq(c.data.facts.detention,1);eq(c.data.events[1].report_status,'cancelled');eq(c.data.reports.detention,nil)
s.tick();eq(#s.plans,0);eq(c.data.facts.detention,1)
c,s=fixture();s.state.busy='binder';s.commit(s.form(),true);eq(c.data.facts.detention,1);eq(#s.plans,0)
s.state.busy=nil;s.tick();eq(#s.plans,1);c:onExecution('cancelled',{plan=s.plans[1]});eq(c.data.events[1].report_status,'cancelled');eq(c.data.facts.detention,1)
-- A change in target, crew, area, session, duty or settings cancels the proposal.
for _,change in ipairs({'target','unit','cfg','session','patrol','alive','demo','ped'})do
    c,s=fixture();p=s.offer(s.form(),true)
    if change=='target'then s.target.name='Other_Player'
    elseif change=='cfg'then s.cfg.events.detention.template='Changed'
    elseif change=='patrol'then s.patrol.id=2
    elseif change=='alive'then s.state.alive=false
    elseif change=='demo'then s.state.demo=true
    else s.state[change]='other'end
    s.tick();check(not c:accept(p),change);eq(#s.plans,0);eq(#c.data.events,0)
end
-- Detention template does not include area; an unused area is not a context break.
c,s=fixture();s.cfg.events.detention.template='{unit}: {subject}, {area}.';p=s.offer(s.form(),true);s.state.area='Market';s.tick();check(not c:accept(p))
c,s=fixture();f=s.form();p=s.offer(f,true);s.tick(61000);check(not c:accept(p))
c,s=fixture();s.target=nil;check(not c:propose(s.form(),false))
c,s=fixture();f=s.form();s.stamp=s.stamp+1;check(not c:propose(f,false),'Same nick/ID/ped after reselection cannot revive the old form')
c,s=fixture();check(c:command('/cuff 4','binder',s.target));local attempt=c.attempts[1].id;s.stamp=s.stamp+1;check(not c:form('detention',attempt))
c,s=fixture();p=s.offer(s.form(),true);check(c:accept(p));s.stamp=s.stamp+1;s.tick();eq(#c.data.events,0);eq(#s.plans,0)
c,s=fixture();f=s.form();f.subject='';check(not c:propose(f,false));s.cfg.events.detention.template=string.rep('д',200);check(not c:propose(s.form(),true))
c,s=fixture();s.state.onDuty=false;s.tick(0);f=s.form();check(not c:propose(f,true));s.commit(f,false);eq(c.data.facts.detention,1)
c,s=fixture();s.state.demo=true;s.tick();s.commit(s.form(),true);s.sent();eq(c.data.facts.detention,nil);eq(c.data.reports.detention,nil);eq(c.data.events[1].report_status,'demo')
-- Outgoing commands are suggestions only. Own queue/native observations dedupe.
c,s=fixture();local q={demo=false,plan={steps={{kind='message',text='/frisk 4'}},target=s.target},index=1}
c:onExecution('sent_line',q);eq(#c.attempts,1);c:onExecution('sent_line',q);eq(#c.attempts,1)
check(not c:command('/frisk 4','native',s.target));eq(#c.attempts,1)
q.plan.automatic={kind='report'};q.index=2;q.plan.steps[2]={kind='message',text='/cuff 4'};c:onExecution('sent_line',q);eq(#c.attempts,1)
s.tick(300001);eq(#c.attempts,0);eq(#c.data.events,0);eq(#s.plans,0)
c,s=fixture();s.cfg.suggest_commands=false;check(not c:command('/cuff 4'))
c,s=fixture();check(c:command('/CUFF 4'));eq(#c.attempts,1)
c,s=fixture();s.cfg.events.detention.enabled=false;check(not c:command('/cuff 4'));check(not c:form('detention'))
c,s=fixture();s.patrol=nil;check(not c:form('custom'));s.cfg.require_patrol=false;f=s.form('custom');s.commit(f,false);eq(c.data.events[1].patrol_id,0)
-- Persisted pending reports turn into cancelled records; never replay on load.
c,s=fixture();s.commit(s.form('jail'),true);check(c.message:find(s.cfg.clear_reminder,1,true))
local clean=assert(module.validate(c.data));eq(clean.events[1].report_status,'cancelled');eq(clean.facts.jail,1)
local bad=model.copy(clean);bad.events[1].source='server';check(not module.validate(bad),'Unverified source cannot become server evidence')
bad=model.copy(clean);bad.facts.jail=-1;check(not module.validate(bad))
bad=model.copy(clean);bad.events[1].id=bad.next_id;check(not module.validate(bad))
-- An already recorded fact survives a lost life while its radio tail is dropped.
c,s=fixture();s.state.busy='binder';s.commit(s.form(),true);eq(c.data.facts.detention,1)
s.state.alive=false;s.tick();eq(c.data.events[1].report_status,'cancelled');eq(#s.plans,0);eq(c.data.facts.detention,1)
-- Timers wrap; unconfirmed stale attempts do not affect results.
c,s=fixture();s.now=4294967280;c:tick(s.state,s.now);check(c:command('/cuff 4'));s.now=16;c:tick(s.state,s.now);eq(#c.attempts,1);eq(#c.data.events,0)
c,s=fixture();check(c:command('/cuff 4','native',nil));f=assert(c:form('detention',c.attempts[1].id))
eq(f.target,nil,'An attempt with no captured target must not borrow a later selected player')
f.subject='Человек';f.acknowledged=true;check(not c:propose(f,false))
check(c:bindTarget(f));eq(f.target.id,s.target.id);check(f.target_manual);check(c:propose(f,false))
c,s=fixture();s.state.blocked=true;s.state.typing=true;s.tick(0)
check(c:command('/cuff 4','native',s.target),'Observe the native Enter event while the chat has not closed yet')
eq(#c:candidates(),0);eq(#c.data.events,0);check(not c:form('detention',c.attempts[1].id))
s.state.blocked=false;s.state.typing=false;s.tick(16);eq(#c:candidates(),1)
