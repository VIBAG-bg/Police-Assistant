local setup=require 'support.copilot_fixture'
local settings=require 'pa26_copilot_settings'
local function fill(s)
 for _=2,s.cfg.copilot.stop_warning_count do s.tick(4000);s.send('stop_order')end
end
local cp,v,s=setup()
eq(s.cfg.copilot.stop_warning_count,5)
local p=assert(cp:propose('stop_order'))
eq(cp.stopWarnings or 0,0,'A preview is not a warning')
cp.offers={p};cp:shown(p.token);check(cp:decide(p.token,false));eq(cp.stopWarnings or 0,0)
s.send('megaphone_order');eq(cp.stopWarnings or 0,0);eq(cp.phase,nil)
check(not cp:propose('stop_order'),'The regular order and 10-55 share the cooldown')
s.tick(4000);s.send('stop_order');eq(cp.stopWarnings,1);eq(cp.tireWarnings,0)
for i=1,3 do s.car.x=i*10;s.car.distance=10+i*10;s.tick(500)end
check(cp.incident.confirmedFlight);check(not s.has('pursuit'),'An observed departure before the limit is not an automatic pursuit')
check(cp:propose('pursuit'),'An officer can start a justified pursuit earlier')
for round=2,5 do
 s.tick(4000)
 s.send(round%2==0 and'megaphone_order'or'stop_order')
 eq(cp.stopWarnings,round)
 check(cp:view().stopWarningStatus:find(round..'/5',1,true))
end
check(not cp:propose('megaphone_order'));check(not cp:propose('stop_order'))
check(not s.has('pursuit'),'Require fresh motion after the fifth warning')
-- The officer can follow at a constant distance as the target leaves the stop site.
for i=1,3 do s.car.x=30+i*6;s.tick(500)end
p=assert(s.has('pursuit'));check(p.autoFlight);eq(cp.phase,'10-55')
eq(#s.plans,6,'The automatic suggestion sends nothing')
local text=table.concat(p.prepared.lines,'\n')
check(not text:find('/su ',1,true));check(not text:find('/pt ',1,true))
cp:shown(p.token);check(cp:decide(p.token,true));s.tick()
local plan=s.plans[#s.plans];check(cp:validPlan(plan))
cp:onExecution('completed',{plan=plan})
eq(cp.phase,'Преследование');eq(cp:pursuitWantedTarget().id,37);eq(cp.pinned,'pursuit_mark')
check(not s.has('fast_wanted'))
p=assert(cp:propose('pursuit_mark'));eq(#p.prepared.lines,1);eq(p.prepared.lines[1],'/pt 37')
s.person.generation=9;s.tick();check(not cp:accept(p));eq(cp.stopWarnings or 0,0,'Reused driver identity resets incident counters')

for _,kind in ipairs({'jitter','teleport','exit','streamout','cancel','session','car','driver'})do
 cp,v,s=setup();s.send('stop_order');fill(s)
 for i=1,4 do
  if kind=='jitter'then s.car.x=i*.05;s.car.distance=10+i*.05
  elseif kind=='teleport'then s.car.x=i*1000;s.car.distance=i*1000
  elseif kind=='exit'then s.car.driver_id=nil;s.car.driver_ped=nil;s.car.x=i*10
  elseif kind=='streamout'then s.car=nil
  elseif kind=='cancel'then cp:reset('cancelled');v.phase=nil
  elseif kind=='session'then s.state.session='other'
  elseif kind=='car'then s.car.id=43
  else s.car.driver_id=38;s.car.driver_ped=201;s.person.id=38;s.person.ped=201;s.person.name='Second_Driver' end
  s.tick()
 end
 check(not s.has('pursuit'),kind)
 if kind=='exit'or kind=='streamout'then check(not cp:propose('megaphone_order'),kind)end
 if kind=='car'or kind=='driver'or kind=='cancel'or kind=='session'then eq(cp.stopWarnings or 0,0,kind)end
end

-- Start counts only real handoff. Duplicate callbacks and later fragments are idempotent.
cp,v,s=setup();s.cfg.megaphone_channel='/s';s.tick()
p=assert(cp:propose('stop_order'));check(#p.prepared.lines>=2);check(p.prepared.lines[1]:match('^/s '))
check(cp:accept(p));check(not cp:accept(p));s.tick();plan=s.plans[#s.plans]
cp:onExecution('cancelled',{plan=plan});eq(cp.stopWarnings or 0,0)
cp:onExecution('completed',{plan=plan});eq(cp.stopWarnings or 0,0)
p=assert(cp:propose('stop_order'));check(cp:accept(p));s.tick();plan=s.plans[#s.plans]
cp:onExecution('sent_line',{plan=plan},plan.lines[1]);eq(cp.stopWarnings,1);eq(cp.phase,'10-55');check(cp:validPlan(plan))
cp:onExecution('sent_line',{plan=plan},plan.lines[1]);eq(cp.stopWarnings,1)
cp:onExecution('cancelled',{plan=plan});eq(cp.stopWarnings,1);check(not cp:propose('megaphone_order'))

cp,v,s=setup();s.state.demo=true;s.tick();assert(v:selectNearest());s.tick()
s.send('stop_order');eq(cp.stopWarnings or 0,0,'Demo never counts as a real warning')
cp,v,s=setup();s.state.onDuty=false;s.tick();check(not cp:propose('stop_order'));check(not cp:propose('pursuit'))
cp,v,s=setup();s.state.radioEnabled=false;s.tick();check(not cp:propose('stop_order'))

cp,v,s=setup();s.profile.name='';s.profile.rank='';s.profile.department='';s.tick()
p=assert(cp:propose('stop_order'))
check(p.prepared.lines[1]:find('Говорит полиция.',1,true))
eq(cp:previewTemplate('stop_order',s.cfg.copilot),table.concat(p.prepared.lines,'\n'))
s.state.patrolStatus='active';s.tick();eq(cp:values().patrol_return,', продолжаю патруль')
s.state.patrolStatus=nil;s.tick();eq(cp:values().patrol_return,'')
s.profile.name='Jane Doe';s.profile.rank='Сержант';s.profile.department='SFPS';s.tick()
p=assert(cp:propose('stop_order'))
check(p.prepared.lines[1]:find('Говорит Сержант SFPS Doe.',1,true))
check(cp:previewTemplate('stop_order',s.cfg.copilot)==table.concat(p.prepared.lines,'\n'))

local old=settings.defaults();old.stop_warning_version=nil;old.stop_warning_count=3
old.templates.stop_order='Моя личная фраза.'
local migrated=assert(settings.validate(old));eq(migrated.stop_warning_count,5);eq(migrated.templates.stop_order,old.templates.stop_order)
migrated.stop_warning_count=3;eq(assert(settings.validate(migrated)).stop_warning_count,3)
old.stop_warning_count=7;eq(assert(settings.validate(old)).stop_warning_count,7)
