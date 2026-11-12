local setup=require 'support.copilot_fixture'
local model=require 'pa26_bindings'
local function near()
 local cp,v,s=setup()
 s.send('stop_order')
 s.state.inVehicle=false;s.car.distance=3;s.person.distance=2;s.tick()
 return cp,v,s
end
local function answer(cp)
 for _,c in ipairs(cp:candidates())do if c.token:match(':answer$')then return c end end
end
local function advanceToAnswer(cp,s)
 local q=assert(cp.windowAwait)
 s.tick(q.delay-(s.now-q.at))
 return assert(answer(cp))
end
local function reason(cp,s)
 local nav=assert(cp:propose('explain_stop'));check(nav.navigation)
 local cfg=model.copy(s.cfg.copilot);cfg.stop_ground='wrong_way'
 local ground=assert(require('pa26_operational').ground('stop',cfg.stop_ground))
 return assert(cp:proposeGround(nav,cfg,ground))
end

local cp,v,s=setup();s.send('stop_order');s.tick(2000);s.send('stop')
for _=1,10 do s.car.x=s.car.x+.4;s.tick()end
check(cp.done.stop);check(cp.stopReportOffered);check(not s.has('stop'),'Jitter cannot repeat a completed stop report')
cp,v,s=setup();s.send('stop_order')
check(not cp:observeManualCommand('/r Ранее была 10-55.','native'))
check(not cp:observeManualCommand('/f 10-99, 10-55 завершена.','native'))
check(cp:observeManualCommand('/f 2-L-1, провожу остановку, 10-55.','native'))
check(cp.done.stop);check(not s.has('stop'))
check(not cp:observeManualCommand('/ud 37','native'),'Inside the cruiser is not contact')

for _,source in ipairs({'native','cef','executor'})do
 cp,v,s=near()
 check(not cp:observeManualCommand('/udfoo 37',source));check(not cp:observeManualCommand('/ud 38',source))
 check(not cp:observeManualCommand('/ud',source))
 check(cp:observeManualCommand('/UD 37',source));check(cp.incident.introduced)
 s.state.inVehicle=true;s.tick();check(not s.has('finish'),'Showing a badge cannot offer 10-99')
 s.state.inVehicle=false;s.tick()
 check(s.has('documents'));check(not s.has('greet_stop'));check(not s.has('approach'))
 local p=s.send('documents');local text=table.concat(p.prepared.lines,' ')
 check(text:find('паспорт и лицензии',1,true));check(not text:find('/ud ',1,true))
 check(s.has('explain_stop'));check(not s.has('finish'))
 p=reason(cp,s);text=table.concat(p.prepared.lines,' ')
 check(not text:find('/ud ',1,true));check(not text:find('Предъявите',1,true))
 s.run(p);check(cp.incident.reasonExplained);check(not s.has('finish'),'While still talking, do not interrupt')
 s.state.inVehicle=true;s.tick()
 local finish=assert(s.has('finish'))
 cp:shown(finish.token);check(cp:decide(finish.token,false));s.tick()
 check(not s.has('finish'),'Do not nag after a decline')
end

-- Requesting documents is not checking them. Officer movement is needed for the other branch.
cp,v,s=near();s.send('documents')
s.person.distance=12;s.car.distance=12;s.position.x=12;s.tick()
check(not s.has('finish'),'Requesting documents alone is not a completed stop')
s.person.distance=2;s.car.distance=3;s.position.x=0;s.tick()
check(cp:markStopContact('documentsChecked'));check(not s.has('finish'))
s.person.distance=12;s.car.distance=12;s.tick()
check(not s.has('finish'),'Distance increased while the officer stayed at the same point')
s.position.x=12;s.tick();check(s.has('finish'),'Officer moved away after checking documents')

