local fixture=require 'support.fixture'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local function healthy(s)check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(s.invalidIOReads,0);eq(#s.scopes,0)end
local function click(s,label)s.click=label;s.render();eq(s.click,nil,'Missing: '..label);healthy(s)end
local lib=model.defaults(core.defaults());lib.vehicle.enabled=true;lib.vehicle.megaphone_enabled=true;lib.vehicle.require_patrol=false;lib.alerts.enabled=true;lib.alerts.on_duty=true
lib.profile.name='Victor Auditore';lib.patrol_session.station='SFPS';lib.patrol_session.unit='P-01'
lib.vehicle.phrase_1_shortcut={key=0x30,alt=true,ctrl=false,shift=false}
local s=fixture({demo=false,library=lib,alerts=true,notifications=true,categoryWheel=true})
getAllVehicles=function()check(not s.rendererContext);return {20}end
doesVehicleExist=function(h)return not s.gone and h==20 end
sampGetVehicleIdByCarHandle=function()return true,105 end;sampGetCarHandleBySampVehicleId=function()return true,20 end
getCarModel=function()return 411 end;getDriverOfCar=function()return 99 end;getCarCoordinates=function()return 0,5,0 end
getCarColours=function()return 1,0 end;getNameOfVehicleModel=function()return 'INFERNUS'end
getGxtText=function(k)return k=='INFERNUS'and 'Infernus'or 'Doherty'end
isCarOnScreen=function()return true end;isLineOfSightClear=function()check(not s.rendererContext);return true end
s.step();s.page('partners');click(s,'Транспорт##Напарники и служба##partners-pagevehicle')
click(s,'Мои требования в мегафон##vehicle-own-megaphone');s.render()
click(s,'Infernus [105] · 5 м##assist-car-105');check(s.vehicleController.selectionRequest);s.step();eq(s.vehicleController.selected.id,105);eq(#s.sent,0)
click(s,'Настройки##megaphone-pagesettings')
s.edits={['##Короткое название##assist-phrase-name']='Остановитесь',
    ['##Текст без /команды##assist-phrase-text']='Водитель {model}, говорит {station}. Цвет: {vehicle_color}. Остановитесь.'};s.render();s.edits={};s.step(700)
eq(s.workspace.library.vehicle.phrases[1].name,'Остановитесь')
click(s,'Реплики##megaphone-pagephrases')
click(s,'Остановитесь##assist-say-1');check(s.workspace.studio.vehicleConfirm);eq(#s.sent,0)
click(s,'НЕТ##confirm-no');s.step();eq(#s.sent,0)
click(s,'Остановитесь##assist-say-1');click(s,'ДА##confirm-yes');s.step();s.step(1500)
eq(#s.sent,1);check(s.sent[1].line:find('/m Водитель Infernus, говорит SFPS.',1,true)==1);check(s.sent[1].line:find('Цвет:',1,true))
s.step(1500);eq(#s.sent,1,'No automatic repeat')
-- Stale consent after settings edits is rejected before any queued send.
click(s,'Остановитесь##assist-say-1');local proposal=s.workspace.studio.vehicleConfirm
local changed=model.copy(s.workspace.library);changed.vehicle.phrases[1].template='Новый текст.';check(s.workspace:save(changed))
click(s,'ДА##confirm-yes');check(s.workspace.studio.modalError);eq(#s.sent,1);s.workspace.studio:cancelModal()
-- A phrase key opens the established confirmation rather than sending directly.
s.commands.pa26();s.commands.pa26();s.physicalDown={};s.step();s.step() -- Close stale popup, then arm a fresh physical chord.
s.physicalDown={[0x12]=true,[0x30]=true};s.step();s.physicalDown={};s.step()
check(s.workspace.studio.vehicleConfirm);eq(s.workspace.studio.vehicleConfirm.action,'megaphone_1');eq(#s.sent,1)
s.gone=true;s.events.onVehicleStreamOut(105);click(s,'ДА##confirm-yes');check(s.workspace.studio.modalError);eq(#s.sent,1)
healthy(s);onScriptTerminate(s.script)
