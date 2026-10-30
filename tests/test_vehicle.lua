local vehicle=require 'pa26_vehicle'
local settings=require 'pa26_vehicle_settings'
local shared=require 'pa26_patrol_settings'
local names=settings.defaults().directions
for _,r in ipairs({{0,1,1},{1,1,2},{1,0,3},{1,-1,4},{0,-1,5},{-1,-1,6},{-1,0,7},{-1,1,8}})do eq(vehicle.compass(r[1],r[2],names),names[r[3]])end
check(not vehicle.compass(0,0,names));check(not vehicle.compass(0/0,1,names))
local function equal(a,b)
    if type(a)~=type(b)then return false end
    if type(a)~='table'then return a==b end
    for k,v in pairs(a)do if not equal(v,b[k])then return false end end
    for k in pairs(b)do if a[k]==nil then return false end end
    return true
end
local function setup()
    local s={now=1000,cfg=settings.defaults(),plans={},active={id=1,status='active'},
        state={session='erp',ped=1,alive=true,focused=true,paused=false,blocked=false,onDuty=true,radioEnabled=true,demo=false,
            unit='P-01',station='SFPS',crew='Victor Auditore',area='Doherty',map_square='J-6',radioText={split_enabled=true,max_lines=6,continuation='...'}},
        cars={{id=11,handle=101,model_id=411,model_name='Infernus',color1=1,color2=0,distance=8},
            {id=12,handle=102,model_id=597,model_name='PoliceCar',color1=0,color2=1,distance=4}}}
    s.cfg.enabled=true;s.cfg.megaphone_enabled=true;s.cfg.require_patrol=true;s.cfg.occupied_only=false -- Abstract cars for executor/lifecycle tests.
    local v=vehicle.new({settings=function()return s.cfg end,codec=codec,equal=equal,patrol=function()return s.active end,
        scan=function()return shared.copy(s.cars)end,resolve=function(target)for _,c in ipairs(s.cars)do if c.handle==target.handle then return shared.copy(c)end end end,
        ownCar=function()return s.own end,start=function(p)s.plans[#s.plans+1]=p;return not s.fail,'injected failure'end})
    function s.tick(dt)s.now=s.now+(dt or 300);v:tick(s.state,s.now)end
    s.tick();return v,s
end
local v,s=setup();eq(v:view().nearest.id,12);check(not v.selected);eq(#s.plans,0)
local p=assert(v:propose('traffic_stop',true));eq(p.target.id,12);eq(#s.plans,0,'Preview never sends')
check(p.prepared.line:find('провожу остановку',1,true));check(p.prepared.line:find('PoliceCar',1,true))
check(v:accept(p));eq(#s.plans,0,'Consent is queued until main')
s.tick();eq(#s.plans,1);check(v:validPlan(s.plans[1]));check(not s.plans[1].target,'A car is not a player target')
v:onExecution('completed',{plan=s.plans[1],demo=false});eq(v.phase,'10-55')
-- A closer car cannot replace the captured target; only explicit selection can.
s.cars[1].distance=1;s.tick();eq(v:view().nearest.id,11);eq(v.selected.id,12)
p=assert(v:propose('megaphone'));check(p.prepared.line:find('/m Водитель автомобиля PoliceCar, говорит SFPS',1,true)==1)
v:invalidate(12);check(not v:accept(p));check(not v.selected)
-- Same handles/models reused after stream-out do not revive consent.
s.tick();local p2=assert(v:propose('traffic_stop',true));v:invalidate(p2.target.id);s.tick();v:selectNearest();check(not v:accept(p2))
-- Frozen config/colors, expiry, scene, duty, patrol and focus boundaries.
for _,change in ipairs({'color','alias','timer','session','duty','patrol','focus'})do
    v,s=setup();p=assert(v:propose('pursuit',true))
    if change=='color'then s.cars[2].color1=3 elseif change=='alias'then s.cfg.model_aliases['597']='Новая модель'
    elseif change=='timer'then s.now=s.now+s.cfg.confirmation_ms+1 elseif change=='session'then s.state.session='other'
    elseif change=='duty'then s.state.onDuty=false elseif change=='patrol'then s.active.status='paused'else s.state.focused=false end
    s.tick();check(not v:accept(p),change);eq(#s.plans,0)
end
v,s=setup();p=assert(v:propose('traffic_stop',true));s.state.busy=true;check(v:accept(p));s.tick();eq(#s.plans,0)
s.state.busy=nil;s.tick();eq(#s.plans,1)
v:onExecution('cancelled',{plan=s.plans[1]});s.tick(5000);eq(#s.plans,1,'No retry after partial cancellation')
v,s=setup();v:selectNearest();check(v:propose('window'));s.own={handle=50,x=0,y=0,z=0};s.tick();check(not v:propose('approach'))
-- Direction follows actual movement, including reversing; stopping preserves the last course. Teleports clear it.
v,s=setup();s.own={handle=50,x=0,y=0,z=0};s.tick();eq(v:values().direction,'неизвестно')
s.own.y=3;s.tick(300);eq(v:values().direction,'Север')
s.own.y=0;s.tick(300);eq(v:values().direction,'Юг')
s.tick(300);eq(v:values().direction,'Юг')
s.own.y=500;s.tick(300);eq(v:values().direction,'неизвестно')
s.state.paused=true;s.tick();s.state.paused=false;s.tick();eq(v:values().direction,'неизвестно')
v,s=setup();local values=assert(vehicle.describe(s.cars[1],s.cfg));check(values.vehicle_color:find('Белый',1,true));check(values.vehicle_color:find('Чёрный',1,true))
s.cfg.color_aliases['1']='Белоснежный';s.cfg.model_aliases['411']='Infernus Custom';values=assert(vehicle.describe(s.cars[1],s.cfg));eq(values.model,'Infernus Custom');eq(values.color_one,'Белоснежный')
s.cars[1].color1=254;values=assert(vehicle.describe(s.cars[1],s.cfg));eq(values.color_one,s.cfg.unknown_color)
for _,field in ipairs({'radius','scan_ms','retain_distance','confirmation_ms'})do local c=settings.defaults();c[field]=-1;check(not settings.validate(c))end
local c=settings.defaults();c.model_aliases['411']='bad\n/m injected';check(not settings.validate(c));c=settings.defaults();c.traffic_stop_template='{unknown}';check(not settings.validate(c))
v,s=setup();p=assert(v:propose('traffic_stop',true));check(v:accept(p));s.state.focused=false;s.tick();s.state.focused=true;s.tick();eq(#s.plans,0,'Focus loss cannot defer old consent until return')
v,s=setup();check(v:selectCandidate(11));eq(v.selected.id,11);check(not v:selectCandidate(999));eq(v.selected.id,11)
-- Clearing and reselecting the same physical car cannot revive old consent.
p=assert(v:propose('megaphone'));v:clearTarget('Снять выбор');s.tick();check(v:selectCandidate(11));check(not v:accept(p));eq(#s.plans,0)
c=settings.defaults();c.description_template='{crew}';check(not settings.validate(c),'Description must use vehicle fields only')
v,s=setup();v:selectNearest();local base={enabled=true,session_key='1',mode='police',police_interval_ms=600000,prison_interval_ms=600000}
v.phase='10-55';check(not v:periodic(base).enabled,'A traffic stop cannot emit an ordinary patrol update')
v.phase='Преследование';local pursuit=v:periodic(base);check(pursuit.enabled);eq(pursuit.police_template,s.cfg.pursuit_periodic_template);eq(pursuit.police_interval_ms,60000)
base.enabled=false;check(not v:periodic(base).enabled,'Delegating the radio disables pursuit reports too')
base.enabled=true;v.phase=nil;eq(v:periodic(base).session_key,'1')
