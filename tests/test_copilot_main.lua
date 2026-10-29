-- Exercise the real main, RPC hooks, Studio modal and executor together.
local fixture=require 'support.fixture';local model=require 'pa26_bindings';local core=require 'pa26_core'
local lib=model.defaults(core.defaults());lib.alerts.enabled=true;lib.alerts.on_duty=true;lib.vehicle.require_patrol=false
lib.profile.name='Иван Петров';lib.patrol_session.station='SFPS';lib.patrol_session.unit='2-L-1'
local s=fixture({demo=false,library=lib,alerts=true,notifications=true,copilot=true});s.vehicle=true
getAllVehicles=function()check(not s.rendererContext);return{20,51}end
doesVehicleExist=function(h)return h==20 or h==51 end
sampGetVehicleIdByCarHandle=function(h)return true,h==20 and 105 or 106 end
sampGetCarHandleBySampVehicleId=function(id)return true,id==105 and 20 or 51 end
getCarModel=function(h)return h==20 and 411 or 597 end
getDriverOfCar=function(h)return h==20 and 99 or PLAYER_PED end
getNumberOfPassengers=function()return 0 end
getCarCoordinates=function(h)return 0,h==20 and 5 or 0,0 end
getCarColours=function()return 1,0 end
isCarOnScreen=function()return true end
isLineOfSightClear=function()check(not s.rendererContext);return true end
s.step();s.commands.pa26();s.step();if s.frames[1].condition()then s.commands.pa26();s.step()end
s.physicalDown={[0x12]=true,[0x37]=true};s.step();s.physicalDown={};s.step()
check(not s.frames[4].condition());check(not s.frames[1].condition());check(s.vehicleController.selected);eq(#s.sent,0)
check(s.copilot.offers[1]and s.copilot.offers[1].action=='stop_order')
s.copilot.offers={}
eq(s.workspace.selectedTarget.id,37,'Driver ID reaches ordinary interaction immediately after Alt+7');eq(s.workspace.selectedTarget.name,s.name)
s.workspace.studio.vehicleConfirm=assert(s.copilot:propose('call911'));s.render();check(s.workspace.studio.vehicleConfirm.carFree);eq(#s.sent,0)
s.click='ДА##confirm-yes';s.render();for _=1,8 do s.step(1600)end;check(#s.sent>0);check(not s.copilot.phase,'Manual radio report does not start traffic')
local radioBefore=#s.sent
s.physicalDown={[0x12]=true,[0x38]=true};s.step();s.physicalDown={};s.step();local pursuit=s.copilot.offers[1];check(pursuit and pursuit.action=='pursuit');s.copilot:shown(pursuit.token)
check(s.copilot:decide(pursuit.token,true))
eq(#s.sent,radioBefore)
for _=1,8 do s.step(1600)end
eq(s.copilot.phase,'Преследование');eq(s.copilot.pinned,'fast_wanted');check(not s.workspace.studio.caseConfirm)
local prior=#s.sent;s.workspace.studio.vehicleConfirm=assert(s.copilot:propose('fast_wanted'));s.render();check(s.workspace.studio.vehicleConfirm);eq(#s.sent,prior)
s.click='ДА##confirm-yes';s.render();for _=1,12 do s.step(1600)end
local wanted,pt=0,0
for _,line in ipairs(s.sent)do if line.line=='/su 37 8 1'then wanted=wanted+1 elseif line.line=='/pt 37'then pt=pt+1 end end
eq(wanted,1);eq(pt,1);check(not s.workspace.studio.caseConfirm);check(not s.workspace.studio.caseForm)
check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0);eq(s.invalidIOReads,0)
onScriptTerminate(s.script)
