-- Behavioral regressions for the accepted 0.42.1 scope; no game APIs or sends.
local model=require 'pa26_bindings';local core=require 'pa26_core'
local vsettings=require 'pa26_vehicle_settings';local C=require 'pa26_copilot';local V=require 'pa26_vehicle'
local equal=require('pa26_author_presets').equal
local defaults=model.defaults(core.defaults())
eq(defaults.vehicle.copilot.always_show_on_duty,false)
eq(defaults.settings.manual_actions.rules.find.enabled,false)
eq(defaults.settings.manual_actions.rules.taser.enabled,false)
check(defaults.settings.manual_actions.rules.ticket.enabled)
local saved=model.copy(defaults)
saved.vehicle.copilot.always_show_on_duty=true;saved.vehicle.copilot.repeat_megaphone=false
saved.vehicle.copilot.pursuit_retention=false;saved.settings.retain_distance=65;saved.settings.retain_grace_ms=2000
saved.settings.manual_actions.rules.find.enabled=true;saved.settings.manual_actions.rules.cuff.prefer_bind=true
saved.settings.manual_actions.rules.cuff.rp='/me личная отыгровка.'
saved.taser.draw_rp_enabled=false;saved.taser.holster_rp_enabled=false;saved.taser.reload_rp_enabled=false
local clean=assert(model.validate(saved,core.defaults()))
eq(clean.settings.retain_distance,65);eq(clean.settings.retain_grace_ms,2000)
check(clean.vehicle.copilot.always_show_on_duty);check(not clean.vehicle.copilot.repeat_megaphone)
check(not clean.vehicle.copilot.pursuit_retention);check(clean.settings.manual_actions.rules.find.enabled)
check(clean.settings.manual_actions.rules.cuff.prefer_bind)
eq(clean.settings.manual_actions.rules.cuff.rp,'/me личная отыгровка.')
check(not clean.taser.draw_rp_enabled and not clean.taser.holster_rp_enabled and not clean.taser.reload_rp_enabled)
local types=require 'pa26_vehicle_types'
for _,r in ipairs({{437,'bus'},{481,'bicycle'},{509,'bicycle'},{510,'bicycle'},{471,'quad'},
 {522,'bike'},{413,'van'},{403,'truck'},{487,'heli'},{593,'plane'},{454,'boat'},
 {537,'train'},{435,'trailer'},{7000,'unknown'},{0/0,'unknown'}})do eq(types.class(r[1]),r[2])end
local typed=types.defaults();typed.bus.name='мой автобус';typed.bus.genitive='моего автобуса'
local cfg=vsettings.defaults();cfg.type_names=typed;check(vsettings.validate(cfg))
local description=assert(V.describe({id=7,model_id=437,model_name='Coach',color1=1,color2=0},cfg,'male'))
eq(description.vehicle_type,'мой автобус');eq(description.vehicle_type_gen,'моего автобуса')
check(description.vehicle_description:find('мой автобус',1,true))
local bad=model.copy(typed);bad.bus.genitive='/m\nвторая команда';check(not types.validate(bad))
for _,value in ipairs({19,301,0/0})do
 local broken=model.copy(defaults.vehicle.copilot);broken.pursuit_retain_distance=value
 check(not require('pa26_copilot_settings').validate(broken))
end

-- The retention exemption is supplied only for an already selected pursuit
-- account. It cannot turn a distant or obscured actor into physical availability.
local trackerModule=require 'pa26_target'
local person={id=37,ped=99,name='Driver_Name'}
local observed={connected=true,name=person.name,distance=280,visible=false,tracked=person}
local tracker=trackerModule.new({inspect=function()return model.copy(observed)end})
local ctx={session='one',alive=true}
local ordinary={action_distance=8,retain_distance=40,retain_grace_ms=1500}
check(tracker:select(person,'one'));tracker:refresh(ctx,1000,ordinary);tracker:refresh(ctx,2500,ordinary)
check(not tracker.target,'Ordinary interaction retains the old distance limit')
local chase=model.copy(ordinary);chase.pursuit={distance=300,grace=15000}
check(tracker:select(person,'one'));tracker:refresh(ctx,3000,chase)
check(tracker.target);eq(tracker.state,'out_of_range');eq(tracker.distance,280)
observed.distance=5;observed.tracked=person;tracker:refresh(ctx,3300,chase)
eq(tracker.state,'out_of_range','Occluded target does not gain physical availability')
observed.distance=nil;observed.tracked=nil;tracker:refresh(ctx,3600,chase)
check(tracker.target);eq(tracker.state,'unavailable');eq(tracker.distance,nil)
observed.distance=280;observed.tracked=person;tracker:refresh(ctx,3900,ordinary);tracker:refresh(ctx,5500,ordinary)
check(not tracker.target,'Exemption ends when pursuit ends')
check(tracker:select(person,'one'));observed.distance=310;tracker:refresh(ctx,6000,chase);tracker:refresh(ctx,21000,chase)
check(not tracker.target,'Known distance beyond 300 expires')
check(tracker:select(person,'one'));tracker:join(37);check(not tracker.target,'Reused ID invalidates even the same nickname')

