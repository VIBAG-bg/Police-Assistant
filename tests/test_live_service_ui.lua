local fixture=require 'support.fixture'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local function healthy(s)
    check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(s.invalidIOReads,0)
end
local function click(s,label)s.click=label;s.render();eq(s.click,nil,'Invisible control: '..label);healthy(s)end
local function setup()
    local lib=model.defaults(core.defaults());lib.vehicle.enabled=true;lib.vehicle.megaphone_enabled=true;lib.vehicle.require_patrol=false
    lib.profile.name='Victor Auditore';lib.profile.callsign='SWITCH';lib.alerts.enabled=true;lib.alerts.on_duty=true
    lib.patrol_session.station='SFPS';lib.patrol_session.unit='P-01'
    local s=fixture({demo=false,library=lib,alerts=true,notifications=true,categoryWheel=true})
    s.gone=false;s.carColors={1,0}
    getAllVehicles=function()check(not s.rendererContext,'Native scan from GUI');return {20}end
    doesVehicleExist=function(h)return not s.gone and h==20 end
    sampGetVehicleIdByCarHandle=function(h)return true,105 end
    sampGetCarHandleBySampVehicleId=function(id)return true,20 end
    getCarModel=function()return 411 end
    getDriverOfCar=function()return 99 end
    getCarCoordinates=function()return 0,5,0 end
    getCarColours=function()return s.carColors[1],s.carColors[2]end
    getNameOfVehicleModel=function()return 'INFERNUS'end
    getGxtText=function(key)return key=='INFERNUS'and 'Infernus'or 'Doherty'end
    isCarOnScreen=function()return true end
    isLineOfSightClear=function()check(not s.rendererContext);return true end
    s.step();s.page('partners');click(s,'Транспорт##Напарники и служба##partners-pagevehicle')
    return s
end
local s=setup();check(s.vehicleController:view().nearest);eq(#s.sent,0)
click(s,'Выбрать ближайшую и начать 10-55##vehicle-select');check(s.workspace.studio.vehicleConfirm);eq(#s.sent,0)
click(s,'НЕТ##confirm-no');s.step();eq(#s.sent,0)
-- Without a session, unit and station come from explicit saved patrol fields.
click(s,'Выбрать ближайшую и начать 10-55##vehicle-select');click(s,'ДА##confirm-yes');eq(#s.sent,0)
s.step();healthy(s);check(#s.sent>=1);for _=1,5 do s.step(1500)end
eq(s.vehicleController.phase,'10-55');check(s.sent[1].line:find('Infernus',1,true))
local stored=model.copy(s.workspace.library);local seen=false
for _,line in ipairs(s.sent)do if line.line:find('10%-55')then seen=true end end;check(seen)
-- Physical hotkeys work with F9 closed and open the vehicle tab, never the patrol tab.
s.commands.pa26();s.physicalDown={};s.step()
s.physicalDown={[0x12]=true,[0x37]=true};s.step();s.physicalDown={};s.step()
eq(s.workspace.studio.partnerPage,'vehicle');check(s.workspace.studio.vehicleConfirm)
local before=#s.sent;s.physicalDown={[0x4e]=true};s.step();s.physicalDown={};s.step();check(not s.workspace.studio.vehicleConfirm);eq(#s.sent,before)
s.commands.pa26();s.physicalDown={};s.step()
s.physicalDown={[0x12]=true,[0x39]=true};s.step();s.physicalDown={};s.step();check(s.frames[4].condition());check(not s.workspace.studio.vehicleConfirm)
click(s,'Остановиться##assist-say-1');check(s.workspace.studio.vehicleConfirm)
s.step() -- release Y before the newly opened confirmation may accept its edge
s.physicalDown={[0x59]=true};s.step();s.physicalDown={};s.step(1500);s.step(1500)
check(#s.sent>before);check(s.sent[#s.sent].line:match('^/m '));healthy(s)
s.commands.pa26();s.page('partners');click(s,'Транспорт##Напарники и служба##partners-pagevehicle')
s.edits={['##Обратиться в мегафон##vehicle-template-megaphone_template']='Водитель {model}, говорит {station}. Остановитесь у обочины.'};s.render();s.edits={};s.step(700)
eq(s.workspace.library.vehicle.megaphone_template,'Водитель {model}, говорит {station}. Остановитесь у обочины.')
check(s.savedLibrary().vehicle.enabled)
-- Stream-out invalidates consent and does not auto-select a different car.
click(s,'Обратиться в мегафон##vehicle-action-megaphone');check(s.workspace.studio.vehicleConfirm)
s.events.onVehicleStreamOut(105);local count=#s.sent;click(s,'ДА##confirm-yes');check(s.workspace.studio.modalError);eq(#s.sent,count)
s.workspace.studio:cancelModal();s.step();healthy(s);onScriptTerminate(s.script);eq(s.events.onVehicleStreamOut,nil)
-- The actual main hook captures a passport shown to us, even with chat filters off.
local lib=model.defaults(core.defaults());lib.identity.passport_server=''
s=fixture({demo=false,library=lib,alerts=true,categoryWheel=true});s.name='Victor_Auditore'
s.actors={[99]={id=38,name='Rafayel_Barvello',x=0,y=2,z=0,sx=600,sy=350}}
s.step();s.commands.pa26select('38');s.step()
check(s.workspace.selectedTarget);s.events.onServerMessage(-1,codec.encode('Rafayel_Barvello достал паспорт и показал его Victor_Auditore'))
eq(s.identity:view().record.passport_seen,'unknown','RPC only enqueues evidence')
s.step();eq(s.identity:view().record.passport_seen,'yes');eq(s.identity:view().record.passport_source,'server');eq(s.identity:view().record.passport_number,'')
onScriptTerminate(s.script)
-- Command-taser fields and manual mode confirmation use the real GUI/save path.
lib=model.defaults(core.defaults());lib.alerts.enabled=true;lib.alerts.on_duty=true
s=fixture({demo=false,library=lib,alerts=true,notifications=true,categoryWheel=true});s.step();s.weapon=24;s.step()
s.page('settings');click(s,'Оружие##settings-tab-weapons');click(s,'Тайзер##Снаряжение##weapons-pagetaser')
eq(s.taser.shots,0);s.events.onSendBulletSync({weaponId=24});s.step();eq(s.taser.shots,0)
click(s,'Подтверждаю: тайзер включён##taser-mode-on');s.step();check(s.taser:activeFor())
s.events.onSendBulletSync({weaponId=24});s.step();eq(s.taser.shots,1)
s.edits={['##Название тайзера##taser-mode-name']='Taser X-26 Custom'};s.render();s.edits={};s.step(700)
eq(s.workspace.library.taser.name,'Taser X-26 Custom')
eq(s.savedLibrary().taser.name,'Taser X-26 Custom')
click(s,'Подтверждаю: обычный Deagle##taser-mode-off');s.step();check(not s.taser:activeFor());eq(s.taser.shots,1)
healthy(s);onScriptTerminate(s.script)
