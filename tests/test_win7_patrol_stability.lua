-- Synthetic transient-state regressions; this does not claim a Windows 7 VM.
local core=require 'pa26_core';local model=require 'pa26_bindings'
local Settings=require 'pa26_patrol_settings';local Session=require 'pa26_patrol_session'
local prefs=require 'pa26_preferences';local equal=require('pa26_author_presets').equal
local function setup()
    local s={now=10000,cfg=Settings.defaults(),state={session='test:7777',local_nick='Officer_Name',ped=1,
        alive=true,health=100,demo=false,onDuty=true,radioEnabled=true,focused=true,paused=false,blocked=false,
        typing=false,area='Doherty',city='Сан-Фиерро',map_square='J-6',direction='Север',gender='male'},plans={},files={}}
    s.cfg.enabled=true;s.cfg.reporter_self=false
    s.env={settings=function()return s.cfg end,clientInstance='client:0001',profile=function()return{name='Officer Name',callsign='L-1'}end,
        contacts=function()return{}end,resolve=function()end,observe=function()end,equal=equal,codec=codec,
        start=function(p)s.plans[#s.plans+1]=p;return true end,
        json={encode=function(v)return TEST_JSON_ENCODE(v)end,decode=function(v)return TEST_JSON_DECODE(v)end}}
    s.env.fs={exists=function(p)return s.files[p]~=nil end,read=function(p)return s.files[p]end,
        write=function(p,v)s.files[p]=v;return true end,remove=function(p)s.files[p]=nil;return true end,
        rename=function(a,b)if not s.files[a]or s.files[b]then return nil end;s.files[b]=s.files[a];s.files[a]=nil;return true end}
    s.controller=Session.new(s.env)
    function s.tick(ms)s.now=s.now+(ms or 100);s.controller:tick(model.copy(s.state),s.now)end
    function s.start()s.tick(0);local p=assert(s.controller:propose('start'));check(s.controller:accept(p));s.tick(0)end
    s.start();return s.controller,s
end
local c,s
for _,field in ipairs({'alive','ped','session','local_nick'})do
    c,s=setup();s.tick(1000);local before=c.data.active.elapsed_ms;local old=s.state[field]
    s.state[field]=field=='alive'and false or field=='local_nick'and''or nil
    s.tick(500);check(c.data.active,field);eq(#c.data.history,0,field);check(c.suspended,field)
    s.state[field]=old;s.tick(500);check(c.data.active,field);eq(c.data.active.elapsed_ms,before,field)
    s.tick(1000);eq(c.data.active.elapsed_ms,before+1000,field)
end
-- A different live ped on the same known account is not proof of death.
c,s=setup();s.state.ped=2;s.tick(1000);check(c.data.active);eq(#c.data.history,0)
c,s=setup();s.state.demo=true;s.tick(1000);check(c.data.active);check(c.data.active.demo)
s.state.demo=false;s.tick(1000);check(c.data.active);check(not c.data.active.demo)
for _,delta in ipairs({-1,-15,-500000})do
    c,s=setup();s.tick(1000);local before=c.data.active.elapsed_ms
    s.now=s.now+delta;c:tick(s.state,s.now);check(c.data.active);eq(c.data.active.elapsed_ms,before)
    s.tick(1000);eq(c.data.active.elapsed_ms,before+1000)
end
for _,bad in ipairs({0/0,1/0,123.5,4294967296})do
    c,s=setup();local before=c.data.active.elapsed_ms;c:tick(s.state,bad)
    check(c.data.active);eq(c.data.active.elapsed_ms,before);check(c.suspended)
    s.tick(1000);check(c.data.active);eq(c.data.active.elapsed_ms,before)
end
c,s=setup();s.now=4294967280;c:tick(s.state,s.now);s.now=16;c:tick(s.state,s.now)
eq(c.data.active.elapsed_ms,32,'Actual uint32 wrap is still understood')
for _,kind in ipairs({'server','character'})do
    c,s=setup()
    if kind=='death'then s.state.health=0;s.state.alive=false
    elseif kind=='server'then s.state.session='another:7777'else s.state.local_nick='Another_Name'end
    s.tick(0);s.tick(2999);check(c.data.active,kind);s.tick(1)
    check(not c.data.active,kind);eq(#c.data.history,1);eq(c.data.history[1].status,'interrupted')
    eq(#s.plans,0,'An interruption does not send anything')
end
c,s=setup();s.state.health=0;s.state.alive=false;s.tick(0);s.tick(2000)
s.state.health=100;s.state.alive=true;s.tick(1);check(c.data.active);eq(c.interruptCandidate,nil)
s.state.health=0;s.state.alive=false;s.tick(0);s.tick(60000);check(c.data.active);eq(#c.data.history,0)
s.state.respawnConfirmed=true;s.tick(0);check(not c.data.active);eq(#c.data.history,1)
c,s=setup();s.state.session=nil;s.state.ped=nil;s.state.alive=false
for i=1,30 do s.tick(1000)end
check(c.data.active,'Unknown data holds the record; it is not fabricated proof of death');eq(c.data.active.elapsed_ms,0)

local function reload(s,key,age,paused)
    if paused then check(s.controller:pause())end
    s.env.path='patrol.json';s.controller.env.path=s.env.path;s.controller.dirty=true
    check(s.controller:save(true));s.env.clientInstance=key
    local n=Session.new(s.env);check(n.recoverable);check(not n.data.active)
    s.now=s.now+(age or 0);n:tick(s.state,s.now);return n
end
c,s=setup();s.tick(1000);local elapsed=c.data.active.elapsed_ms
local n=reload(s,'client:0001',500);check(n.data.active);check(not n.recoverable)
eq(n.data.active.elapsed_ms,elapsed);eq(#s.plans,0,'Reload never repeats start RP or an old queue')
check(n.data.active.report_status:find('не повторяются',1,true))
for _,case in ipairs({'new_process','old_record','manual_pause','disabled','no_proof','character','server'})do
    c,s=setup()
    if case=='disabled'then s.cfg.auto_resume_reload=false
    elseif case=='character'then s.state.local_nick='Other_Name'
    elseif case=='server'then s.state.session='other:7777'end
    local key=case=='new_process'and'client:0002'or case=='no_proof'and''or'client:0001'
    n=reload(s,key,case=='old_record'and 30001 or 100,case=='manual_pause')
    check(not n.data.active,case);check(n.recoverable,case);eq(#s.plans,0)
end
-- GUI policy values are validated and retained.
local cfg=Settings.defaults();cfg.interrupt_grace_ms=5000;cfg.reload_grace_ms=45000;cfg.auto_resume_reload=false
local valid=assert(Settings.validate(cfg));eq(valid.interrupt_grace_ms,5000);eq(valid.reload_grace_ms,45000);check(not valid.auto_resume_reload)
cfg.interrupt_grace_ms=0;check(not Settings.validate(cfg))

local Patrol=require 'pa26_patrol';local Guard=require 'pa26_radio_guard'
local function radioFixture(custom)
    local q={now=1000,guardCfg=prefs.radioGuardDefaults(),cfg=prefs.patrolDefaults(),plans={},state={session='test',ped=1,
        alive=true,onDuty=true,radioEnabled=true,focused=true,paused=false,demo=false,blocked=false,typing=false,
        local_nick='Officer_Name',area='Doherty',unit='1-L-1',crew_count='1',my_name='Officer Name'}}
    q.cfg.enabled=true;q.cfg.police_interval_ms=60000;q.cfg.confirmation=false
    q.cfg.police_template='{unit}: продолжаю патруль. Экипаж: {crew_count}.'
    if custom then q.guardCfg.custom={{id=1,name='Таймер',enabled=true,confirmation=false,interval_ms=60000,channel='/r',template='Доклад.'}};q.guardCfg.next_id=2 end
    q.guard=Guard.new({settings=function()return q.guardCfg end,patrol=function()return q.cfg end,codec=codec,
        start=function(p)q.plans[#q.plans+1]=p;return true end,cancel=function()end})
    q.patrol=Patrol.new({settings=function()return q.cfg end,clockPolicy=function()return q.guardCfg.count_during_input end,
        lead=function()return q.guardCfg.lead_ms end,preview=function(key,cfg,left)return q.guard:track(key,Guard.patrolSpec(cfg),left)end,
        ready=function(key)return q.guard:ready(key)end,dispatch=function(_,_,key)return q.guard:dispatch(key)end,
        drop=function(key)local t=q.guard.tickets[key];if t then q.guard:cancel(t.token);q.guard:retire(key)end end,
        retire=function(key)q.guard:retire(key)end})
    function q.tick(ms,paint)
        q.now=q.now+(ms or 1000);local state=model.copy(q.state)
        q.guard:tick(state,q.now);q.patrol:tick(state,q.now)
        if paint~=false then for _,v in ipairs(q.guard:candidates())do q.guard:shown(v.token)end end
    end
    function q.advance(seconds,paint)for i=1,seconds do q.tick(1000,paint)end end
    q.tick(0);return q
end
local q=radioFixture();q.advance(30);local ticket=q.guard:first();check(ticket);local token=ticket.token
q.state.blocked=true;q.state.typing=true;q.advance(30,false)
eq(q.patrol.remaining,0);eq(ticket.lead,0);eq(#q.plans,0);eq(ticket.token,token)
check(q.patrol:view().phase~='paused');check(q.guard:candidates()[1].status:find('закрытия',1,true))
q.state.blocked=false;q.state.typing=false;q.tick(16);eq(ticket.lead,0);q.tick(16);eq(#q.plans,1)
check(q.guard:validPlan(q.plans[1]));q.guard:onExecution('sent_line',{plan=q.plans[1]});q.tick(16);eq(q.patrol.remaining,60000)
q=radioFixture(true);q.cfg.enabled=false;q.tick(0);q.advance(30);ticket=q.guard:first();check(ticket)
q.state.blocked=true;q.state.typing=true;q.advance(30,false);eq(ticket.lead,0);eq(q.guard.jobs['custom:1'].remaining,0);eq(#q.plans,0)
q.state.blocked=false;q.state.typing=false;q.tick(16);q.tick(16);eq(#q.plans,1)
q=radioFixture();q.guardCfg.count_during_input=false;q.advance(30);ticket=q.guard:first();q.state.blocked=true;q.advance(10);eq(q.patrol.remaining,30000);eq(ticket.lead,30000)
q=radioFixture();q.advance(40);ticket=q.guard:first();eq(ticket.lead,20000);q.state.focused=false;q.advance(10);eq(ticket.lead,20000)
q.state.focused=true;q.tick(16);eq(ticket.lead,30000,'Actual Alt+Tab gets a fresh warning')
q=radioFixture();q.advance(40);ticket=q.guard:first();local left=ticket.lead;local cycle=q.patrol.cycle
q.state.unit='1-A-1';q.state.crew_count='2';q.tick(1000,false)
eq(q.patrol.cycle,cycle);eq(ticket.phase,'pending');eq(ticket.lead,left-1000)
check(ticket.plan.lines[1]:find('1-A-1',1,true));eq(ticket.paintedWire,nil,'The updated crew needs a new rendered preview')
q.guard:shown(ticket.token);check(ticket.paintedWire)
q.state.my_name='Different Profile';q.tick(1000);eq(ticket.phase,'cancelled','A profile edit still invalidates the old decision')

-- The same non-destructive retry adapter backs INI and JSON transactions.
local storage=require 'pa26_config';local library=require 'pa26_library'
eq(library.fs.rename,storage.fs.rename);eq(library.fs.remove,storage.fs.remove)
local oldRename,oldRemove=os.rename,os.remove;local attempts,deletes=0,0
os.rename=function(a,b)attempts=attempts+1;if attempts<3 then return nil,'temporarily locked',13 end;return true end
os.remove=function()deletes=deletes+1;return true end
local ok=storage.fs.rename('source','destination');os.rename=oldRename;os.remove=oldRemove
check(ok);eq(attempts,3);eq(deletes,0)
attempts,deletes=0,0
os.rename=function()attempts=attempts+1;return nil,'destination exists',17 end
os.remove=function()deletes=deletes+1;return true end
ok=storage.fs.rename('source','destination');os.rename=oldRename;os.remove=oldRemove
check(not ok);eq(attempts,3);eq(deletes,0,'An existing destination is never deleted on rename failure')
attempts=0;os.remove=function()attempts=attempts+1;if attempts<3 then return nil,'locked'end;return true end
ok=storage.fs.remove('already-verified-backup');os.remove=oldRemove;check(ok);eq(attempts,3)
check(not core.recoveryDefaults().demo_after_recovery)
local raw=core.defaults();raw.main.demo_mode=false;raw.cuff=nil
local normalized,notes=core.normalizeConfig(raw);check(#notes>0);check(not normalized.main.demo_mode);check(not normalized.cuff.enabled)
raw=core.defaults();raw.main.demo_mode=true;raw.cuff=nil
normalized=core.normalizeConfig(raw);check(normalized.main.demo_mode,'Saved demo preference remains explicit')
