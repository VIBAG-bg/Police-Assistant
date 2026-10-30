local C=require 'pa26_copilot';local V=require 'pa26_vehicle';local settings=require 'pa26_vehicle_settings'
local model=require 'pa26_bindings';local equal=require('pa26_author_presets').equal
local function setup()
 local s={now=1000,cfg=settings.defaults(),plans={},state={session='test',ped=1,alive=true,focused=true,paused=false,blocked=false,onDuty=true,radioEnabled=true,demo=false,inVehicle=true,
  area='Doherty',city='Сан-Фиерро',map_square='J-6',my_nick='Ivan_Petrov',gameHour=12,radioText={split_enabled=true,max_lines=3,continuation='...'}}}
 s.car={id=142,handle=100,model_id=560,model_name='Sultan',color1=0,color2=0,x=0,y=10,z=0,distance=10,driver_known=true,driver_ped=200,driver_id=37,occupants=2}
 s.person={id=37,ped=200,name='Driver_Name',generation=0,armed=false,distance=5,x=0,y=10,z=0}
 local v=V.new({settings=function()return s.cfg end,profile=function()return{name='Иван Петров',callsign='',department='SFPS'}end,
  codec=codec,equal=equal,scan=function()return{model.copy(s.car)}end,resolve=function()return model.copy(s.car)end,
  ownCar=function()if s.state.inVehicle then return{handle=50,x=0,y=0,z=0}end end,start=function()return true end})
 local cp=C.new({vehicle=v,settings=function()return s.cfg.copilot end,profile=function()return{name='Иван Петров',callsign='',department='SFPS'}end,
  codec=codec,equal=equal,driver=function(id)if s.person and id==s.person.id then return model.copy(s.person)end end,
  start=function(plan)s.plans[#s.plans+1]=plan;return true end})
 function s.tick(dt)s.now=s.now+(dt or 500);v:tick(s.state,s.now);cp:tick(s.state,s.now)end
 s.tick();assert(v:selectNearest());s.tick()
 function s.send(action)
  local p,err=cp:propose(action);check(p,err);local count=#s.plans;check(cp:accept(p));eq(#s.plans,count,'UI consent only queues an intent')
  s.tick();local plan=s.plans[#s.plans];eq(#s.plans,count+1);check(cp:validPlan(plan));cp:onExecution('completed',{plan=plan,demo=s.state.demo});return plan
 end
 function s.has(action)for _,p in ipairs(cp.offers)do if p.action==action then return p end end end
 return cp,v,s
end
local cp,v,s=setup();eq(#s.plans,0);s.send('stop_order');eq(cp.phase,'10-55');check(not s.has('stop'));s.tick(1500);check(s.has('stop'))
local offered=s.has('stop');cp:shown(offered.token);check(cp:decide(offered.token,false));eq(#s.plans,1)
s.tick();check(not s.has('stop'));s.send('stop');check(cp.stopReportOffered)
s.car.driver_id=nil;s.car.driver_ped=nil;s.car.occupants=0;s.tick();check(s.has('return_car'))
local p=assert(cp:propose('return_car'));check(p.prepared.lines[1]:match('^/m '));s.state.inVehicle=false;s.tick()
p=assert(cp:propose('return_car'));check(p.prepared.lines[1]:match('^/s '))
s.person.distance=20;s.person.y=30;s.tick();check(s.has('foot'));s.person.armed=true;s.tick();check(s.has('armed'));check(not s.has('combat'))
cp:damage(37,24,s.now);s.tick();check(cp.attackConfirmed);check(s.has('combat'))
cp,v,s=setup();s.send('stop_order');s.state.inVehicle=false;s.car.distance=5;s.tick()
p=assert(cp:propose('approach'));local lines=table.concat(p.prepared.lines,'\n');check(lines:find('фары',1,true));check(lines:find('/do ',1,true));check(lines:find('/n ',1,true));check(not lines:find('фонарик',1,true))
s.state.gameHour=22;s.tick();p=assert(cp:propose('approach'));check(table.concat(p.prepared.lines,'\n'):find('фонарик',1,true))
s.cfg.copilot.window_ooc_hint=false;s.tick();p=assert(cp:propose('approach'));check(not table.concat(p.prepared.lines,'\n'):find('/n ',1,true))
cp,v,s=setup();s.send('stop_order');s.car.distance=30;s.car.x=5;s.tick();check(s.has('pursuit'))
s.send('pursuit');eq(cp.phase,'Преследование');s.tick();p=assert(s.has('fast_wanted'));cp:shown(p.token);check(cp:decide(p.token,false));eq(cp.pinned,'fast_wanted')
local fast=assert(cp:propose('fast_wanted'));local text=table.concat(fast.prepared.lines,'\n');check(text:find('/su 37 8 1',1,true));check(text:find('/pt 37',1,true));check(not fast.prepared.lines[1]:find('маск',1,true));check(not fast.prepared.lines[1]:find('SA-142',1,true))
check(cp:accept(fast));s.tick();local plan=s.plans[#s.plans];check(cp:validPlan(plan));s.person.generation=1;check(not cp:validPlan(plan),'Reused player ID must cancel even between lines')
cp,v,s=setup();s.send('pursuit');s.car.distance=20;s.tick(50);s.tick(3000);check(s.has('high_risk'))
local one;s.car.occupants=1;s.tick();one=assert(cp:propose('risk_order'));check(table.concat(one.prepared.lines,'\n'):find('три шага',1,true))
s.car.occupants=2;s.tick();p=assert(cp:propose('risk_order'));check(table.concat(p.prepared.lines,'\n'):find('ПО ОДНОМУ',1,true));check(not cp:accept(one))
cp,v,s=setup();s.send('pursuit');for i=1,5 do s.tick(5000);s.send('tire');eq(cp.tireWarnings,i)end
check(cp:view().tireStatus:find('5/5',1,true));check(not cp:propose('tire'));s.tick(5000);s.send('finish');check(not cp.phase);eq(cp.tireWarnings,0)
cp,v,s=setup();s.state.colleagues={ownCruiserRole='driver'};s.send('stop_order');s.tick(1500);check(not s.has('stop'))
s.state.colleagues.ownCruiserRole='navigator';s.tick();check(s.has('stop'))
for _,change in ipairs({'session','focus','demo','car','settings','driver'})do
 cp,v,s=setup();s.send('pursuit');p=assert(cp:propose('fast_wanted'))
 if change=='session'then s.state.session='other'elseif change=='focus'then s.state.focused=false elseif change=='demo'then s.state.demo=true elseif change=='car'then s.car.id=143 elseif change=='settings'then s.cfg.copilot.tac_channel='TAC 2'else s.person.name='Other_Name'end
 s.tick();check(not cp:accept(p),change)
end
-- A handed-off /su must never be repeated when /pt was interrupted.
cp,v,s=setup();s.send('pursuit');p=assert(cp:propose('fast_wanted'));check(cp:accept(p));s.tick();plan=s.plans[#s.plans]
cp:onExecution('sent_line',{plan=plan},'/su 37 8 1');cp:onExecution('cancelled',{plan=plan})
eq(cp.pinned,'pursuit_mark');p=assert(cp:propose('pursuit_mark'));eq(#p.prepared.lines,1);eq(p.prepared.lines[1],'/pt 37')
-- Unknown driver readings are not proof of an exit.
cp,v,s=setup();s.send('stop_order');s.car.driver_known=false;s.car.driver_id=nil;s.car.driver_ped=nil;s.car.occupants=0;s.person.distance=50;s.person.y=50;s.tick()
check(not s.has('return_car'));check(not s.has('foot'))
-- Existing patrol and megaphone access switches remain authoritative.
cp,v,s=setup();s.cfg.require_patrol=true;s.tick();check(not cp:propose('pursuit'));s.cfg.require_patrol=false;s.cfg.megaphone_enabled=false;s.tick();check(not cp:propose('stop_order'))
-- The warning after a foot pursuit is separate and disappears when armed.
cp,v,s=setup();s.send('foot');s.send('fast_wanted');s.tick();check(s.has('taser_warning'));s.person.armed=true;s.tick();check(not s.has('taser_warning'))
-- Saved /todo RP uses the same action-preserving splitter as manual chat.
cp,v,s=setup();s.send('pursuit');s.cfg.copilot.templates.wanted_rp='/todo Приметы машины переданы диспетчеру.*обращаясь по рации к диспетчеру';s.tick()
p=assert(cp:propose('fast_wanted'));check(p.prepared.lines[1]:match('^/todo '));check(p.prepared.lines[1]:find('*обращаясь по рации к диспетчеру',1,true))
-- Losing focus cancels from the controller before the executor callback. Preserve
-- the handed-off /su there too, and resume only the missing pursuit marker.
cp,v,s=setup();s.send('pursuit');p=assert(cp:propose('fast_wanted'));check(cp:accept(p));s.tick();plan=s.plans[#s.plans]
cp:onExecution('sent_line',{plan=plan},'/su 37 8 1');s.state.focused=false;s.tick()
eq(cp.pinned,'pursuit_mark');check(cp.done.fast_wanted);s.state.focused=true;s.tick()
check(not cp:propose('fast_wanted'));p=assert(cp:propose('pursuit_mark'));eq(#p.prepared.lines,1);eq(p.prepared.lines[1],'/pt 37')
s.send('pursuit_mark');s.send('pursuit');check(not cp.pinned,'Repeating a report must not repeat /su')
-- A finished incident clears detector and pursuit flags before the next stop.
cp,v,s=setup();s.send('stop_order');s.send('stop');s.send('pursuit');s.send('finish');s.tick()
check(not cp.pursuitStarted);check(not cp.stopReportOffered);s.send('stop_order');s.tick(1500);check(s.has('stop'))
check(not cp:propose('fast_wanted'),'A prior incident must not authorize wanted issuance')
cp:damage(37,24,s.now);cp:reset('new incident');check(not cp.damageMail)
