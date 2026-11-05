local C=require 'pa26_copilot';local V=require 'pa26_vehicle';local prefs=require 'pa26_vehicle_settings';local model=require 'pa26_bindings'
local function setup(kind)
 local s={now=1000,cfg=prefs.defaults(),plans={},state={session='test',ped=1,alive=true,focused=true,paused=false,blocked=false,onDuty=true,radioEnabled=true,demo=false,inVehicle=true,area='Doherty',city='Сан-Фиерро',map_square='J-6',my_nick='Demo_Officer',gameHour=12}}
 s.car={id=142,handle=100,model_id=kind,color1=0,color2=0,x=0,y=10,z=0,distance=10,driver_known=true,driver_ped=200,driver_id=37,occupants=1}
 s.person={id=37,ped=200,name='Driver_Name',generation=0,armed=false,distance=5,x=0,y=10,z=0}
 local v=V.new({settings=function()return s.cfg end,profile=function()return{name='Demo Officer',callsign='',department='EPD'}end,codec=codec,equal=require('pa26_author_presets').equal,
 scan=function()return{model.copy(s.car)}end,resolve=function()return model.copy(s.car)end,ownCar=function()return{handle=50,x=0,y=0,z=0}end,start=function()return true end})
 local cp=C.new({vehicle=v,settings=function()return s.cfg.copilot end,profile=function()return{name='Demo Officer',callsign='',department='EPD'}end,codec=codec,equal=require('pa26_author_presets').equal,
 driver=function(id)if id==37 then return model.copy(s.person)end end,start=function(p)s.plans[#s.plans+1]=p;return true end})
 function s.tick(dt)s.now=s.now+(dt or 100);v:tick(s.state,s.now);cp:tick(s.state,s.now)end
 s.tick();assert(v:selectNearest());s.tick();return s,cp
end
for _,kind in ipairs({596,522})do
 local s,c=setup(kind);local stop=assert(c:propose('stop_order'))
 local stopText=table.concat(stop.prepared.lines,'\n');check(stopText:find(kind==522 and'Водитель мотоцикла'or'к правой обочине',1,true))
 local p=assert(c:propose('risk_order'));local checkpoints,waits=0,0
 for _,step in ipairs(p.prepared.steps)do
  if step.kind=='confirm'then checkpoints=checkpoints+1;check(#step.preview>0);eq(step.timeout_ms,90000)end
  if step.kind=='wait'then waits=waits+1;eq(step.ms,kind==522 and 1400 or 1800)end
 end
 eq(checkpoints,3);eq(waits,2)
 if kind==522 then local body=table.concat(p.prepared.lines,'\n');for _,word in ipairs({'салон','дверь','багажник','окно'})do check(not body:find(word,1,true))end end
 check(c:accept(p));s.tick();local plan=s.plans[#s.plans];check(plan);check(c:validPlan(plan))
 s.state.modal=true;s.state.typing=true;s.tick();check(not c:validPlan(plan));plan.rpStageWaiting=true;check(c:validPlan(plan),'Only the executor-owned stage can wait in its own modal')
 s.car.driver_id=38;s.tick();check(not c:validPlan(plan),'Driver changes still invalidate the stage')
end
for _,kind in ipairs({481,471})do
 local s,c=setup(kind);check(not c:prepare('stop_order'))
 local choice=assert(c:propose('stop_order'));check(choice.rpVariants);check(choice.variants.car);check(choice.variants.bike)
 check(c:valid(choice.variants.bike));check(table.concat(choice.variants.bike.prepared.lines,'\n'):find('мотоцикла',1,true))
 s.car.model_id=596;s.tick(1000);check(not c:accept(choice.variants.car),'Changing the vehicle invalidates both previews')
end
local s,c=setup(596);local p=assert(c:propose('busy_report'));check(table.concat(p.prepared.lines,'\n'):find('10-8',1,true))