local function setup()
 local s={now=1000,cfg=vsettings.defaults(),plans={},stream=true,vehicleLive=true,connected=true,
  state={session='one',ped=1,alive=true,focused=true,paused=false,blocked=false,onDuty=true,radioEnabled=true,
   demo=false,inVehicle=true,area='Doherty',city='Сан-Фиерро',map_square='J-6',my_nick='Ivan_Petrov',radioText={split_enabled=true,max_lines=3,continuation='...'}}}
 s.car={id=142,handle=100,model_id=437,model_name='Coach',color1=0,color2=1,x=0,y=10,z=0,distance=10,driver_known=true,driver_ped=99,driver_id=37,occupants=2}
 s.person={id=37,ped=99,name='Driver_Name',generation=0,armed=false,distance=10,x=0,y=10,z=0}
 local cp
 local vehicle=V.new({settings=function()return s.cfg end,codec=codec,equal=equal,
  profile=function()return{name='Иван Петров',callsign='1-L-1'}end,
  scan=function()return s.vehicleLive and{model.copy(s.car)}or{}end,
  resolve=function()return s.vehicleLive and model.copy(s.car)or nil end,
  retention=function()if cp and cp:inPursuit()then return{distance=s.cfg.copilot.pursuit_retain_distance}end end,
  ownCar=function()return{handle=50,x=0,y=0,z=0}end,start=function()return true end})
 cp=C.new({vehicle=vehicle,settings=function()return s.cfg.copilot end,
  profile=function()return{name='Иван Петров',callsign='1-L-1'}end,codec=codec,equal=equal,
  driver=function()return s.stream and s.connected and model.copy(s.person)or nil end,
  driverAccount=function()if s.connected then return{id=37,name=s.person.name,generation=s.person.generation}end end,
  start=function(plan)s.plans[#s.plans+1]=plan;return true end})
 function s.tick(dt)s.now=s.now+(dt or 300);vehicle:tick(s.state,s.now);cp:tick(s.state,s.now)end
 function s.send(action)
  local p,err=cp:propose(action);check(p,err);check(cp:accept(p));s.tick()
  local plan=s.plans[#s.plans];check(plan);check(cp:validPlan(plan))
  cp:onExecution('completed',{plan=plan,demo=false});return plan
 end
 function s.offer(action)for _,p in ipairs(cp.offers)do if p.action==action then return p end end end
 s.tick();check(vehicle:selectNearest());s.tick();return s,cp,vehicle
end
local s,cp,vehicle=setup()
check(cp:view().visible,'Selection immediately shows the card')
check(not cp:retentionFor(s.person));s.send('stop_order');check(not cp:retentionFor(s.person));eq(cp.tireWarnings,0)
s.send('pursuit');eq(cp:retentionFor(s.person).distance,300)
s.car.distance=280;s.car.y=280;s.person.distance=280;s.person.y=280;s.tick()
check(vehicle.selected);check(cp.driver);check(cp:prepare('fast_wanted'))
local p=assert(cp:propose('fast_wanted'));check(cp:accept(p));s.tick()
local plan=s.plans[#s.plans];cp:onExecution('sent_line',{plan=plan},'/su 37 8 1')
local life=cp.life;cp:hideHud()
check(not cp:view().visible);eq(cp.life,life);check(cp.queued and cp.queued.suSent)
cp:onExecution('cancelled',{plan=plan});check(cp.done.fast_wanted);eq(cp.pinned,'pursuit_mark')
cp:hideHud();eq(cp.pinned,'pursuit_mark');check(not cp:propose('fast_wanted'))
s.stream=false;s.vehicleLive=false;s.tick()
check(cp.driver and cp.driverLive and cp.driverLive.stale);check(cp.car.stale)
eq(cp.car.distance,nil);check(cp:prepare('pursuit_mark'),'Remote pursuit command retains verified account context')
check(not cp:prepare('taser_warning'));check(not cp:propose('approach'))
s.person.generation=1;s.tick();check(not cp.driver,'ID generation change cancels stale pursuit identity')
s,cp,vehicle=setup();s.send('pursuit');s.send('high_risk')
check(not cp:retentionFor(s.person),'300 m ends at 10-66')
s,cp,vehicle=setup();s.send('pursuit');s.stream=false;s.vehicleLive=false;s.tick();check(cp.driver)
s.tick(16000);check(not cp.driver,'Lost observations expire after grace')
s,cp,vehicle=setup();s.send('pursuit');s.car.id=143;s.tick()
check(not cp.phase,'A different vehicle ID is not a temporary stream loss')

-- Repeated offers are proposals only; refusal postpones, pause suppresses,
-- stopping replaces warnings and ordinary stop requests do not count as fire.
s,cp,vehicle=setup();s.send('stop_order');eq(cp.tireWarnings,0)
s.car.y=s.car.y+1;s.tick(5000);p=s.offer('stop_order');check(p and p.repeatOffer);eq(#s.plans,1)
cp:shown(p.token);check(cp:decide(p.token,false))
s.car.y=s.car.y+1;s.tick(1000);check(not s.offer('stop_order'))
s.car.y=s.car.y+1;s.tick(4000);p=s.offer('stop_order');check(p and p.repeatOffer);eq(#s.plans,1)
cp:pauseRepeats();s.car.y=s.car.y+1;s.tick(5000);check(not s.offer('stop_order'))
cp:pauseRepeats();s.car.y=s.car.y+1;s.tick(5000);check(s.offer('stop_order'))
s.tick(2000);check(not s.offer('stop_order'));check(s.offer('stop'),'Stationary vehicle switches to a stop report offer')
eq(cp.tireWarnings,0)
s,cp,vehicle=setup();cp:offer('stop_order');p=s.offer('stop_order');check(p);cp:shown(p.token);check(cp:decide(p.token,false))
s.car.y=s.car.y+1;s.tick(5000);check(s.offer('stop_order'),'Initial N postpones an offer even before a traffic phase starts')
eq(#s.plans,0)
s,cp,vehicle=setup();s.send('stop_order');s.send('pursuit')
s.cfg.copilot.pursuit_retention=false;s.tick();s.car.y=s.car.y+1;s.tick(5000)
local warning,warningError=cp:propose('tire')
check(s.offer('tire'),warningError or('Disabling retention does not change pursuit warning semantics: '..tostring(cp.phase)..', repeatAt='..tostring(cp.repeatAt)..', offers='..#cp.offers))
eq(cp.tireWarnings,0)

-- Silent RP-reload changes only PA's advisory count after the full cooldown.
local prefs=require 'pa26_preferences';local Taser=require 'pa26_taser'
local toggles=prefs.taserDefaults();toggles.active_reply='ACTIVE'
local toggle=Taser.new({settings=function()return toggles end,codec=codec,start=function()return true end})
local toggleState={session='one',ped=1,alive=true,focused=true,paused=false,blocked=false,onDuty=true,weapon=24}
toggle:tick(toggleState,1000);check(toggle:command('/taser',true));toggle:tick(toggleState,1010)
eq(toggle.mode,'unknown');check(toggle:serverMessage('ACTIVE'));toggle:tick(toggleState,1020)
check(toggle.suppressModeRp,'A handled manual command does not trigger a second weapon RP')
eq(toggle.mode,'active')
local tc=prefs.taserDefaults();tc.activation='weapon';tc.reload_rp_enabled=false
local starts=0;local taser=require('pa26_taser').new({settings=function()return tc end,codec=codec,start=function()starts=starts+1;return true end})
local ts={session='one',ped=1,alive=true,focused=true,paused=false,blocked=false,onDuty=true,weapon=24,gender='male'}
taser:tick(ts,1000);taser:bullet({weaponId=24});taser:tick(ts,1100)
taser:tick(ts,6100);taser:bullet({weaponId=24});taser:tick(ts,6200);eq(taser.shots,2)
taser:tick(ts,11199);eq(taser.shots,2);eq(starts,0)
taser:tick(ts,11200);eq(taser.shots,0);eq(starts,0)
-- Independent holster text can remain enabled when draw text is disabled.
local wc=prefs.weaponDefaults();wc.enabled=true;wc.delay_ms=1000;wc.holster_delay_ms=1000
local plans={};local weapons=require('pa26_weapons').new({settings=function()return wc end,codec=codec,start=function(q)plans[#plans+1]=q;return true end})
ts.taserActive=true;ts.taserRoleItem={name='Taser X26',draw_rp_enabled=false,template='достал {weapon}.',holster_enabled=true,holster_template='убрал {weapon}.'}
ts.weapon=0;weapons:tick(ts,1000);ts.weapon=24;weapons:tick(ts,2000);weapons:tick(ts,3100);eq(#plans,0)
ts.weapon=0;weapons:tick(ts,3200);weapons:tick(ts,4300)
eq(#plans,1);eq(plans[1].automatic.kind,'weapon_holster')
