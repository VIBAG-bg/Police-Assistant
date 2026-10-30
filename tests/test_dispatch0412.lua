-- v0.41.2: real dispatch preparation/execution, migration, driver identity and UI.
-- Offline fixtures only; no GTA, network, user files or game commands.
local model=require 'pa26_bindings';local core=require 'pa26_core'
local prefs=require 'pa26_vehicle_settings';local cpPrefs=require 'pa26_copilot_settings'
local V=require 'pa26_vehicle';local C=require 'pa26_copilot';local D=require 'pa26_dispatch'
local equal=require('pa26_author_presets').equal
local fresh=prefs.defaults();check(fresh.occupied_only and fresh.sync_driver_target);eq(fresh.copilot_migrated,2)
for _,row in ipairs(D.templates)do check(type(fresh.copilot.templates[row[1]])=='string',row[1]..' must have a usable default')end
for _,marker in ipairs({false,1})do
 local raw=model.copy(fresh);raw.copilot_migrated=marker or nil;raw.occupied_only=false;raw.sync_driver_target=false
 raw.radius=23;raw.enabled=false;raw.channel='/f';raw.model_aliases['560']='Личная машина';raw.copilot.templates.stop='Личный доклад.'
 local upgraded=assert(prefs.validate(raw));check(upgraded.occupied_only and upgraded.sync_driver_target);eq(upgraded.copilot_migrated,2)
 eq(upgraded.radius,23);check(not upgraded.enabled);eq(upgraded.channel,'/f');eq(upgraded.model_aliases['560'],'Личная машина');eq(upgraded.copilot.templates.stop,'Личный доклад.')
 upgraded.occupied_only=false;upgraded.sync_driver_target=false
 local saved=assert(prefs.validate(upgraded));check(not saved.occupied_only and not saved.sync_driver_target,'The second migration is one-time, not a startup override')
end
for _,bad in ipairs({0,3,'2',true,0/0})do local cfg=prefs.defaults();cfg.copilot_migrated=bad;check(not prefs.validate(cfg))end
-- A new target requires a streamed connected human in the DRIVER seat.
local world=require 'pa26_vehicle_world';local distance,driver,connected,npc,roundtrip,exists=10,300,true,false,300,true
local funcs={doesCharExist=function(p)return p==1 or p==300 and exists end,getCharCoordinates=function()return 0,0,0 end,
 isCharInAnyCar=function()return false end,doesVehicleExist=function(h)return h==11 end,getAllVehicles=function()return{11}end,
 sampGetVehicleIdByCarHandle=function()return true,11 end,sampGetCarHandleBySampVehicleId=function()return true,11 end,
 getCarCoordinates=function()return 0,distance,0 end,getCarModel=function()return 560 end,getCarColours=function()return 0,1 end,
 isCarOnScreen=function()return true end,isLineOfSightClear=function()return true end,getDriverOfCar=function()return driver end,
 getNumberOfPassengers=function()return 1 end,sampGetPlayerIdByCharHandle=function()return true,37 end,
 sampGetCharHandleBySampPlayerId=function()return true,roundtrip end,sampIsPlayerConnected=function()return connected end,
 sampIsPlayerNpc=function()return npc end,sampGetPlayerNickname=function()return'Driver_Name'end}
