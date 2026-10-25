local model=require 'pa26_bindings';local prefs=require 'pa26_preferences';local module=require 'pa26_weapon_warning'
local function setup()
    local s={now=1000,cfg=prefs.weaponWarningDefaults(),plans={},state={session='one',ped=1,demo=false,alive=true,onDuty=true,
        radioEnabled=false,focused=true,paused=false,blocked=false,typing=false,recording=false,weapon=23,targetKey='245:42:Player_Name',accent=''}}
    s.cfg.trigger='stable'
    local c=module.new({settings=function()return s.cfg end,weaponName=function(id)return id==23 and 'Тайзер'or 'M4'end,
        taserId=function()return 23 end,codec=codec,start=function(p)s.plans[#s.plans+1]=p;return s.accepted~=false end,
        cancel=function()s.cancelled=true end})
    function s.tick(ms)s.now=(s.now+(ms or 16))%4294967296;c:tick(model.copy(s.state),s.now)end
    function s.offer()s.tick(0);s.tick(5000);check(c.pending);c:shown(c.pending.token)end
    return c,s
end
local c,s=setup();s.tick(0);s.tick(4999);eq(c.pending,nil);s.tick(1);check(c.pending);eq(#s.plans,0)
local p=c.pending;check(not c:decide(p.token,true));c:shown(p.token);check(c:decide(p.token,true));eq(#s.plans,0)
s.state.busy='Miranda';s.tick();eq(#s.plans,0);s.state.busy=nil;s.tick();eq(#s.plans,1);check(c:validPlan(s.plans[1]))
c:onExecution('sent_line',{plan=s.plans[1]});eq(c.pending,nil);s.state.weapon=31;s.tick();s.state.weapon=23;s.tick();s.tick(5000);eq(c.pending,nil,'same scene already warned')
c:request();s.tick();check(c.pending,'explicit request can remind again');eq(#s.plans,1)
-- N, timeout and a stale token produce no speech.
c,s=setup();s.offer();p=c.pending;check(c:decide(p.token,false));s.tick(1000);eq(#s.plans,0)
c:request();s.tick();local nextP=c.pending;check(nextP.token~=p.token);check(not c:decide(p.token,true));eq(nextP.phase,'offered')
c:shown(nextP.token);s.tick(5000);s.tick(5000);eq(c.pending,nil);eq(#s.plans,0)
-- Accepted speech is cancelled by changed weapon, selected actor, life or input.
for _,key in ipairs({'weapon','targetKey','session','demo','alive','typing','focused','alertPending','modal'})do
    c,s=setup();s.offer();p=c.pending;check(c:decide(p.token,true));s.state.busy='binder';s.tick()
    if key=='weapon'then s.state.weapon=31 elseif key=='targetKey'then s.state.targetKey='other' elseif key=='session'then s.state.session='other'
    elseif key=='demo'then s.state.demo=true elseif key=='alive'then s.state.alive=false elseif key=='focused'then s.state.focused=false else s.state[key]=true end
    s.tick();eq(c.pending,nil,key);eq(#s.plans,0)
end
-- Cancel stays available while waiting and after the shared queue starts.
c,s=setup();s.offer();p=c.pending;c:decide(p.token,true);s.state.busy='binder';s.tick();check(c:decide(p.token,false));eq(#s.plans,0)
c,s=setup();s.offer();p=c.pending;c:decide(p.token,true);s.tick();check(c:decide(p.token,false));check(s.cancelled);check(not c:validPlan(s.plans[1]))
c,s=setup();s.offer();p=c.pending;c:decide(p.token,true);s.state.busy='binder';s.tick(5000);s.tick(5000);s.tick(5000);s.tick(5000);s.tick(1);eq(c.pending,nil);eq(#s.plans,0)
-- Independent from drawing RP; optional draw trigger follows an actual event.
c,s=setup();s.cfg.trigger='draw';s.tick(0);s.tick(5000);eq(c.pending,nil);c:drawn(23);s.tick();check(c.pending)
c,s=setup();s.cfg.trigger='draw';s.tick(0);c:drawn(23);s.tick(6000);eq(c.pending,nil,'stale draw cannot reopen a prompt')
-- Alias, shout/plain speech, accent and CP1251 are frozen and validated.
c,s=setup();s.cfg.taser_template='Предупреждение: {weapon}.';s.state.accent='[Русский акцент]:';s.offer()
check(c.pending.plan.lines[1]:find('/s [Русский акцент]: Предупреждение: Тайзер.',1,true));check(#c.pending.plan.wire[1]<=127)
s.cfg.channel='';s.tick();eq(c.pending,nil);c:request();s.tick();check(c.pending.plan.lines[1]:match('^%['))
c,s=setup();s.cfg.taser_template=string.rep('я',200);s.tick(0);s.tick(5000);eq(c.pending,nil);eq(#s.plans,0)
c,s=setup();s.cfg.items['23']=false;s.tick(0);s.tick(5000);eq(c.pending,nil)
c,s=setup();s.offer();s.cfg.enabled=false;s.tick();eq(c.pending,nil);s.cfg.enabled=true;s.tick();s.tick(5000);eq(#s.plans,0)
-- Distinct actors can get distinct reminders; a re-used stale plan cannot speak.
c,s=setup();s.offer();p=c.pending;c:decide(p.token,true);s.tick();s.state.targetKey='246:99:Another';s.tick();check(not c:validPlan(s.plans[1]))
