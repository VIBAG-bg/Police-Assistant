local core=require 'pa26_core';local model=require 'pa26_bindings';local prefs=require 'pa26_preferences'
local module=require 'pa26_radio_guard'
local function setup(custom)
    local s={now=1000,cfg=prefs.radioGuardDefaults(),plans={},cancelled={},state={session='test',ped=1,demo=false,alive=true,
        onDuty=true,radioEnabled=true,focused=true,paused=false,blocked=false,typing=false,recording=false,area='Ganton',
        local_tag='LSPD |',my_name='Officer Name',post='Северный пост'}}
    if custom then s.cfg.custom={{id=1,name='Свой доклад',enabled=true,confirmation=false,interval_ms=60000,
        channel='/r',template='{local_tag}{my_name}: 10-20 {area}.'}};s.cfg.next_id=2 end
    local c=module.new({settings=function()return s.cfg end,codec=codec,start=function(plan)
        s.plans[#s.plans+1]=plan;return s.accepted~=false
    end,cancel=function(token)s.cancelled[#s.cancelled+1]=token end})
    function s.tick(ms,paint)
        s.now=(s.now+(ms or 1000))%4294967296;c:tick(model.copy(s.state),s.now)
        if paint~=false then for _,t in ipairs(c:candidates())do c:shown(t.token)end end
    end
    function s.advance(ms,paint)for i=1,ms/1000 do s.tick(1000,paint)end end
    s.tick(0);return c,s
end
local spec={name='Полиция',template='{local_tag}Патруль. {area}.',channel='/r',interval_ms=60000,confirmation=false}
local c,s=setup();local phase,err,t=c:track('one',spec,30000);eq(phase,'pending');eq(#s.plans,0)
s.advance(30000,false);c:track('one',spec,0);check(not c:ready('one'),'unpainted popup must not authorize auto send')
c:shown(t.token);s.advance(29000);check(not c:ready('one'));s.tick();check(c:ready('one'))
check(c:dispatch('one'));eq(#s.plans,1);check(c:validPlan(s.plans[1]));check(c:cancel(t.token));check(not c:validPlan(s.plans[1]));eq(#s.cancelled,1)
-- Once handed to the client, cancellation cannot undo or repeat it.
c,s=setup();_,_,t=c:track('one',spec,0);c:shown(t.token);s.advance(30000);check(c:dispatch('one'))
c:onExecution('sent_line',{plan=s.plans[1]});check(not c:cancel(t.token));eq(#s.plans,1)
-- A hidden full toast keeps a compact cancellable occurrence.
c,s=setup();_,_,t=c:track('one',spec,30000);c:shown(t.token);s.advance(11000)
local candidate=c:candidates()[1];check(not candidate.full);check(candidate.remaining>0);check(c:cancel(candidate.token))
eq(c:track('one',spec,19000),'cancelled');eq(#s.plans,0)
-- Another producer must not prune an unacknowledged cancellation tombstone.
c:track('two',spec,30000);eq(c:track('one',spec,0),'cancelled')
-- Pause/resume and clock stalls always get a new warning, never catch-up.
for _,key in ipairs({'focused','typing','blocked','recording','modal','alertPending'})do
    c,s=setup();_,_,t=c:track('one',spec,0);c:shown(t.token);s.advance(20000)
    s.state[key]=key~='focused';s.advance(60000);eq(t.lead,10000)
    s.state[key]=key=='focused';s.tick();eq(t.lead,30000);check(not c:ready('one'));eq(#s.plans,0)
end
c,s=setup();_,_,t=c:track('one',spec,0);c:shown(t.token);s.tick(600000,false);eq(t.lead,30000);eq(#s.plans,0)
-- Fresh dynamic location must be painted; changing identity/config cancels.
c,s=setup();_,_,t=c:track('one',spec,0);c:shown(t.token);s.advance(30000)
s.state.area='East Beach';s.tick(16,false);c:track('one',spec,0);check(not c:ready('one'))
c:shown(t.token);check(c:ready('one'));check(c:dispatch('one'));check(s.plans[1].lines[1]:find('East Beach',1,true))
s.state.area='Ganton';s.tick(16);check(not c:validPlan(s.plans[1]))
c,s=setup();_,_,t=c:track('one',spec,0);s.state.my_name='Changed';s.tick();eq(t.phase,'cancelled')
local changed=model.copy(spec);changed.channel='/d';eq(c:track('one',changed,0),'cancelled')
-- Real custom timers, cancellation, explicit confirmation, disabling and errors.
c,s=setup(true);s.advance(29000);eq(#c:candidates(),0);s.tick();check(c:candidates()[1]);eq(#s.plans,0)
s.advance(10000);check(not c:candidates()[1].full);check(c:cancel());s.tick();s.advance(59000);eq(#s.plans,0)
s.tick();eq(#s.plans,1);check(c:validPlan(s.plans[1]));c:onExecution('sent_line',{plan=s.plans[1]});s.tick();s.advance(58000);eq(#s.plans,1)
c,s=setup(true);s.advance(30000);s.cfg.custom[1].enabled=false;s.tick();eq(#c:candidates(),0);s.advance(60000);eq(#s.plans,0)
-- Profile changes and deleted producers retire their old occurrence, without
-- accumulating cancelled tombstones that could exhaust the ticket limit.
c,s=setup(true)
for i=1,22 do
    s.advance(30000);check(c:candidates()[1]);s.state.my_name='Officer '..i;s.tick()
    local count=0;for _ in pairs(c.tickets)do count=count+1 end;eq(count,0,'old custom occurrence must be retired')
end
s.advance(30000);s.cfg.custom={};s.tick();eq(next(c.tickets),nil);eq(next(c.jobs),nil);eq(#s.plans,0)
c,s=setup(true);s.cfg.custom[1].confirmation=true;s.tick();s.advance(60000)
local p=c:candidates()[1];eq(p.mode,'confirm');eq(#s.plans,0);check(c:decide(p.token,true));s.tick();eq(#s.plans,1)
c,s=setup(true);s.accepted=false;s.advance(60000);eq(#s.plans,1);s.advance(59000);eq(#s.plans,1,'failure is not auto-retried')
c,s=setup();check(not module.prepare({name='Bad',channel='/r',template='{post}'},s.state,{encode=function()error('bad codec')end},s.now,1))
s.state.post='';check(not module.prepare({name='Bad',channel='/r',template='{post}'},s.state,codec,s.now,1))
-- Genuine uint32 wrap retains elapsed time; new lives clear old occurrences.
c,s=setup();s.now=4294967280;c:reset();s.tick(0);_,_,t=c:track('wrap',spec,0);c:shown(t.token);s.tick(16);eq(t.lead,29984)
s.state.session='another';s.tick();eq(#c:candidates(),0)
-- Preference migration and key conflicts are explicit, not a library reset.
local lib=model.defaults(core.defaults());local valid,issue=model.validate(lib,core.defaults());check(valid,issue)
local bad=model.copy(lib);bad.radio_guard.lead_ms=999;check(not model.validate(bad,core.defaults()))
bad=model.copy(lib);bad.radio_guard.custom={{id=1,name='Bad',enabled=true,confirmation=false,interval_ms=60000,channel='/r',template='{closest_id}'}};bad.radio_guard.next_id=2
check(not model.validate(bad,core.defaults()))
local old=model.copy(lib);old.radio_guard=nil;old.weapon_warning=nil;old.bindings[1].shortcut={key=0x57,alt=true,ctrl=false,shift=false}
valid,issue=model.validate(old,core.defaults());check(valid,issue);eq(valid.weapon_warning.shortcut.key,0);eq(valid.bindings[1].shortcut.key,0x57)
