local setup=require 'support.copilot_fixture';local copy=require('pa26_bindings').copy
local cp,v,s=setup();eq(cp.stopWarnings or 0,0)
local proposal=assert(cp:propose('stop_order'));eq(cp.stopWarnings or 0,0,'A preview is not a warning')
cp.offers={proposal};cp:shown(proposal.token);check(cp:decide(proposal.token,false));eq(cp.stopWarnings or 0,0)
s.send('stop_order');eq(cp.stopWarnings,1);eq(cp.tireWarnings,0);check(not cp:propose('stop_order'),'Cooldown also applies to manual repeat buttons')
for round=2,3 do s.tick(4000);s.send('stop_order');eq(cp.stopWarnings,round)end
check(cp:view().stopWarningStatus:find('3/3',1,true));eq(cp.tireWarnings,0)
for i=1,10 do s.car.x=s.car.x+1;s.car.distance=s.car.distance+1;s.tick(500)end
check(not s.has('stop_order'),'No fourth automatic suggestion');check(not s.has('pursuit'),'Three warnings are not pursuit authorization')
cp,v,s=setup();s.send('stop_order')
for i=1,3 do s.car.x=i*10;s.car.distance=10+i*10;s.tick(500)end
check(cp.incident.confirmedFlight);check(s.has('pursuit'));eq(cp.stopWarnings,1,'Flight does not require two more warnings')
eq(cp.phase,'10-55');local count=#s.plans;s.tick();eq(#s.plans,count,'Pursuit proposal never sends itself')
s.send('pursuit');local p=assert(cp:propose('fast_wanted'))
local text=table.concat(p.prepared.lines,'\n');check(text:find('/su 37 8 1',1,true));check(not text:find('/pt ',1,true))
s.send('fast_wanted');eq(cp.pinned,'pursuit_mark')
p=assert(cp:propose('pursuit_mark'));eq(#p.prepared.lines,1);eq(p.prepared.lines[1],'/pt 37')
s.person.generation=9;s.tick();check(not cp:accept(p));eq(cp.stopWarnings or 0,0,'Reused driver identity resets incident counters')
for _,kind in ipairs({'jitter','teleport','exit','streamout','cancel','session','car'})do
 cp,v,s=setup();s.send('stop_order')
 for i=1,4 do
  if kind=='jitter'then s.car.x=i*.05;s.car.distance=10+i*.05
  elseif kind=='teleport'then s.car.x=i*1000;s.car.distance=i*1000
  elseif kind=='exit'then s.car.driver_id=nil;s.car.driver_ped=nil;s.car.x=i*10
  elseif kind=='streamout'then s.car=nil
  elseif kind=='cancel'then cp:reset('cancelled');v.phase=nil
  elseif kind=='session'then s.state.session='other'
  elseif kind=='car'then s.car.id=43 end
  s.tick()
 end
 check(not s.has('pursuit'),kind)
end
-- Failed/aborted executor submissions never advance the stop counter.
cp,v,s=setup();p=assert(cp:propose('stop_order'));check(cp:accept(p));s.tick();local plan=s.plans[#s.plans]
cp:onExecution('cancelled',{plan=plan});eq(cp.stopWarnings or 0,0)
cp:onExecution('completed',{plan=plan});eq(cp.stopWarnings or 0,0)
