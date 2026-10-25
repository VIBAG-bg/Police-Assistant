local model=require 'pa26_bindings'
local prefs=require 'pa26_preferences'
local module=require 'pa26_weapons'
local function fixture()
    local s={now=10000,cfg=prefs.weaponDefaults(),plans={},state={session='test',ped=1,demo=false,weapon=0,
        alive=true,focused=true,paused=false,blocked=false,typing=false,recording=false,editingHud=false,draggingHud=false,onDuty=true}}
    s.cfg.enabled=true
    local c=module.new({settings=function()return s.cfg end,codec=codec,start=function(p)s.plans[#s.plans+1]=p;return true end})
    function s.tick(dt)s.now=s.now+(dt or 16);c:tick(model.copy(s.state),s.now)end
    s.tick(0);return c,s
end
local c,s=fixture();s.state.weapon=23;s.tick();s.tick(4999);eq(#s.plans,0);s.tick(1);eq(#s.plans,1)
eq(#s.plans[1].steps,1);check(s.plans[1].lines[1]:find('SD Pistol',1,true));check(c:validPlan(s.plans[1]))
s.tick(10000);eq(#s.plans,1);s.state.weapon=24;s.tick();check(not c:validPlan(s.plans[1]))
c,s=fixture();s.state.weapon=23;s.tick();s.tick(3000);s.state.weapon=24;s.tick();s.tick(4999);eq(#s.plans,0)
s.state.weapon=0;s.tick();s.tick(10000);eq(#s.plans,0,'holstered candidate must never send')
for _,key in ipairs({'busy','wheel','alertPending','reloadPending'})do
    c,s=fixture();s.state.weapon=23;s.tick();s.state[key]=true;s.tick(5000);eq(#s.plans,0,key)
    s.state[key]=nil;s.tick();eq(#s.plans,1,key)
end
for _,key in ipairs({'blocked','typing','recording','editingHud','draggingHud','paused','focused','alive','onDuty'})do
    c,s=fixture();s.state.weapon=23;s.tick();s.state[key]=key~='focused' and key~='alive' and key~='onDuty';s.tick(5000)
    eq(#s.plans,0,key);s.state[key]=key=='focused' or key=='alive' or key=='onDuty';s.tick(5000);eq(#s.plans,0)
end
c,s=fixture();s.state.weapon=23;s.tick();s.state.busy=true;s.tick(16000);s.state.busy=nil;s.tick();eq(#s.plans,0)
c,s=fixture();s.state.weapon=23;s.tick();s.cfg.items['23'].template='новый текст';s.tick(5000);eq(#s.plans,0)
c,s=fixture();s.cfg.items['17'].name='Дымовая %s граната';s.cfg.items['17'].template='берёт {weapon} в руку'
s.state.weapon=17;s.tick();s.tick(5000);eq(s.plans[1].lines[1],'/me берёт Дымовая %s граната в руку')
c,s=fixture();for _,row in ipairs(prefs.weaponCatalog)do
    local item=s.cfg.items[tostring(row[1])];local line='/me '..item.template:gsub('{weapon}',function()return item.name end)
    local wire,err=require 'pa26_core'.encodeWire(line,codec);check(wire,row[1]..': '..tostring(err))
end
c,s=fixture();s.state.weapon=23;s.tick();s.tick(5000);s.state.weapon=0;s.tick();s.state.weapon=23;s.tick();s.tick(5000)
eq(#s.plans,1,'same weapon cooldown must suppress repeated draws')
s.state.weapon=0;s.tick(30000);s.state.weapon=23;s.tick();s.tick(5000);eq(#s.plans,2)
c,s=fixture();s.cfg.items['23'].template=string.rep('А',150);s.state.weapon=23;s.tick();s.tick(5000);eq(#s.plans,0)
s.tick(15000);eq(#s.plans,0,'invalid phrase never auto retries')
