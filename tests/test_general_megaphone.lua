local model=require 'pa26_bindings'
local prefs=require 'pa26_vehicle_settings'
local vehicle=require 'pa26_vehicle'
local function equal(a,b)
    if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
    for k,v in pairs(a)do if not equal(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local function setup()
    local c=prefs.defaults();c.megaphone_enabled=true
    local s={session='server',ped=1,alive=true,focused=true,paused=false,blocked=false,onDuty=true,radioEnabled=false,demo=false,station='SFPS'}
    local car={id=7,handle=20,model_id=411,model_name='Infernus',color1=1,color2=0,distance=5}
    local ctx={cfg=c,state=s,plans={},now=1000,cars={}}
    local v=vehicle.new({settings=function()return c end,equal=equal,codec=codec,patrol=function()return ctx.patrol end,
        scan=function()return model.copy(ctx.cars)end,resolve=function()return not ctx.gone and model.copy(car)or nil end,
        ownCar=function()return ctx.own end,start=function(plan)ctx.plans[#ctx.plans+1]=plan;return true end})
    function ctx.tick(dt)ctx.now=ctx.now+(dt or 300);v:tick(s,ctx.now)end
    ctx.tick();return v,ctx,car
end
local v,s=setup();check(not s.cfg.enabled and s.cfg.require_patrol);check(not v.selected and not s.patrol)
local p=assert(v:propose('megaphone_4'));check(not p.target);eq(p.label,'Уступите дорогу');eq(#s.plans,0)
check(p.prepared.line:find('/m Говорит SFPS.',1,true)==1);check(not p.prepared.line:find('Infernus',1,true))
check(v:accept(p));eq(#s.plans,0);s.tick();eq(#s.plans,1);check(v:validPlan(s.plans[1]));check(not v.phase)
v:onExecution('completed',{plan=s.plans[1],demo=false});s.tick(5000);eq(#s.plans,1);check(not v.phase)
check(not v:propose('megaphone_1'),'A targeted phrase still needs an explicit car')
-- A general announcement is independent of the selected vehicle and its stream lifetime.
v,s=setup();s.cars={{id=7,handle=20,model_id=411,model_name='Infernus',color1=1,color2=0,distance=5}};s.tick()
check(v:selectCandidate(7));p=assert(v:propose('megaphone_4'));check(v:accept(p));v:invalidate(7);s.gone=true;s.tick()
eq(#s.plans,1);check(v:validPlan(s.plans[1]));check(not v.selected)
-- Every configured condition is evaluated again after consent.
for _,change in ipairs({'enabled','duty','radio','patrol','focus','chat','dead','session','timer','config','condition'})do
    v,s=setup();p=assert(v:propose('megaphone_4'));check(v:accept(p))
    if change=='enabled'then s.cfg.megaphone_enabled=false
    elseif change=='duty'then s.state.onDuty=false
    elseif change=='radio'then s.cfg.megaphone_require_radio=true
    elseif change=='patrol'then s.cfg.megaphone_require_patrol=true
    elseif change=='focus'then s.state.focused=false
    elseif change=='chat'then s.state.blocked=true
    elseif change=='dead'then s.state.alive=false
    elseif change=='session'then s.state.session='other'
    elseif change=='timer'then s.now=s.now+s.cfg.confirmation_ms+1
    elseif change=='config'then s.cfg.phrases[4].template='Другой текст.'
    else s.cfg.phrases[4].condition='vehicle'end
    s.tick();eq(#s.plans,0,change);check(not v:accept(p),change)
end
v,s=setup();s.cfg.megaphone_require_duty=false;s.state.onDuty=false;s.tick();check(v:propose('megaphone_4'))
s.cfg.megaphone_require_patrol=true;check(not v:propose('megaphone_4'));s.patrol={id=1,status='active'};p=assert(v:propose('megaphone_4'))
check(v:accept(p));s.patrol.status='paused';s.tick();eq(#s.plans,0)
for _,mode in ipairs({'vehicle','foot','stop','pursuit'})do
    v,s=setup();s.cfg.phrases[4].condition=mode
    if mode=='vehicle'then check(not v:propose('megaphone_4'));s.own={handle=55,x=0,y=0};s.tick()
    elseif mode=='foot'then s.own={handle=55,x=0,y=0};s.tick();check(not v:propose('megaphone_4'));s.own=nil;s.tick()
    else check(not v:propose('megaphone_4'));v.phase=mode=='stop'and'10-55'or'Преследование'end
    check(v:propose('megaphone_4'),mode)
end
-- Migration adds examples only to exact old unused slots, never to personal text.
local old=prefs.defaults();old.enabled=true
for _,key in ipairs({'megaphone_enabled','megaphone_require_patrol','megaphone_require_duty','megaphone_require_radio','megaphone_wheel'})do old[key]=nil end
for i,p0 in ipairs(old.phrases)do p0.target=nil;if i>=4 then p0.enabled=false;p0.name='Требование '..i;p0.template='Водитель автомобиля {model}, говорит {station}.'end end
old.phrases[5].template='Личный текст.';old.model_aliases['597']='Служебный автомобиль'
local migrated=assert(prefs.validate(old));check(migrated.megaphone_enabled);eq(migrated.phrases[4].target,'none');check(migrated.phrases[4].enabled)
eq(migrated.phrases[5].template,'Личный текст.');check(not migrated.phrases[5].enabled);eq(migrated.model_aliases['597'],'Служебный автомобиль')
old.enabled=false;check(not assert(prefs.validate(old)).megaphone_enabled)
for key in pairs(prefs.vehicleFields)do local c=prefs.defaults();c.phrases[4].template='Общее {'..key..'}';check(not prefs.validate(c),key)end
local c=prefs.defaults();c.phrases[4].target='hidden';check(not prefs.validate(c));c=prefs.defaults();c.megaphone_enabled=1;check(not prefs.validate(c))