-- No then Yes: exact boundaries, held offers and the same driver. No automatic dispatch.
cp,v,s=near();s.person.distance=5;s.tick();s.send('approach')
check(not s.has('greet_stop'));check(not s.has('window_question'),'Inspection alone is not window proximity')
s.person.distance=2;s.tick();check(s.has('window_question'))
check(not cp:windowAnswer('open'));s.send('window_question')
local q=assert(cp.windowAwait)
check(not cp:windowAnswer('open'))
s.tick(4999-(s.now-q.at));check(not answer(cp))
s.tick(1);local prompt=assert(answer(cp))
eq(prompt.duration,60000);eq(prompt.remaining,60000);eq(prompt.title,'Игрок сказал, что окно открыто?')
check(not cp:decide(prompt.token,true),'Must actually be shown before accepting the popup')
local sent=#s.sent
cp:shown(prompt.token);check(cp:decide(prompt.token,false));s.tick()
eq(#s.sent,sent);eq(cp.windowReply,'closed');check(s.has('window_knock'));check(not s.has('greet_stop'))
s.send('window_knock');check(s.has('window_question'));check(not s.has('greet_stop'),'A knock does not prove the window opened')
s.send('window_question');prompt=advanceToAnswer(cp,s)
cp:shown(prompt.token);s.tick(59999);eq(assert(answer(cp)).remaining,1)
check(cp:decide(prompt.token,true));s.tick()
check(s.has('greet_stop'));check(not s.has('window_knock'));check(not cp:decide(prompt.token,false))
local greet=s.send('greet_stop')
eq(greet.prepared.lines[#greet.prepared.lines],'/ud 37')
check(cp.incident.introduced);check(not cp:propose('greet_stop'))
check(s.has('documents'));check(not s.has('finish'))

cp,v,s=near();s.send('approach');s.send('window_question')
prompt=advanceToAnswer(cp,s);cp:shown(prompt.token);s.tick(60000)
check(not answer(cp));check(not cp:decide(prompt.token,true));check(not s.has('window_question'),'An expired question is not automatically repeated')
check(not s.has('greet_stop'));check(cp:propose('window_question'),'Manual retry is available')

-- The dialog never consumes input from chat, a wheel, or a different driver.
for _,field in ipairs({'typing','ownUi','modal','wheel','busy'})do
 cp,v,s=near();s.send('approach');s.send('window_question')
 s.state[field]=true
 q=cp.windowAwait;s.tick(5000-(s.now-q.at))
 check(not answer(cp),field)
 s.state[field]=false;s.tick();prompt=assert(answer(cp))
 eq(prompt.remaining,60000)
end
cp,v,s=near();s.send('approach');s.send('window_question')
prompt=advanceToAnswer(cp,s);cp:shown(prompt.token)
s.person.generation=2;s.tick();check(not cp:decide(prompt.token,true));check(not cp.windowAwait)
cp,v,s=near();s.send('approach');s.send('window_question')
prompt=advanceToAnswer(cp,s);cp:shown(prompt.token)
s.car.driver_id=nil;s.car.driver_ped=nil;s.tick()
check(not cp:decide(prompt.token,false));check(not s.has('window_knock'))
check(s.has('greet_stop'),'A nearby driver on foot can be greeted without the window workflow')

-- A14 already includes the documents request, whereas A01 ends with /ud.
for _,ref in ipairs({'A01','A02','A14'})do
 cp,v,s=near();s.send('approach');s.send('window_question')
 local fakePlan={binding={author_ref=ref},target=model.copy(s.person),lines={'Предъявите, пожалуйста, паспорт и лицензии.'}}
 if ref~='A02' then cp:onExecution('sent_line',{plan=fakePlan},'/ud 37')end
 cp:onExecution('completed',{plan=fakePlan,sent=1})
 s.tick()
 check(not cp.windowAwait);check(not s.has('greet_stop'))
 if ref=='A01' then check(s.has('documents'))
 else check(cp.incident.documentsRequested);check(s.has('explain_stop'));check(not s.has('documents'))end
end
cp,v,s=near();local wrong={binding={author_ref='A14'},target=model.copy(s.person),lines={'Предъявите паспорт и лицензии.'}}
wrong.target.generation=9;cp:onExecution('completed',{plan=wrong,sent=1})
check(not cp.incident.documentsRequested)

-- Automatic weapon observation waits for this driver's completed RP inspection.
cp,v,s=setup();s.person.armed=true;s.send('stop_order')
check(not s.has('armed'),'From inside the patrol car')
s.state.inVehicle=false;s.car.distance=20;s.person.distance=20;s.tick()
check(not s.has('armed'),'Exiting far away is not contact')
s.car.distance=3;s.person.distance=2;s.tick()
check(not s.has('armed'),'Approaching is not inspection')
check(not cp:propose('armed'),'Even the direct proposal requires an inspection')
local look=assert(cp:propose('approach'));check(cp:accept(look));s.tick()
local reportQ={plan=s.plans[#s.plans],index=1}
cp:onExecution('sent_line',reportQ,look.prepared.lines[1]);s.tick()
check(not s.has('armed'),'The first line alone is insufficient')
cp:onExecution('cancelled',reportQ);s.tick();check(not s.has('armed'))
s.send('approach')
local armed=assert(s.has('armed'))
check(table.concat(armed.prepared.lines,' '):find('возможно, вооружены',1,true))
eq(assert(cp:previewTemplate('armed',s.cfg.copilot)),table.concat(armed.prepared.lines,'\n'))
check(not s.has('combat'),'Weapon observation is not an attack')
s.person.armed=false;s.tick();check(not s.has('armed'));check(not cp:accept(armed))
s.person.armed=true;s.tick()
s.state.inVehicle=true;s.tick();check(not s.has('armed'),'A stale on-foot alert is invalid after returning to the cruiser')
s.state.inVehicle=false;s.tick()
s.cfg.copilot.armed_offer=false;s.tick();check(not s.has('armed'))
s.cfg.copilot.armed_offer=true;s.tick();s.send('armed');check(not s.has('armed'),'No second report after confirmed delivery')
s.person.generation=3;s.tick();check(not cp:propose('armed'),'New driver needs a new inspection')

-- The stock manual traffic-stop bind includes an inspection, scoped to its locked car.
cp,v,s=near();s.person.armed=true;s.tick()
local stock=require('pa26_author_rp').bindings['14']
local plan={binding={author_ref='A14',script=stock.script},target=model.copy(s.person),bindingContext={life=cp.life,car=model.copy(cp.car)},
 lines={'Предъявите паспорт и лицензии.'}}
check(not s.has('armed'))
local unrelated=model.copy(plan);unrelated.binding.script='Здравствуйте.'
cp:onExecution('completed',{plan=unrelated,sent=1});s.tick();check(not s.has('armed'))
local oldCar=model.copy(plan);oldCar.bindingContext.car.id=44
cp:onExecution('completed',{plan=oldCar,sent=1});s.tick();check(not s.has('armed'))
cp:onExecution('completed',{plan=plan,sent=1});s.tick();check(s.has('armed'))

-- Local demo exercises the same steps and cannot send anything.
cp,v,s=setup();s.state.demo=true;s.tick();check(v:selectNearest());s.tick();s.send('stop_order')
s.state.inVehicle=false;s.car.distance=3;s.person.distance=2;s.tick()
s.send('approach');s.send('window_question');prompt=advanceToAnswer(cp,s);cp:shown(prompt.token)
check(cp:decide(prompt.token,true));s.tick();s.send('greet_stop');s.send('documents')
eq(#s.sent,0);check(cp.incident.documentsRequested)
