local fixture=require 'support.fixture';local model=require 'pa26_bindings';local core=require 'pa26_core'
local function click(s,label)s.click=label;s.render();eq(s.click,nil,'Missing ground control: '..label);check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0)end
local lib=model.defaults(core.defaults());lib.procedures.enabled=true;lib.alerts.on_duty=true;lib.alerts.enabled=true
local s=fixture({productionWindows=true,demo=false,library=lib,alerts=true,categoryWheel=true,copilot=true});s.step()
if s.frames[1].condition()then s.commands.pa26();s.step()end
check(s.workspace:selectTarget({id=37,ped=s.mappedPed,name=s.name}));s.step()
local p,why=s.copilot:propose('explain_detention');check(p,why);check(p.navigation);check(not p.prepared)
check(s.copilot:accept(p));s.step();s.step()
check(s.windows['Основание задержания и права##pa26-ground']);check(not s.frames[1].condition());eq(#s.sent,0)
local gf=s.workspace.studio.groundForm;eq(gf.request.groundTarget.id,37)
click(s,'Физическое сопротивление полиции · УК ст. 100##ground-select-resistance')
click(s,'Показать / скрыть точные реплики##ground-preview-toggle')
click(s,'Озвучить и открыть помощник /su##ground-next-wanted')
local proposal=s.workspace.studio.vehicleConfirm;check(proposal);check(proposal.groundData);eq(#s.sent,0)
eq(s.workspace.library.vehicle.copilot.detention_ground,'none','A per-case reason must not rewrite persistent defaults')
click(s,'ДА##confirm-yes')
for i=1,50 do s.step(1600);if s.workspace.studio.caseForm and s.workspace.studio.caseForm.kind=='wanted'then break end end
local wanted=s.workspace.studio.caseForm;check(wanted,table.concat(s.logs,' | '));eq(wanted.kind,'wanted');eq(wanted.reason_id,'08.01')
eq(wanted.mask,'unknown');check(not s.frames[1].condition())
for _,row in ipairs(s.sent)do check(not row.line:match('^/su '),'Handoff opens the assistant and never silently issues wanted stars')end
check(not s.hasLog('Ошибка интерфейса'));eq(s.invalidIOReads,0);onScriptTerminate(s.script)

-- A completed approach creates navigation even with no persistent stop reason.
local V=require 'pa26_vehicle';local C=require 'pa26_copilot';local equal=require('pa26_author_presets').equal
local vehicleCfg=require('pa26_vehicle_settings').defaults();vehicleCfg.approach_distance=10
local car={id=142,handle=100,model_id=560,model_name='Sultan',color1=0,color2=0,x=0,y=2,z=0,distance=2,driver_known=true,driver_ped=200,driver_id=37,occupants=1}
local person={id=37,ped=200,name='Driver_Name',generation=0,distance=2,x=0,y=2,z=0}
local state={session='test',ped=1,alive=true,focused=true,paused=false,blocked=false,onDuty=true,radioEnabled=true,demo=false,inVehicle=false,
 area='Doherty',map_square='J-6',my_nick='Officer_Name',gameHour=12,radioText={split_enabled=true,max_lines=3,continuation='...'}}
local now=1000;local plans={};local profile={name='Officer Name',rank='Сержант',department='SFPS',callsign=''}
local v=V.new({settings=function()return vehicleCfg end,profile=function()return profile end,codec=codec,equal=equal,
 scan=function()return{model.copy(car)}end,resolve=function()return model.copy(car)end,ownCar=function()end,start=function()return true end})
local c=C.new({vehicle=v,settings=function()return vehicleCfg.copilot end,profile=function()return profile end,codec=codec,equal=equal,
 driver=function()return model.copy(person)end,start=function(plan)plans[#plans+1]=plan;return true end})
local function tick()now=now+500;v:tick(state,now);c:tick(state,now)end
tick();check(v:selectNearest());tick()
p=assert(c:propose('approach'));check(c:accept(p));tick();c:onExecution('completed',{plan=plans[1]})
local navigation;for _,offer in ipairs(c.offers)do if offer.action=='explain_stop'then navigation=offer end end
check(navigation);check(navigation.navigation);check(not navigation.prepared);check(c:accept(navigation));eq(#plans,1)
local req=c.groundRequest;check(req);local draft=model.copy(vehicleCfg.copilot);draft.stop_ground='signal';draft.stop_branch='first';draft.ground_ud=true
local g=assert(require('pa26_operational').ground('stop','signal','first'));local cat=require('pa26_sanctions').new(TEST_JSON_DECODE(TEST_KNOWLEDGE_JSON))
require('pa26_sanctions').select(g,cat.byId['AK:41'],1)
p=assert(c:proposeGround(req,draft,g,'fine'));local speech=table.concat(p.prepared.lines,'\n');check(speech:find('/ud 37',1,true));check(speech:find('Предъявите',1,true))
check(c:accept(p));tick();c:onExecution('completed',{plan=plans[2]});check(c.lastStopReason);eq(c.lastStopReason.ground.sanction_id,'AK:41');eq(c.groundHandoff.kind,'fine')
eq(vehicleCfg.copilot.stop_ground,'none');draft.templates.explain_stop='Changed after acceptance';check(not c.lastStopReason.ground.basis:find('Changed',1,true))
person.generation=1;tick();check(not c:groundContextValid(req,true));c:reset('New case');check(not c.lastStopReason)
