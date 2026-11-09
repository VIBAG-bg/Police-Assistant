local core=require 'pa26_core'
local model=require 'pa26_bindings'
local fixture=require 'support.fixture'
local vehicle=require 'pa26_vehicle'
local geometry=require 'pa26_geometry'
local prefs=require 'pa26_patrol_settings'

local lib=model.defaults(core.defaults())
lib.alerts.on_duty=true;lib.alerts.enabled=true
lib.vehicle.require_patrol=true;lib.vehicle.megaphone_require_patrol=true
lib.profile.name='Иван Петров';lib.profile.rank='Сержант';lib.profile.department='EPD';lib.profile.callsign='1-L-9'
lib.settings.help.visible=true;lib.settings.help.welcome=false
local function game()
 local s=fixture({demo=false,library=model.copy(lib),alerts=true,notifications=true,copilot=true,categoryWheel=true,productionWindows=true})
 s.vehicle=true
 getAllVehicles=function()check(not s.rendererContext);return{20,51}end
 doesVehicleExist=function(h)return h==20 or h==51 end
 sampGetVehicleIdByCarHandle=function(h)return true,h==20 and 105 or 106 end
 sampGetCarHandleBySampVehicleId=function(id)return true,id==105 and 20 or 51 end
 getCarModel=function(h)return h==20 and 426 or 597 end
 getNameOfVehicleModel=function()return'PREMIER'end
 getGxtText=function(key)return key=='PREMIER'and'Premier'or'Doherty'end
 getDriverOfCar=function(h)return h==20 and(s.exited and 0 or 99)or PLAYER_PED end
 getNumberOfPassengers=function()return 0 end
 getCarCoordinates=function(h)return 0,h==20 and 5 or 0,0 end
 getCarColours=function()return 999,999 end
 isCarOnScreen=function()return true end
 isLineOfSightClear=function()check(not s.rendererContext);return true end
 s.step()
 if s.frames[1].condition()then s.commands.pa26();s.step()end
 return s
end
local function click(s,label)
 s.click=label;s.render();eq(s.click,nil,label)
 check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'))
end
local function hold(s,key,modifier)
 s.physicalDown=modifier and{[modifier]=true,[key]=true}or{[key]=true};s.step()
 s.physicalDown={};s.step()
end
local function run(s)
 for _=1,9 do s.step(1600)end
 check(not s.patrolSession.data.active)
