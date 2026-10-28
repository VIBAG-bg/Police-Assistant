local vehicle=require 'pa26_vehicle'
local prefs=require 'pa26_vehicle_settings'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local function equal(a,b)
    if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
    for k,v in pairs(a)do if not equal(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local cfg=prefs.defaults();eq(#cfg.phrases,8)
for _,mutation in ipairs({'variable','channel','name','condition','count'})do
    local c=model.copy(cfg)
    if mutation=='variable'then c.phrases[1].template='{unknown}'elseif mutation=='channel'then c.phrases[1].channel='/su'
    elseif mutation=='name'then c.phrases[1].name=''elseif mutation=='condition'then c.phrases[1].condition='hidden'else c.phrases[9]={}end
    check(not prefs.validate(c),mutation)
end
cfg.enabled=true;cfg.megaphone_enabled=true;cfg.require_patrol=false;cfg.occupied_only=false -- Exercise phrase conditions independently of driver selection.
local state={session='erp',ped=1,alive=true,focused=true,paused=false,blocked=false,onDuty=true,radioEnabled=true,demo=false,station='SFPS'}
local car={id=1,handle=10,model_id=411,model_name='Infernus',color1=1,color2=0,distance=5}
local plans={};local own
local v=vehicle.new({settings=function()return cfg end,equal=equal,codec=codec,scan=function()return {model.copy(car)}end,
    resolve=function()return model.copy(car)end,ownCar=function()return own end,start=function(p)plans[#plans+1]=p;return true end})
local now=1000;local function tick()now=now+300;v:tick(state,now)end
tick();check(v:selectCandidate(1));local p=assert(v:propose('megaphone_1'));check(p.prepared.line:find('Infernus',1,true));eq(p.label,'Остановиться');eq(#plans,0)
check(v:accept(p));tick();eq(#plans,1);check(v:validPlan(plans[1]));v:onExecution('completed',{plan=plans[1],demo=false})
cfg.phrases[1].condition='pursuit';check(not v:propose('megaphone_1'));v.phase='Преследование';check(v:propose('megaphone_1'))
cfg.phrases[1].condition='stop';check(not v:propose('megaphone_1'));v.phase='10-55';check(v:propose('megaphone_1'))
cfg.phrases[1].condition='vehicle';check(not v:propose('megaphone_1'));own={handle=20,x=0,y=0};tick();check(v:propose('megaphone_1'))
cfg.phrases[1].condition='foot';check(not v:propose('megaphone_1'));own=nil;tick();p=assert(v:propose('megaphone_1'))
cfg.phrases[1].template='Изменённый текст.';check(not v:accept(p));cfg.phrases[1].enabled=false;check(not v:propose('megaphone_1'));check(not v:propose('megaphone_0'))
cfg.phrases[1].enabled=true;cfg.phrases[1].condition='any';p=assert(v:propose('megaphone_1'));car.color1=3;tick();check(not v:accept(p),'Changed vehicle description invalidates consent')
local lib=model.defaults(core.defaults());lib.vehicle.phrase_1_shortcut=model.copy(lib.vehicle.megaphone_shortcut)
check(not model.validate(lib,core.defaults()),'All phrase hotkeys participate in collision checks')
