local model=require 'pa26_bindings'
local core=require 'pa26_core'
local module=require 'pa26_alerts'
local cfg=model.alertDefaults()
local function fixture()
    local s={now=10000,cfg=model.alertDefaults(),confirmed={},state={session='test:7777',ped=1,localId=0,demo=false,
        alive=true,focused=true,paused=false,blocked=false,typing=false,recording=false,editingHud=false,
        draggingHud=false,window=false,area='Ganton',local_tag='',callsign='',city='',square='',mouseAllowed=false}}
    local c=module.new({settings=function()return s.cfg end,codec=codec,
        confirm=function(plan,interrupt)s.confirmed[#s.confirmed+1]={plan=plan,interrupt=interrupt};return true end})
    s.controller=c;c:tick(s.state,s.now,{})
    function s.step(dt,keys,paint)
        s.now=s.now+(dt or 16)
        if paint~=false and c.pending then c:paint(c.pending.token,s.now-1,keys or {}) end
        local consumed=c:tick(model.copy(s.state),s.now,keys or {})
        if paint~=false and c.pending then c:paint(c.pending.token,s.now,keys or {}) end
        return consumed
    end
    function s.offer(kind)
        c:request(kind or 'shots');s.step();check(c.pending);s.step(150);s.step();check(c.armed)
    end
    return c,s
end
local old=model.defaults(core.defaults());old.alerts=nil;local migrated=model.validate(old,core.defaults())
check(migrated);eq(migrated.alerts.channel,'/r');check(migrated.alerts.auto_shots);check(not migrated.alerts.include_sd)
for _,change in ipairs({{'channel','/rn'},{'enabled',1},{'cooldown_ms',0},{'timeout_ms',0/0},
    {'shots_template','/r dangerous'},{'sos_template','@cancel'},{'sos_template','Hello\n/r injected'},
    {'shots_template','{select_id}'},{'shots_template','{bad}'}}) do
    local bad=model.copy(cfg);bad[change[1]]=change[2];check(not model.validateAlerts(bad))
end
-- Weapon/reason filtering, invalid values, self/environment and no accusation.
for _,weapon in ipairs({0,1,3,16,18,19,21,23,35,36,37,39,41,42,46,49,50,51,53,54,255,-1,24.5,0/0}) do
    local c,s=fixture();check(not c:takeDamage(245,20,weapon,3));s.step();eq(c.pending,nil)
end
for _,weapon in ipairs({22,24,25,26,27,28,29,30,31,32,33,34,38}) do
    local c,s=fixture();check(c:takeDamage(245,20,weapon,3));s.step();check(c.pending)
    check(c.pending.plan.lines[1]:find('Shots fired',1,true));check(not c.pending.plan.lines[1]:find('245',1,true))
end
for _,fields in ipairs({{65535,20,24,3},{0,20,24,3},{245,0,24,3},{245,-1,24,3},{245,math.huge,24,3},
    {245,20,24,0},{245,20,24,10},{245,20,24,3.5},{'245',20,24,3}}) do
    local c,s=fixture();check(not c:takeDamage(unpack(fields)));s.step();eq(c.pending,nil)
end
local c,s=fixture();s.cfg.include_sd=true;check(c:takeDamage(245,20,23,3));s.step();check(c.pending)
for _,key in ipairs({'enabled','on_duty','auto_shots'}) do
    c,s=fixture();s.cfg[key]=false;check(not c:takeDamage(245,20,24,3));s.step();eq(c.pending,nil)
end
c,s=fixture();s.state.inReport=true;s.step();check(not c:takeDamage(245,20,24,3))
-- Coalesce a burst without prolonging the confirmation; no stored attacker.
c,s=fixture();for i=1,25 do check(c:takeDamage(245,20,24,3)) end;s.step()
eq(c.pending.hits,25);local original=c.pending.offeredAt;local token=c.pending.token
for i=1,20 do c:takeDamage(111,10,31,3) end;s.step(100)
eq(c.pending.hits,45);eq(c.pending.offeredAt,original);eq(c.pending.token,token);eq(#s.confirmed,0)
-- No paint, stale paint, held Y, simultaneous keys and modifiers never accept.
c,s=fixture();c:request('sos');s.step(16,{y=true},false);s.step(150,{y=true},false);eq(#s.confirmed,0)
s.step(16,{y=true});s.step(150,{y=true});eq(#s.confirmed,0)
s.step(16,{});s.step(16,{y=true});eq(#s.confirmed,1);eq(#s.confirmed[1].plan.lines,1)
eq(s.confirmed[1].plan.lines[1],'/r 10-70. Требуется поддержка. 10-20: Ganton.')
check(not s.confirmed[1].plan.requirements.target);eq(s.confirmed[1].plan.target,nil)
s.step(16,{y=true});s.step(16,{});s.step(16,{y=true});eq(#s.confirmed,1)
c,s=fixture();s.offer();s.step(16,{y=true,n=true});eq(#s.confirmed,0);s.step(16,{y=true});eq(#s.confirmed,0)
s.step(16,{});s.step(16,{y=true});eq(#s.confirmed,1)
for _,field in ipairs({'typing','blocked','recording','editingHud','draggingHud'}) do
    c,s=fixture();s.offer();s.state[field]=true;s.step(16,{y=true});eq(#s.confirmed,0)
    s.state[field]=false;s.step(16,{y=true});eq(#s.confirmed,0)
    s.step(16,{});s.step(16,{y=true});eq(#s.confirmed,1,field)
end
c,s=fixture();s.offer();s.step(16,{y=true,mods=true});s.step(16,{y=true});eq(#s.confirmed,0)
s.step(16,{});s.step(16,{y=true});eq(#s.confirmed,1)
c,s=fixture();s.offer();s.step(500,{},false);s.step(16,{y=true},false);eq(#s.confirmed,0)
-- Negative choice and timeout suppress the next automatic burst for 30 seconds.
c,s=fixture();s.offer();s.step(16,{n=true});eq(c.pending,nil);eq(#s.confirmed,0)
c:takeDamage(245,20,24,3);s.step();eq(c.pending,nil);s.step(30000)
c:takeDamage(245,20,24,3);s.step();check(c.pending)
c,s=fixture();s.offer();s.step(15000);eq(c.pending,nil);eq(#s.confirmed,0)
c:takeDamage(245,20,24,3);s.step();eq(c.pending,nil)
-- New session/life, focus, pause, demo change, stale events and clock reset.
for _,spec in ipairs({{'session','other'},{'ped',2},{'alive',false},{'focused',false},{'paused',true},{'demo',true}}) do
    c,s=fixture();s.offer();s.state[spec[1]]=spec[2];s.step(16,{y=true});eq(c.pending,nil);eq(#s.confirmed,0)
end
c,s=fixture();c:takeDamage(245,20,24,3);s.step(300);eq(c.pending,nil)
c,s=fixture();s.offer();c:invalidateLife();s.step(16,{y=true});eq(c.pending,nil);eq(#s.confirmed,0)
c,s=fixture();s.offer();s.now=0;s.step(16,{y=true});eq(c.pending,nil);eq(#s.confirmed,0)
c,s=fixture();c:request('sos');s.step();s.now=4294967280;c:invalidateLife();c:tick(s.state,s.now,{})
c:request('shots');s.step(8);check(c.pending);s.now=0;c:paint(c.pending.token,0,{});c:tick(s.state,0,{});check(c.pending,'normal timer wrap should survive')
-- Payload and queue changes invalidate paint and require a new released key.
for _,kind in ipairs({'area','local_tag','channel','busy'}) do
    c,s=fixture();s.offer('sos');local oldToken=c.pending.token
    if kind=='channel' then s.cfg.channel='/d'
    elseif kind=='busy' then s.state.busy='new-queue'
    else s.state[kind]=kind=='area' and 'East Beach' or 'LSPD |' end
    s.step(16,{y=true});eq(#s.confirmed,0);check(c.pending.token~=oldToken)
    s.step(150,{y=true});eq(#s.confirmed,0);s.step(16,{});s.step(16,{y=true});eq(#s.confirmed,1)
    eq(s.confirmed[1].interrupt,kind=='busy')
end
c,s=fixture();s.offer('shots');c:request('sos');s.step();eq(c.pending.kind,'sos')
c:takeDamage(245,20,24,3);s.step();eq(c.pending.kind,'sos');eq(#s.confirmed,0)
-- Mouse token is consumed only on a current, painted, active card with a cursor.
c,s=fixture();s.offer('sos');local oldToken=c.pending.token;c:click(oldToken,true);s.step();eq(#s.confirmed,0)
s.state.mouseAllowed=true;c:click(oldToken-1,true);s.step();eq(#s.confirmed,0)
c:click(oldToken,false);s.step();eq(c.pending,nil);eq(#s.confirmed,0)
-- GUI may consume game keys: use a fresh native-style IO snapshot instead.
c,s=fixture();s.state.window=true;c:request('sos');s.step(16,{});s.step(150,{});s.step(16,{})
c:paint(c.pending.token,s.now,{y=true});c:tick(s.state,s.now,{});eq(#s.confirmed,1)
-- Frozen execution guard prevents sending old coordinates after confirmation.
c,s=fixture();s.offer('sos');s.step(16,{y=true});local plan=s.confirmed[1].plan;check(c:validPlan(plan))
s.state.area='Rodeo';s.step();check(not c:validPlan(plan))
eq(cfg.help_command,'');check(not cfg.help_enabled)
c,s=fixture();local p=module.prepare('shots',s.state,cfg,codec,s.now,c.life)
check(p);eq(#p.steps,1);eq(p.wire[1],codec.encode(p.lines[1]));check(not p.lines[1]:find('10-70',1,true));check(not p.lines[1]:find('CODE 0',1,true))
s.state.local_tag=string.rep('А',200);check(not module.prepare('shots',s.state,cfg,codec,s.now,c.life),'oversized radio line must fail before any send')
