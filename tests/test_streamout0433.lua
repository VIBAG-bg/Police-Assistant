local setup=require 'support.copilot_fixture'
local function contact(source)
 local cp,v,s=setup();s.send('stop_order');s.state.inVehicle=false;s.car.distance=3;s.person.distance=2;s.tick()
 check(not cp:observeManualCommand('/ud 38',source));check(cp:observeManualCommand('/ud 37',source));check(not cp.done.explain_stop)
 return cp,v,s
end
local function stream(v,s)s.car=nil;s.unstreamed=true;v:clearTarget('stream out',true);s.tick()end
for _,source in ipairs({'native','cef','executor'})do
 local cp,v,s=contact(source);local before=cp.life
 stream(v,s);local p=s.has('finish');check(p,'/ud + stream-out on foot must offer finish')
 check(cp.car.stale);eq(cp.life,before);check(not cp.incident.departed);check(not s.has('pursuit'))
 eq(cp:values().stop_area,'Doherty');eq(cp:values().stop_map_square,'J-6')
 cp:shown(p.token);check(cp:decide(p.token,false));for _=1,12 do s.tick()end
 check(cp.phase~=nil);check(not s.has('finish'));check(not s.has('pursuit'),'Stream-out only never proves flight')
 local finish=assert(cp:propose('finish'));check(cp:accept(finish));s.tick();cp:onExecution('completed',{plan=s.plans[#s.plans],demo=false});eq(cp.phase,nil)
end
local cp,v,s=setup();s.send('stop_order');s.state.inVehicle=false;stream(v,s);check(not s.has('finish'),'No contact means no stream-out finish offer')
cp,v,s=contact('executor');s.state.blocked=true;stream(v,s);eq(#cp.offers,0,'CEF input owns confirmation input')
s.state.blocked=false;s.tick();check(s.has('finish'))
for _,field in ipairs({'modal','typing','recording','wheel','alertPending','ownUi','busy'})do
 cp,v,s=contact('executor');s.state[field]=true;stream(v,s);check(not s.has('finish'),field..' owns the input')
 s.state[field]=false;s.tick();check(s.has('finish'),'Finish is offered when '..field..' releases input')
end
cp,v,s=contact('native');stream(v,s);local toast=assert(s.has('finish'));check(toast.confirmationNote:find('вне наблюдения',1,true))
s.state.modal=true;s.tick(s.cfg.copilot.toast_ms+1);s.state.modal=false;s.tick();check(s.has('finish'),'A hidden expired offer can be prepared afresh')
cp,v,s=contact('native');s.car.x=20;s.tick();local finish=assert(s.has('finish'));cp:shown(finish.token);check(cp:decide(finish.token,false))
for _=1,3 do s.tick();check(s.has('pursuit'),'Observed flight offer must not vanish on the next tick')end
cp,v,s=contact('native');s.car.id=43;s.car.handle=101;v.selected=require('pa26_bindings').copy(s.car);cp:tick(s.state,s.now+500)
check(not s.has('finish'),'Another selected car cannot inherit the old contact');eq(cp.manualUdDone,nil)