local api=world.new(function(k,...)if funcs[k]then return funcs[k](...)end end,codec,function()return 1 end)
for _,m in ipairs({0,1,5,15,40,59.99,60})do distance=m;local rows=api.scan(fresh);eq(#rows,1);eq(rows[1].driver_id,37);eq(rows[1].driver_ped,300)end
distance=60.01;eq(#api.scan(fresh),0);distance=10
local selected=assert(api.scan(fresh)[1])
for _,bad in ipairs({'empty','npc','disconnected','bad_roundtrip','missing_ped','unknown'})do
 driver=300;connected=true;npc=false;roundtrip=300;exists=true
 if bad=='empty'then driver=0 elseif bad=='npc'then npc=true elseif bad=='disconnected'then connected=false
 elseif bad=='bad_roundtrip'then roundtrip=301 elseif bad=='missing_ped'then exists=false else driver=nil end
 eq(#api.scan(fresh),0,bad);check(api.resolve(selected,fresh),'Retaining a selected car is independent of driver eligibility')
 local optional=model.copy(fresh);optional.occupied_only=false;eq(#api.scan(optional),1,'Manual opt-out includes driverless/passenger cars')
end
-- Common controller fixture with the main-thread intent queue and captured ID.
local function setup(withCar)
 local t={cfg=prefs.defaults(),now=1000,plans={},target=nil,revision=0,syncs=0,scans=0,
  state={session='test',ped=1,alive=true,focused=true,paused=false,blocked=false,onDuty=true,radioEnabled=true,demo=false,inVehicle=true,
   area='Doherty',city='Сан-Фиерро',map_square='J-6',direction='Север',my_nick='Ivan_Petrov',gender='female',
   colleagues={cruiserOccupants=1,nearbyOfficers={},ownCruiserRole='solo'},radioText={split_enabled=true,max_lines=3,continuation='...'}}}
 t.car=withCar and{id=11,handle=11,model_id=560,model_name='Sultan',distance=10,x=0,y=10,z=0,driver_known=true,
  driver_id=37,driver_ped=300,driver_name='Driver_Name',occupants=1,color1=0,color2=1}or nil
 t.driver={id=37,ped=300,name='Driver_Name',generation=0,alive=true,distance=10,x=0,y=10,z=0}
 local v=V.new({settings=function()return t.cfg end,profile=function()return{name='Иван Петров',callsign='2-L-1'}end,codec=codec,equal=equal,
  scan=function()t.scans=t.scans+1;return t.car and{model.copy(t.car)}or{}end,resolve=function()return model.copy(t.car)end,
  ownCar=function()if t.state.inVehicle then return{handle=50,x=0,y=0,z=0}end end,
  currentTarget=function()return t.target,t.revision end,driver=function(id)return id==37 and model.copy(t.driver)end,
  selectTarget=function(person)t.target=model.copy(person);t.revision=t.revision+1;t.syncs=t.syncs+1;return true end})
 local cp=C.new({vehicle=v,settings=function()return t.cfg.copilot end,profile=function()return{name='Иван Петров',callsign='2-L-1'}end,
  codec=codec,equal=equal,driver=function(id)return id==37 and model.copy(t.driver)end,
  start=function(p)t.plans[#t.plans+1]=p;return true end})
 function t.tick(dt)t.now=t.now+(dt or 300);v:tick(t.state,t.now);cp:tick(t.state,t.now)end
 function t.propose(action)local p,why=cp:propose(action);check(p,why);return p end
 function t.send(action)
  local p=t.propose(action);local n=#t.plans;check(cp:accept(p));eq(#t.plans,n,'Consent cannot send inside a UI callback')
  t.tick(1);eq(#t.plans,n+1);local plan=t.plans[#t.plans];check(cp:validPlan(plan));cp:onExecution('completed',{plan=plan});return plan
 end
 t.tick();if withCar then check(v:requestSelection());local n=t.syncs;t.tick(1);eq(t.syncs,n+1);eq(t.target.id,37)end
 return cp,v,t
end
-- Driver sync survives a genuine exit in each active stop/pursuit phase.
for _,phase in ipairs({'10-55','10-66','Преследование','10-57 FOXTROT'})do
 local cp,v,t=setup(true);v.phase=phase;local count=t.syncs
 t.car.driver_id=nil;t.car.driver_ped=nil;t.car.driver_name=nil;t.car.occupants=0;t.tick()
 eq(#v.candidates,0);check(v.selected,'Exit must not discard the captured vehicle');eq(t.target.id,37);eq(t.syncs,count)
 t.target=nil;t.revision=t.revision+1;t.tick();eq(t.target.id,37,'Restore original driver, not a new nearby player')
 t.target={id=5,ped=500,name='Manual_Person'};t.revision=t.revision+1;t.tick();eq(t.target.id,5,'Explicit manual interaction remains authoritative')
 t.target=nil;t.driver.generation=1;t.revision=t.revision+1;t.tick();check(not t.target,'ID reuse after exit cannot rebind a different player')
end
do
 local cp,v,t=setup(true);v.phase='10-55';cp.phase='10-55'
 t.car.driver_id=nil;t.car.driver_ped=nil;t.car.driver_name=nil;t.car.occupants=0;t.tick()
 local returnOffer=false;for _,p in ipairs(cp.offers)do if p.action=='return_car'then returnOffer=true end end;check(returnOffer)
 t.driver.distance=30;t.driver.y=40;t.tick();local foot=false;for _,p in ipairs(cp.offers)do if p.action=='foot'then foot=true end end;check(foot)
 t.cfg.occupied_only=false;local other=model.copy(t.car);other.id=12;other.handle=12;t.car=other
 check(v:requestSelection(12));t.tick();v.phase='10-55';t.target=nil;t.revision=t.revision+1;t.tick();check(not t.target,'A different empty car cannot reuse the old sync stamp')
end
-- Every supplied call works with no person/car target, both on foot and in-car.
for _,inVehicle in ipairs({true,false})do for _,action in ipairs({'dispatch_911','dispatch_stolen','dispatch_business','dispatch_gas','dispatch_bank'})do
 local cp,v,t=setup(false);t.state.inVehicle=inVehicle;t.tick();local p=t.propose(action)
 check(p.carFree and not p.target and not p.car);check(p.dispatchRp);eq(p.inVehicle,inVehicle)
 local text=table.concat(p.prepared.lines,'\n');check(p.prepared.lines[1]:match('^/me '));check(text:find('/do ',1,true));check(text:find('/r ',1,true));check(text:find(action=='dispatch_stolen'and'Doherty'or'Сан-Фиерро',1,true),text);check(text:find('J-6',1,true))
 if inVehicle then check(text:find('терминал',1,true));check(not text:find('КПК',1,true))else check(text:find('КПК',1,true));check(not text:find('бортов',1,true))end
 check(not text:find('{',1,true));check(not text:find('принял ',1,true),text);check(not text:find('/su ',1,true));check(not text:find('/pt ',1,true));check(not text:find('/gps ',1,true))
 local radioAt=false
 for i,line in ipairs(p.prepared.lines)do
  local wire=assert(codec.encode(line));check(#wire<=127);eq(wire,p.prepared.wires[i]);check(core.validUtf8(line))
  if line:match('^/r ')then radioAt=true else check(not radioAt,'All RP must precede the radio report')end
 end
 local before=#t.plans;t.tick(100);eq(#t.plans,before,'Preparing/viewing a dispatch cannot send')
 local plan=t.send(action);eq(plan.requirements.target,false);eq(plan.requirements.closest,false);check(not cp.phase);check(not v.phase);eq(cp.tireWarnings,0)
end end
-- Editable templates/channels and preview do not overwrite older custom reports.
do
 local cp,v,t=setup(false);t.cfg.channel='/f';t.cfg.copilot.templates.call911='Мой прежний доклад.'
 t.cfg.copilot.templates.dispatch_911_rp='/me {gender:передал|передала} вызов.\n/do Вызов принят.'
 t.cfg.copilot.templates.call_911='Проверенный вызов: {city}, {map_square}.'
 local saved=assert(prefs.validate(t.cfg));t.cfg=saved;t.tick();eq(t.cfg.copilot.templates.call911,'Мой прежний доклад.')
 local p=t.propose('dispatch_911');eq(p.prepared.lines[1],'/me передала вызов.');eq(p.prepared.lines[#p.prepared.lines],'/f Проверенный вызов: Сан-Фиерро, J-6.')
 local preview=assert(cp:previewTemplate('dispatch_911_rp',t.cfg.copilot));eq(preview,'/me передала вызов.\n/do Вызов принят.')
 check(assert(cp:previewTemplate('call_911',t.cfg.copilot)):match('^/f '));check(assert(cp:prepare('call911')).lines[1]:find('Мой прежний доклад.',1,true))
 t.cfg.copilot.dispatch_rp_enabled=false;t.tick();p=t.propose('dispatch_911');check(not p.dispatchRp);eq(#p.prepared.lines,1)
 t.cfg.copilot.dispatch_enabled=false;t.tick();check(not cp:propose('dispatch_911'));check(cp:propose('call911'),'Legacy report is independently usable')
end
for _,key in ipairs({'dispatch_911_rp','dispatch_911_foot_rp','dispatch_gas_rp','dispatch_bank_foot_rp'})do
 for _,bad in ipairs({'/su 37 8 1','plain text','/me test\n/pt 37','/me {unknown} works',''})do
  local cfg=cpPrefs.defaults();cfg.templates[key]=bad;check(not cpPrefs.validate(cfg),key..' must reject arbitrary server commands/variables')
 end
end
-- Guard estimates use max, not addition (the same colleague can be in both lists).
eq(D.officers(nil),1);eq(D.officers({colleagues={cruiserOccupants=0/0}}),1)
eq(D.officers({colleagues={cruiserOccupants=2,nearbyOfficers={{},{}}}}),3)
for _,count in ipairs({1,2,3})do
 local cp,v,t=setup(false);t.state.colleagues.cruiserOccupants=count;t.tick();local p=t.propose('dispatch_business')
 eq(p.guardRisk,count<2);check(p.confirmationTitle~=nil)
 eq(p.confirmationNote:find('3.1 / 10.4',1,true)~=nil,count<2)
 if count<2 then check(p.confirmationNote:find('Jail',1,true));check(p.confirmationNote:find('1 чел.',1,true))end
 t.cfg.copilot.robbery_warning='Проверьте экипаж: {dispatch_officers} из {robbery_min_officers}.'
 check(cp:previewTemplate('robbery_warning',t.cfg.copilot):find(count..' из 2',1,true))
 t.cfg.copilot.robbery_min_officers=3;t.tick();p=t.propose('dispatch_business');eq(p.guardRisk,count<3)
 t.cfg.copilot.robbery_guard=false;t.tick();p=t.propose('dispatch_business');check(not p.guardRisk and p.confirmationTitle=='Подтверждение доклада')
end
do
 local cp,v,t=setup(false);local p=t.propose('dispatch_business');t.state.colleagues.cruiserOccupants=2;t.tick();check(not cp:accept(p),'Crew guard must be re-confirmed when the risk changes')
 p=t.propose('dispatch_business');check(cp:accept(p));t.tick(1);local plan=t.plans[#t.plans];check(cp:validPlan(plan))
 cp:onExecution('sent_line',{plan=plan},plan.lines[1]);t.state.colleagues.cruiserOccupants=1;t.tick(1);check(not cp:validPlan(plan),'Guard remains checked between RP/radio lines')
end
-- Fresh context is checked at consent AND between executor lines.
for _,change in ipairs({'vehicle','session','focus','mode','text','channel','duty','typing'})do
 local cp,v,t=setup(false);local p=t.propose('dispatch_911');check(cp:accept(p));t.tick(1);local plan=t.plans[#t.plans];check(cp:validPlan(plan))
 cp:onExecution('sent_line',{plan=plan},plan.lines[1])
 if change=='vehicle'then t.state.inVehicle=false elseif change=='session'then t.state.session='new'
 elseif change=='focus'then t.state.focused=false elseif change=='mode'then t.state.demo=true elseif change=='text'then t.cfg.copilot.templates.call_911='Другой вызов.'
 elseif change=='channel'then t.cfg.channel='/f'elseif change=='duty'then t.state.onDuty=false else t.state.typing=true end
 t.tick(1);check(not cp:validPlan(plan),change)
end
-- Gas warning uses configured megaphone channel; never increments tyre counters.
do
 local cp,v,t=setup(false);local p=t.propose('gas_order');check(p.prepared.lines[1]:match('^/m '));check(p.confirmationNote:find('8.2',1,true));check(not p.dispatchRp)
 t.cfg.megaphone_channel='/s';t.cfg.copilot.templates.gas_order='Полиция! Оставайтесь на месте.';t.state.inVehicle=false;t.tick()
 p=t.propose('gas_order');eq(p.prepared.lines[1],'/s Полиция! Оставайтесь на месте.')
 eq(cp:previewTemplate('gas_order',t.cfg.copilot),p.prepared.lines[1]);t.send('gas_order');eq(cp.tireWarnings,0)
 t.cfg.megaphone_enabled=false;t.tick();check(not cp:propose('gas_order'));check(cp:propose('dispatch_gas'))
end
for _,key in ipairs({'robbery_warning','dispatch_confirmation_note','gas_confirmation_note'})do
 local cfg=cpPrefs.defaults();cfg[key]='Личная подсказка: {city}, {dispatch_officers}.';eq(assert(cpPrefs.validate(cfg))[key],cfg[key])
 local cp,v,t=setup(false);t.cfg.copilot[key]='Состав: {officers}/{min_officers}, предупреждения: {warnings}/{warning_count}/{ooc_warning_count}.'
 eq(cp:previewTemplate(key,t.cfg.copilot),'Состав: 1/3, предупреждения: 0/5/1.')
 cfg[key]='{unknown}';check(not cpPrefs.validate(cfg))
end
do
 local cp,v,t=setup(false)
 for _,action in ipairs({'arrive_code6','break_code7','lost_code4_adam'})do check(t.propose(action).carFree)end
 check(table.concat(t.propose('lost_code4_adam').prepared.lines,' '):find('преследуемому т/с',1,true))
 t.cfg.copilot.lost_vehicle_fallback='красному авто';t.tick();check(table.concat(t.propose('lost').prepared.lines,' '):find('красному авто',1,true))
end
-- Main/Studio path: all new buttons exist on BOTH pages; NO never starts a plan.
local fixture=require 'support.fixture';local lib=model.defaults(core.defaults());lib.alerts.enabled=true;lib.alerts.on_duty=true;lib.profile.name='Иван Петров'
local f=fixture({demo=false,library=lib,alerts=true,copilot=true});f.step();f.commands.pa26();f.step();if f.frames[1].condition()then f.commands.pa26();f.step()end
f.physicalDown={[0x73]=true};f.step();f.physicalDown={};f.step();check(f.frames[4].condition())
for _,page in ipairs({'traffic','patrol'})do
 f.workspace.studio.assistPage=page
 f.workspace.studio.dispatchExpanded={dispatch_911=true,dispatch_stolen=true,dispatch_business=true,dispatch_gas=true,dispatch_bank=true}
 for _,row in ipairs(D.actions)do
  local before=#f.sent;f.click=row[2]..'##copilot-dispatch-'..row[1];f.render();eq(f.click,nil,'Button missing from '..page)
  local notice=f.workspace.studio.feedback:peek()
  check(f.workspace.studio.vehicleConfirm and f.workspace.studio.vehicleConfirm.dispatchAction,row[1]..': '..tostring(notice and notice.text)..' '..table.concat(f.logs,'\n'));eq(#f.sent,before)
  f.click='НЕТ##confirm-no';f.render();eq(f.click,nil);check(not f.workspace.studio.vehicleConfirm);f.workspace.studio.reportEdit=nil;f.step();eq(#f.sent,before)
 end
end
f.workspace.studio.assistPage='traffic';f.click=D.actions[1][2]..'##copilot-dispatch-dispatch_911';f.render()
check(f.workspace.studio.vehicleConfirm);f.click='ДА##confirm-yes';f.render();eq(f.click,nil)
for _=1,15 do f.step(1600)end
check(#f.sent>0);check(f.sent[1].line:match('^/me '));check(f.sent[#f.sent].line:match('^/r '));check(not f.copilot.phase)
-- GUI drafts use the same validator/persistence path as all existing settings.
f.workspace.studio.copilotPage='settings';f.workspace.studio.copilotTemplate='dispatch_911_rp'
f.edits={['##Реплика##copilot-rp']='/me Передала диспетчеру данные.\n/do Вызов принят.'};f.render();check(next(f.edits)==nil)
f.step(1000);f.step(1000);eq(f.workspace.library.vehicle.copilot.templates.dispatch_911_rp,'/me Передала диспетчеру данные.\n/do Вызов принят.')
f.toggle='RP перед докладом о вызове##copilot-setting-dispatch_rp_enabled';f.render();eq(f.toggle,nil);f.step(1000);check(not f.workspace.library.vehicle.copilot.dispatch_rp_enabled)
check(not f.hasLog('Ошибка интерфейса'));eq(#f.scopes,0);eq(f.invalidIOReads,0);onScriptTerminate(f.script)
