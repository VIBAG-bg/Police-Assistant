local fixture=require 'support.fixture';local model=require 'pa26_bindings';local core=require 'pa26_core';local wheel=require 'pa26_wheel'
local lib=model.defaults(core.defaults());lib.alerts.on_duty=true;lib.vehicle.require_patrol=false
lib.settings.wheel_car_separate=false
lib.profile.name='Тест Офицер';lib.patrol_session.station='SFPS';lib.patrol_session.unit='2-L-1'
local id='assist-traffic-nearest'
for _,profile in ipairs({'compact','extended','full'})do
 lib.settings.wheel_profile=profile;lib.settings.wheel_system_groups[id]='detention'
 local clean=assert(model.validate(lib,core.defaults()));local c=wheel.build(clean,1,false,{onDuty=true,inVehicle=true})
 eq(c.bySystem[id].category,'detention');check(not c.bySystem[id].needsTarget)
 check(wheel.available(c,{id=id,kind='assist',category='detention'},false,nil))
 clean.settings.wheel_system_groups[id]='disabled';check(not wheel.build(clean,1,true,{onDuty=true}).bySystem[id])
 clean.vehicle.enabled=false;check(not wheel.build(clean,1,true,{onDuty=true}).bySystem[id])
end
lib.settings.wheel_system_groups[id]=nil
for _,entry in ipairs({'wheel','hotkey'})do
 local s=fixture({demo=false,library=model.copy(lib),alerts=true,notifications=true,copilot=true,categoryWheel=true});s.vehicle=true
 getAllVehicles=function()check(not s.rendererContext);return{20,51}end
 doesVehicleExist=function(h)return h==20 or h==51 end
 sampGetVehicleIdByCarHandle=function(h)return true,h==20 and 105 or 106 end
 sampGetCarHandleBySampVehicleId=function(v)return true,v==105 and 20 or 51 end
 getCarModel=function(h)return h==20 and 411 or 597 end
 getDriverOfCar=function(h)return h==20 and 99 or PLAYER_PED end
 getNumberOfPassengers=function()return 0 end
 getCarCoordinates=function(h)return 0,h==20 and 5 or 0,0 end
 getCarColours=function()return 1,0 end
 isCarOnScreen=function()return true end;isLineOfSightClear=function()return true end
 s.step();if s.frames[1].condition()then s.commands.pa26();s.step()end
 if entry=='hotkey'then s.physicalDown={[0x12]=true,[0x37]=true};s.step();s.physicalDown={};s.step()
 elseif entry=='wheel'then
  check(s.runtime.env.wheelNavigate({kind='assist',id=id,category='service'}))
  s.step();s.step()
 end
  check(s.vehicleController.selected,entry..' selects nearest eligible car')
  local p=s.copilot.offers[1];check(p and p.action=='stop_order',entry..' uses the original COPILOT toast')
  eq(#s.sent,0,'Selection itself never sends');eq(s.workspace.selectedTarget.id,37)
  s.copilot:shown(p.token);check(s.copilot:decide(p.token,entry=='wheel'))
  if entry=='wheel'then
   for _=1,8 do s.step(1600)end
   check(#s.sent>0);eq(s.copilot.phase,'10-55');eq(s.copilot.stopWarnings,1,'Exactly one completed stop warning')
  else eq(#s.sent,0)end
 check(not s.hasLog('Ошибка интерфейса'));onScriptTerminate(s.script)
end
