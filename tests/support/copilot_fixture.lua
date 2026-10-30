-- Prepared observations + the production Vehicle/Copilot; no native game calls.
return function()
 local copy=require('pa26_bindings').copy;local V=require 'pa26_vehicle';local C=require 'pa26_copilot'
 local s={now=1000,cfg=require('pa26_vehicle_settings').defaults(),plans={},sent={},profile={name='Офицер Тест',callsign='',department='SFPS',gender='male'},
  state={session='test',ped=1,local_nick='Officer_Test',my_nick='Officer_Test',alive=true,focused=true,paused=false,blocked=false,onDuty=true,radioEnabled=true,
   demo=false,inVehicle=true,city='Сан-Фиерро',area='Doherty',map_square='J-6',gender='male',gameHour=12}}
 s.car={id=42,handle=100,model_id=560,model_name='Sultan',color1=0,color2=0,x=0,y=10,z=0,distance=10,driver_known=true,driver_ped=200,driver_id=37,occupants=1}
 s.person={id=37,ped=200,name='Driver_Name',generation=0,distance=5,x=0,y=10,z=0}
 s.own={id=10,handle=50,model_id=597,x=0,y=0,z=0}
 local v=V.new({settings=function()return s.cfg end,profile=function()return s.profile end,codec=codec,equal=require('pa26_author_presets').equal,
  scan=function()return s.car and{copy(s.car)}or{}end,resolve=function()return s.car and copy(s.car)end,
  ownCar=function()return s.state.inVehicle and copy(s.own)or nil end,start=function()return true end})
 local cp=C.new({vehicle=v,settings=function()return s.cfg.copilot end,profile=function()return s.profile end,codec=codec,
  equal=require('pa26_author_presets').equal,driver=function(id)return s.person and s.person.id==id and not s.unstreamed and copy(s.person)or nil end,
  driverAccount=function(id)return s.person and s.person.id==id and copy(s.person)or nil end,
  start=function(p)s.plans[#s.plans+1]=p;return true end})
 function s.tick(dt)s.now=s.now+(dt or 500);v:tick(s.state,s.now);cp:tick(s.state,s.now)end
 function s.has(action)for _,p in ipairs(cp.offers)do if p.action==action then return p end end end
 function s.send(action)
  local p,why=cp:propose(action);check(p,why);check(cp:accept(p));s.tick()
  local q={plan=s.plans[#s.plans],demo=s.state.demo};check(cp:validPlan(q.plan))
  for _,line in ipairs(p.prepared.lines)do s.sent[#s.sent+1]=line;cp:onExecution(s.state.demo and'preview_line'or'sent_line',q,line)end
  cp:onExecution('completed',q);s.tick();return p
 end
 s.tick();check(v:selectNearest());s.tick();return cp,v,s
end
