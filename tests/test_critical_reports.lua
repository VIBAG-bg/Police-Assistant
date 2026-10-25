local model=require 'pa26_bindings'
local alerts=require 'pa26_alerts'
local function fixture()
    local s={now=10000,cfg=model.alertDefaults(),plans={},state={session='test',ped=1,localId=0,demo=false,
        alive=true,focused=true,paused=false,blocked=false,typing=false,recording=false,editingHud=false,draggingHud=false,
        area='Ganton',local_tag='',prison_tag='',global_tag='',callsign='P-1',city='',square='',post='Северный КПП',
        my_name='Officer Name',department='LSPD',rank='Officer',health=100}}
    local c=alerts.new({settings=function()return s.cfg end,codec=codec,
        confirm=function(p)s.plans[#s.plans+1]=p;return true end})
    function s.tick(dt,keys)
        s.now=s.now+(dt or 16);if c.pending then c:paint(c.pending.token,s.now-1,{})end
        c:tick(model.copy(s.state),s.now,keys or {physical=true})
        if c.pending then c:paint(c.pending.token,s.now,keys or {})end
    end
    s.tick(0);return c,s
end
local c,s=fixture();s.cfg.auto_code0=true;c:takeDamage(245,25,24,3);s.state.health=20;s.tick()
eq(c.pending.kind,'code0');eq(#s.plans,0);s.tick(150);s.tick();s.tick(16,{physical=true,y=true});eq(#s.plans,1)
check(s.plans[1].lines[1]:find('CODE 0',1,true));check(not s.plans[1].lines[1]:find('245',1,true))
eq(#s.plans[1].lines,1);check(c:validPlan(s.plans[1]));s.state.health=60;s.tick();check(not c:validPlan(s.plans[1]))
-- Late HP updates can upgrade a shots suggestion, but never auto-send or reuse its Y.
c,s=fixture();s.cfg.auto_code0=true;c:takeDamage(245,25,24,3);s.tick();eq(c.pending.kind,'shots')
local token=c.pending.token;s.state.health=15;s.tick(100,{physical=true,y=true});eq(c.pending.kind,'code0')
check(c.pending.token~=token);eq(#s.plans,0);s.tick(150,{physical=true,y=true});eq(#s.plans,0)
s.tick();s.tick(16,{physical=true,n=true});eq(c.pending,nil);eq(#s.plans,0)
-- Low HP alone, armour damage, falls, SD pistol and stale HP never claim CODE 0.
for _,reason in ipairs({'no_damage','armour','low_before','fall','taser','late','disabled','dead','health_unknown'})do
    c,s=fixture();s.cfg.auto_code0=true
    if reason=='low_before' then s.state.health=20;s.tick()end
    if reason~='no_damage' then
        c:takeDamage(245,25,reason=='fall' and 54 or reason=='taser' and 23 or 24,3)
    end
    if reason=='disabled' then s.cfg.code0_enabled=false
    elseif reason=='armour' then s.state.health=100
    elseif reason=='health_unknown' then s.state.health=nil
    elseif reason=='dead' then s.state.alive=false;s.state.health=0
    else s.state.health=20 end
    s.tick(reason=='late' and 1200 or 16)
    check(not c.pending or c.pending.kind~='code0',reason);eq(#s.plans,0)
end
c,s=fixture();c:request('code0');s.tick();eq(c.pending,nil);s.state.health=20;c:request('code0');s.tick();check(c.pending)
s.state.alive=false;s.tick();eq(c.pending,nil)
c,s=fixture();s.cfg.shots_channel='/d';s.cfg.sos_channel='/r';s.cfg.shots_template='{callsign} · {my_name}. 10-20: {area}.'
local p=alerts.prepare('shots',s.state,s.cfg,codec,s.now,c.life);check(p);check(p.lines[1]:match('^/d '));check(p.lines[1]:find('Officer Name',1,true))
s.cfg.patrol.enabled=true;s.cfg.patrol.mode='prison';s.cfg.patrol.prison_channel='/d';s.state.prison_tag='DOC |'
p=alerts.prepare('prison',s.state,s.cfg,codec,s.now,c.life);check(p);eq(p.lines[1],'/d DOC | Продолжаю службу в охране тюрьмы. Пост: Северный КПП.')
s.state.post='';check(not alerts.prepare('prison',s.state,s.cfg,codec,s.now,c.life))
s.cfg.shots_template='{select_nick}';local ok,res=pcall(alerts.prepare,'shots',s.state,s.cfg,codec,s.now,c.life);check(ok);check(not res)
eq(model.alertDefaults().help_command,'');check(not model.alertDefaults().help_enabled)
local core=require 'pa26_core';local wheel=require 'pa26_wheel';local lib=model.defaults(core.defaults())
local route={kind='alert',category='service',id='code0'}
check(not wheel.available(wheel.build(lib,0,true,{health=100}),route,false,nil))
check(wheel.available(wheel.build(lib,0,true,{health=20}),route,false,nil))
check(not wheel.available(wheel.build(lib,0,true,{}),route,false,nil))
