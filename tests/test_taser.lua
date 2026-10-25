local model=require 'pa26_bindings'
local prefs=require 'pa26_preferences'
local module=require 'pa26_taser'
local ffi=require 'ffi'
local function fixture()
    local s={now=10000,cfg=prefs.taserDefaults(),plans={},state={session='test',ped=1,demo=false,weapon=23,
        alive=true,focused=true,paused=false,blocked=false,typing=false,recording=false,editingHud=false,draggingHud=false,onDuty=true}}
    local c=module.new({settings=function()return s.cfg end,codec=codec,observed=function()return s.observed~=false end,
        start=function(p)s.plans[#s.plans+1]=p;return s.accepted~=false,s.error end})
    s.cfg.activation='weapon';s.cfg.weapon_id=23 -- Explicit legacy SD-Pistol fixture; command mode is tested separately.
    function s.tick(dt)s.now=s.now+(dt or 16);c:tick(model.copy(s.state),s.now)end
    function s.shot(id)check(c:bullet({weaponId=id or 23}));s.tick()end
    function s.complete(sent)c:onExecution('completed',{plan=s.plans[#s.plans],sent=sent or 1,demo=s.state.demo})end
    s.tick(0);return c,s
end
local c,s=fixture();eq(c:view().charges,2);check(c:view().ready);s.shot();eq(c:view().charges,1)
check(not c:view().ready);eq(c:view().remaining,5000);eq(#s.plans,0)
s.tick(4999);check(not c:view().ready);s.tick(1);check(c:view().ready)
s.shot();eq(c:view().charges,0);eq(#s.plans,1);check(c.queued);check(not c:view().ready)
eq(#s.plans[1].steps,1);check(s.plans[1].lines[1]:find('картриджи',1,true));check(c:validPlan(s.plans[1]))
s.complete();eq(c:view().charges,0);eq(c:view().remaining,5000);check(not c:view().ready)
s.tick(5000);eq(c:view().charges,2);check(c:view().ready);eq(#s.plans,1)
-- Every BulletSyncData packet counts, even a miss: no hitType/target requirement.
ffi.cdef('typedef struct {unsigned char hitType; unsigned short targetId; unsigned char weaponId;} Pa26TaserTestBullet;')
c,s=fixture();local packet=ffi.new('Pa26TaserTestBullet',{hitType=0,targetId=65535,weaponId=23})
check(c:bullet(packet));s.tick();eq(c.shots,1);check(not c:bullet(nil));check(not c:bullet({weaponId=24}));check(not c:bullet({weaponId=23.5}))
-- Weapon swapping doesn't provide two free RP charges or erase cooldown.
c,s=fixture();s.shot();s.state.weapon=24;s.tick();check(not c:view().visible);eq(c.shots,1)
s.state.weapon=23;s.tick();eq(c:view().charges,1);check(c:view().remaining>0)
s.shot();check(c.violation);check(c.queued);s.complete();check(not c.violation)
-- Never interrupts binders/important cards or reloads while the taser is holstered.
for _,key in ipairs({'busy','wheel','alertPending'})do
    c,s=fixture();s.state[key]=true;s.shot();s.tick(5000);s.shot();eq(#s.plans,0,key);check(c:needsReload())
    s.state[key]=nil;s.tick();eq(#s.plans,1,key);s.tick(1000);eq(#s.plans,1)
end
c,s=fixture();s.state.busy=true;s.shot();s.tick(5000);s.shot();s.state.weapon=24;s.state.busy=nil;s.tick(6000)
eq(#s.plans,0);s.state.weapon=23;s.tick();eq(#s.plans,1)
-- Blocked input postpones the automatic narrative without losing the two shots.
for _,key in ipairs({'blocked','typing','recording','editingHud','draggingHud','paused','focused','onDuty'})do
    c,s=fixture();s.state[key]=key~='focused' and key~='onDuty';s.shot();s.tick(5000);s.shot();eq(#s.plans,0,key)
    s.state[key]=key=='focused' or key=='onDuty';s.tick();eq(#s.plans,1,key)
end
-- A failed or cancelled handoff never retries automatically, but explicit repeat works.
c,s=fixture();s.accepted=false;s.shot();s.tick(5000);s.shot();eq(#s.plans,1);s.tick(6000);eq(#s.plans,1)
check(c:view().button);s.accepted=true;c:requestReload();s.tick();eq(#s.plans,2);s.complete();check(c:view().ready)
c,s=fixture();s.shot();s.tick(5000);s.shot();c:onExecution('cancelled',{plan=s.plans[1]});s.tick(6000)
eq(#s.plans,1);check(c:view().button);c:requestReload();s.tick();eq(#s.plans,2)
-- Manual-only reload can be queued while a binder is busy, then done once free.
c,s=fixture();s.cfg.auto_reload=false;s.shot();s.tick(5000);s.shot();eq(#s.plans,0)
s.state.busy=true;c:requestReload();s.tick();eq(#s.plans,0);s.state.busy=nil;s.tick();eq(#s.plans,1)
s.cfg.auto_reload=false;check(c:validPlan(s.plans[1]));s.complete();s.tick(5000);eq(c.shots,0)
-- Safety guards invalidate a queued narrative when its weapon, life or payload changes.
for _,change in ipairs({'weapon','session','ped','demo','enabled','template','new_shot','auto_reload'})do
    c,s=fixture();s.shot();s.tick(5000);s.shot();local p=s.plans[1];check(c:validPlan(p))
    if change=='enabled' then s.cfg.enabled=false
    elseif change=='template' then s.cfg.reload_template='заменяет картридж'
    elseif change=='auto_reload' then s.cfg.auto_reload=false
    elseif change=='new_shot' then c:bullet({weaponId=23})
    elseif change=='weapon' then s.state.weapon=24
    elseif change=='session' then s.state.session='other'
    elseif change=='ped' then s.state.ped=9
    else s.state.demo=true end
    s.tick();check(not c:validPlan(p),change)
end
c,s=fixture();for i=1,40 do c:bullet({weaponId=23})end;c:reset();s.tick();eq(c.shots,0);eq(#s.plans,0,'old overflow must not survive respawn')
c,s=fixture();s.cfg.reload_template=string.rep('А',160);s.shot();s.tick(5000);s.shot();eq(#s.plans,0)
s.tick(5000);eq(#s.plans,0);check(c:view().button)
c,s=fixture();s.observed=false;check(not c:view().ready);eq(c:view().status,'События выстрелов недоступны')
c,s=fixture();check(c:bullet({weaponId=23}));s.tick(3000);eq(c.shots,1);eq(c:remaining(),5000,'a client stall cannot drop a real shot')
c,s=fixture();s.now=4294967280;c:reset();s.tick(0);check(c:bullet({weaponId=23}));s.tick(8);s.now=0;c:tick(s.state,s.now)
check(c:remaining()>4900 and c:remaining()<=5000,'timer wrap must preserve cooldown')
-- The configurable RP limit does not grant fresh charges in the middle of a cartridge.
c,s=fixture();s.shot();s.cfg.capacity=3;s.tick();eq(c:view().capacity,2);eq(c:view().charges,1);eq(c:view().pendingCapacity,3)
c:requestReload();s.tick();check(c.queued);s.complete();s.tick(5000);eq(c:view().capacity,3);eq(c:view().charges,3)
s.shot();s.tick(5000);s.shot();eq(c:view().charges,1);check(not c:needsReload());s.tick(5000);s.shot();check(c:needsReload())
for _,value in ipairs({0,11,false,1.5})do local d=prefs.taserDefaults();d.capacity=value;check(not prefs.validateTaser(d))end
-- Frame-boundary race: an early third packet cannot earn fresh RP charges.
c,s=fixture();s.shot();s.tick(5000);s.shot();s.complete();s.tick(4999)
check(c:bullet({weaponId=23}));s.tick(2);eq(c:view().charges,0);check(c:needsReload());check(c.violation)
check(not c.reloadDone);check(not c:view().ready)