end
for _,entry in ipairs({'f4','wheel','hotkey'})do
 local s=game();local studio=s.workspace.studio
 if entry=='f4' then
  hold(s,0x73);click(s,'Начать 10-55##copilot-stop_order');s.step()
 elseif entry=='wheel'then
  check(s.runtime.env.wheelNavigate({kind='assist',id='assist-traffic-nearest',category='service'}));s.step()
 else hold(s,0x37,0x12)end
 local p=assert(studio.vehicleConfirm or s.copilot.offers[1],entry)
 eq(p.action,'stop_order');eq(p.driver.id,37);eq(p.description,'Premier');eq(#s.sent,0)
 local preview=table.concat(p.prepared.lines,'\n')
 check(preview:find('Сержант EPD Петров',1,true));check(not preview:find('неизвест',1,true))
 if studio.vehicleConfirm then click(s,'ДА##confirm-yes')
 else s.copilot:shown(p.token);check(s.copilot:decide(p.token,true))end
 run(s)
 eq(s.copilot.phase,'10-55');eq(s.vehicleController.phase,s.copilot.phase);eq(s.copilot.stopWarnings,1)
 eq(#s.sent,#p.prepared.lines)
 for _,row in ipairs(s.sent)do check(row.line:match('^/m '))end
 onScriptTerminate(s.script)
end

-- Start VICTOR directly from F4 and use the existing report timer without starting patrol.
do
 local s=game();local studio=s.workspace.studio
 s.workspace.library.patrol_session.enabled=true
 s.workspace.library.vehicle.pursuit_interval_ms=5000
 s.workspace.library.vehicle.pursuit_confirmation=true
 s.workspace.library.radio_guard.lead_ms=1000
 hold(s,0x73);click(s,'10-57 · Начать погоню##copilot-pursuit');s.step()
 local p=assert(studio.vehicleConfirm);eq(p.action,'pursuit');eq(#s.sent,0)
 click(s,'ДА##confirm-yes');s.step()
 hold(s,0x73);run(s)
 eq(s.copilot.phase,'Преследование');check(s.patrol.active)
 eq(s.patrol:view().label,'Погоня 10-57');eq(#s.sent,#p.prepared.lines)
 local ticket=s.radioGuard:first();check(ticket and ticket.phase=='confirm' and ticket.spec.pursuitKey)
 check(s.radioGuard:decide(ticket.token,true))
 for _=1,3 do s.step(1200)end
 check(#s.sent>#p.prepared.lines);check(s.sent[#p.prepared.lines+1].line:find('продолжаю преследование',1,true))
 s.events.onVehicleStreamOut(105);s.step()
 check(not s.patrol.active);check(not s.patrolSession.data.active)
 onScriptTerminate(s.script)
end

-- HUD actions use the same action router and locked target as the F4 controls.
local s=game();local studio=s.workspace.studio
hold(s,0x37,0x12)
local stop=s.copilot.offers[1];s.copilot:shown(stop.token);check(s.copilot:decide(stop.token,true));run(s)
local function hud(action)
 s.copilot.widgetMail={action=action,life=s.copilot.life,at=s.copilot.now};s.step();s.step()
end
hud('megaphone_order')
local order=studio.vehicleConfirm or s.copilot.offers[1];check(order and order.action=='megaphone_order');eq(order.driver.id,37)
if studio.vehicleConfirm then click(s,'ДА##confirm-yes')
else s.copilot:shown(order.token);check(s.copilot:decide(order.token,true))end
run(s);eq(s.copilot.stopWarnings,2)
hud('pursuit')
check(studio.vehicleConfirm and studio.vehicleConfirm.action=='pursuit')
eq(studio.vehicleConfirm.reportValues.unit,'1-L-9')
click(s,'ДА##confirm-yes');run(s)
eq(s.copilot.phase,'Преследование')
local before=#s.sent
hud('pursuit_wanted');run(s)
check(studio.caseForm and studio.caseForm.kind=='wanted');eq(studio.caseForm.target.id,37)
check(not studio.caseForm.reason_id or studio.caseForm.reason_id=='')
eq(#s.sent,before,'Opening the standard reason form does not send anything')
hold(s,0x79)
if studio.caseForm and s.frames[4].condition()then hold(s,0x73)end
-- The standalone controller has no implicit charge in the pursuit preview.
local mark=assert(s.copilot:propose('pursuit_mark'))
eq(mark.prepared.lines[1],'/pt 37');eq(#mark.prepared.lines,1)
for _,row in ipairs(s.sent)do check(not row.line:match('^/su ')and not row.line:match('^/pt '))end
onScriptTerminate(s.script)

-- Probe passive overlay via the real input callback. Outside ×, the game owns the click.
s=game();studio=s.workspace.studio
local name='Клавиши PA##pa26-help-overlay'
local panel=assert(s.windows[name])
check(table.concat(s.drawnText,'\n'):find('Alt+7 — Начать 10-55',1,true))
local helpKey={key=0x38,ctrl=true,alt=false,shift=true}
s.workspace.library.vehicle.select_shortcut=helpKey
s.drawnText={};s.step()
check(table.concat(s.drawnText,' '):find(model.shortcutName(helpKey)..' — Начать 10-55',1,true))
s.workspace.library.vehicle.select_shortcut={key=0,ctrl=false,alt=false,shift=false}
s.drawnText={};s.step();check(table.concat(s.drawnText,'\n'):find('Отключено — Начать 10-55',1,true))
local function clickAt(x,y)
 s.mx,s.my=x,y;local old=s.consumed
 onWindowMessage(0x201,0,0);onWindowMessage(0x202,0,0)
 return s.consumed-old
end
panel=assert(s.windows[name])
local cx,cy=panel.x+panel.width-12,panel.y+12
eq(clickAt(cx,cy),0,'No capture during normal gameplay')
s.physicalDown={[0x12]=true};s.step()
eq(clickAt(panel.x+10,panel.y+36),0,'Overlay body passes clicks through')
s.chat=true;eq(clickAt(cx,cy),0,'Chat activation blocks close even before a new frame')
s.chat=false;s.step()
eq(clickAt(cx,cy),2,'Only the X click pair is consumed')
s.step();check(not s.workspace.library.settings.help.visible);check(not s.savedLibrary().settings.help.visible)
s.physicalDown={};s.step();s.commands.pa26();s.page('settings')
click(s,'6. Экран, HUD и карта##settings-tab-general');studio.screenSettingsPage='hud'
s.toggle='Показывать подсказки клавиш##pa26-help-visible';s.render();eq(s.toggle,nil)
s.step(500);check(s.savedLibrary().settings.help.visible)
onScriptTerminate(s.script)

-- User-visible report values, migration, and punctuation.
local vc=require('pa26_vehicle_settings').defaults()
local car={id=2,model_id=426,model_name='Premier',color1=0,color2=0}
eq(assert(vehicle.describe(car,vc)).vehicle_description,'Чёрный Premier')
car.color2=999;eq(assert(vehicle.describe(car,vc)).vehicle_description,'Чёрный Premier')
car.color1=999;eq(assert(vehicle.describe(car,vc)).vehicle_description,'Premier')
eq(vehicle.colorTemplate('Транспорт {model}, цвет: {vehicle_color}, район {area}.',{vehicle_color=''}),'Транспорт {model}, район {area}.')
local old=TEST_JSON_DECODE(assert(io.open('presets/pa-settings.json','rb')):read('*a')).settings.data.patrol_session
check(old.start_template:find('начинаем',1,true))
local cfg=assert(prefs.validate(old));check(cfg.start_template:find('{patrol_start}',1,true))
old.start_template='Личный текст: {patrol_start}.';eq(assert(prefs.validate(old)).start_template,old.start_template)
local report=require 'pa26_report_context'
for _,case in ipairs({{nil,'начинаю патруль','1-L-1'},{false,'начинаю патруль','1-L-1'},{true,'начинаем патруль','1-A-1'}})do
 local people=case[1]~=nil and{{id=37,name='Person_Name',verifiedPolice=case[1],ic_name='Имя Напарника'}}or{}
 local v=report.values({inVehicle=true,colleagues={patrolCrew=people,patrolOccupants=2}},{name='Иван Петров',department='EPD'},{})
 eq(v.patrol_start,case[2]);eq(v.unit,case[3])
end
for _,d in ipairs({{1366,768},{1920,1080},{2560,1440}})do
 local w=geometry.rect(d[1],d[2],'assist')
 check(w.x>=16 and w.y>=16 and w.x+w.width<=d[1]-16 and w.y+w.height<=d[2]-16)
 local min=geometry.bounds(d[1],d[2],'assist')
 eq(min.minW,420);eq(min.minH,380)
end
