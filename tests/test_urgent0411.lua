-- Regression cases for the reported live 0.41.0 defects, with no game writes.
local core=require 'pa26_core';local model=require 'pa26_bindings';local prefs=require 'pa26_vehicle_settings'
local grid=require 'pa26_map_grid';local hud=require 'pa26_hud';local bridge=require 'pa26_chat_bridge'
local equal=require('pa26_author_presets').equal
for _,row in ipairs({{1500,-1500,'Лос-Сантос'},{-2000,100,'Сан-Фиерро'},{2000,2000,'Лас-Вентурас'},
 {500,200,'Ред-Каунти'},{-700,-1800,'Флинт-Каунти'},{-2500,-2000,'Уэтстоун'},{0,2000,'Боун-Каунти'},{-2000,2200,'Тьерра-Робада'},
 {-1000,1000,'Тьерра-Робада'},{-1100,-700,'Сан-Фиерро','SFAIR'},{-1150,-1000,'Сан-Фиерро','SILLY1'}})do
 eq(hud.cityName(row[1],row[2],10,row[4]),row[3])
 local values=grid.values(grid.defaults(),{city='Мой город'},row[1],row[2],0,10,row[4]);eq(values.city,row[3])
end
check(not hud.cityName(0/0,0,0));check(not hud.cityName(4000,4000,0))
local map=grid.defaults();map.auto_city=false;eq(grid.values(map,{city='Своя метка'},1500,-1500,0,0).city,'Своя метка')
eq(grid.values(map,{city=''},1500,-1500,0,0).city,'Лос-Сантос');check(not grid.values(grid.defaults(),{},1500,-1500,1,0).city)
check(not grid.validate((function()local c=grid.defaults();c.auto_city='yes';return c end)()))
local cfg=prefs.defaults();eq(cfg.radius,60);eq(cfg.height_tolerance,15);check(cfg.sync_driver_target and cfg.occupied_priority and cfg.occupied_only);eq(cfg.copilot_migrated,2)
local legacy=model.copy(cfg);legacy.copilot_migrated=nil;legacy.enabled=false;legacy.megaphone_enabled=false;legacy.require_patrol=true;legacy.occupied_only=true;legacy.radius=40;legacy.cone_angle=65;legacy.height_tolerance=0
local migrated=assert(prefs.validate(legacy));check(migrated.enabled and migrated.megaphone_enabled and not migrated.require_patrol and migrated.occupied_only);eq(migrated.radius,60);eq(migrated.copilot_migrated,2)
migrated.enabled=false;migrated.megaphone_enabled=false;migrated.occupied_only=true;migrated.radius=13
local personal=assert(prefs.validate(migrated));check(not personal.enabled and not personal.megaphone_enabled and personal.occupied_only);eq(personal.radius,13)
legacy.radius=29;local custom=assert(prefs.validate(legacy));check(not custom.enabled);eq(custom.radius,29)
for _,n in ipairs({4,151,0/0,math.huge})do local c=prefs.defaults();c.radius=n;check(not prefs.validate(c))end
for _,n in ipairs({5,60,150})do local c=prefs.defaults();c.radius=n;check(prefs.validate(c))end
local patrol=require 'pa26_patrol_settings';local cpPrefs=require 'pa26_copilot_settings'
local old=patrol.defaults();old.radio_templates_version=nil;old.start_template='{local_tag}{unit}: начинаю патрулирование. Экипаж: {crew}. 10-20: {area}.'
local fresh=assert(patrol.validate(old));check(fresh.start_template:find('{city}',1,true))
old.start_template='Личный доклад {unit}.';eq(assert(patrol.validate(old)).start_template,old.start_template)
old.radio_templates_version=1;old.start_template='{local_tag}{unit}: начинаю патрулирование. Экипаж: {crew}. 10-20: {area}.';eq(assert(patrol.validate(old)).start_template,old.start_template)
local oldcp=cpPrefs.defaults();oldcp.radio_templates_version=nil;oldcp.templates.stop='{local_tag}{unit}, провожу остановку {vehicle_description} в районе {area} ({map_square}), {occupants_text}, Код 4.'
check(assert(cpPrefs.validate(oldcp)).templates.stop:find('{city}',1,true));oldcp.templates.stop='Мой доклад.';eq(assert(cpPrefs.validate(oldcp)).templates.stop,'Мой доклад.')
for _,r in ipairs(cpPrefs.templates)do check(cpPrefs.validate({templates={[r[1]]=cpPrefs.defaults().templates[r[1]]}}))end
local world=require 'pa26_vehicle_world';local cars,own,camera,clear,losCalls={},100,{0,-4,2,0,50,2},true,0
local funcs={doesCharExist=function(p)return p==1 or p==300 end,getCharCoordinates=function()return 0,0,0 end,
 isCharInAnyCar=function()return own~=nil end,storeCarCharIsInNoSave=function()return own end,doesVehicleExist=function(h)return h==100 or cars[h]~=nil end,
 getAllVehicles=function()local out={100};for h in pairs(cars)do out[#out+1]=h end;return out end,
 sampGetVehicleIdByCarHandle=function(h)return true,h end,sampGetCarHandleBySampVehicleId=function(h)return true,h end,
 getCarCoordinates=function(h)if h==100 then return 0,0,0 end;local c=cars[h];return c.x,c.y,c.z end,
 getCarModel=function()return 560 end,getCarColours=function()return 0,1 end,
 isCarOnScreen=function(h)return cars[h]and cars[h].screen~=false end,
 isLineOfSightClear=function(...)local a={...};eq(select('#',...),11);eq(a[7],true);for i=8,11 do eq(a[i],false)end;losCalls=losCalls+1;return clear end,
 getOffsetFromCarInWorldCoords=function()return 0,1,0 end,getActiveCameraCoordinates=function()return unpack(camera,1,3)end,getActiveCameraPointAt=function()return unpack(camera,4,6)end,
 getDriverOfCar=function(h)return cars[h]and cars[h].driver or 0 end,getNumberOfPassengers=function(h)return cars[h]and cars[h].passengers or 0 end,
 sampGetPlayerIdByCharHandle=function()return true,37 end,sampGetCharHandleBySampPlayerId=function()return true,300 end,
 sampIsPlayerConnected=function()return true end,sampIsPlayerNpc=function()return false end,sampGetPlayerNickname=function()return'Driver_Name'end}
local api=world.new(function(name,...)if funcs[name]then return funcs[name](...)end end,codec,function()return 1 end)
cfg.occupied_only=false -- Geometry cases deliberately exercise the optional all-car mode.
for _,distance in ipairs({0,1,2,5,10,15})do for _,deg in ipairs({-180,-90,0,90,180})do
 local a=math.rad(deg);cars={[11]={x=math.sin(a)*distance,y=math.cos(a)*distance,z=0}};eq(#api.scan(cfg),1,'Close visible car at any angle')
end end
cars={[11]={x=0,y=60,z=0},[12]={x=60,y=0,z=0}};camera={0,-4,2,50,-4,2};eq(#api.scan(cfg),2,'Camera OR cruiser cone reaches 60m')
cars={[11]={x=0,y=61,z=0}};eq(#api.scan(cfg),0)
cars={[11]={x=0,y=5,z=16}};eq(#api.scan(cfg),0,'Other floor excluded');cfg.height_tolerance=0;eq(#api.scan(cfg),1);cfg.height_tolerance=15
cars={[11]={x=1,y=1,z=0}};clear=false;eq(#api.scan(cfg),0,'Known building obstruction remains blocked even close')
clear=nil;eq(#api.scan(cfg),1,'Unavailable LOS has bounded near fallback');cars[11].y=20;eq(#api.scan(cfg),0);clear=true
cars={[11]={x=0,y=20,z=0,passengers=1}};cfg.occupied_only=true;eq(#api.scan(cfg),0,'A passenger cannot substitute for a player driver');cars[11].passengers=0;eq(#api.scan(cfg),0);cfg.occupied_only=false;eq(#api.scan(cfg),1)
cars[11].screen=false;eq(#api.scan(cfg),0);check(losCalls>0)
local V=require 'pa26_vehicle';local state={session='s',ped=1,alive=true,focused=true,onDuty=true,radioEnabled=true,inVehicle=true,area='Ganton',city='Лос-Сантос',map_square='H-7',my_nick='Officer_Name',radioText={split_enabled=true,max_lines=6,continuation='...'}}
local rows={{id=11,handle=11,model_id=560,model_name='Sultan',distance=30,angle=0,occupants=1,driver_id=37,driver_ped=300,driver_name='Driver_Name',x=0,y=30,z=0,color1=0,color2=1},
 {id=12,handle=12,model_id=541,distance=5,angle=90,occupants=0,x=5,y=0,z=0,color1=0,color2=0}}
local target,rev,syncs,scans=nil,0,0,0
local driver={id=37,ped=300,name='Driver_Name',generation=0,alive=true,connected=true}
local v=V.new({settings=function()return cfg end,profile=function()return{}end,codec=codec,equal=equal,
 scan=function()scans=scans+1;return model.copy(rows)end,resolve=function(c)for _,r in ipairs(rows)do if r.id==c.id then return model.copy(r)end end end,
 driver=function(id)return id==37 and model.copy(driver)or nil end,currentTarget=function()return target,rev end,
 selectTarget=function(t)target=model.copy(t);rev=rev+1;syncs=syncs+1;return true end,ownCar=function()return nil end})
local now=1000;local function tick(dt)now=now+(dt or 300);v:tick(state,now)end
tick();eq(v.candidates[1].id,12,'Immediate empty car wins over much farther occupant');rows[2].distance=10;tick();eq(v.candidates[1].id,11,'Otherwise prefer occupied')
check(v:requestSelection(11));eq(syncs,0,'UI intent performs no native selection');local before=scans;tick(1);check(scans>before);eq(target.id,37);eq(syncs,1)
for _=1,8 do tick()end;eq(syncs,1,'Same driver must not bump target revision each tick')
target={id=20,ped=400,name='Manual_Person'};rev=rev+1;tick();eq(target.id,20,'Manual target remains authoritative in background')
check(v:requestSelection(11));tick();eq(target.id,37,'Explicit car selection rebinds driver')
cfg.sync_driver_target=false;target=nil;tick();check(not target);cfg.sync_driver_target=true
driver.name='Reused_Id';target=nil;tick();check(not target,'Driver name mismatch prevents stale ID reuse')
driver.name='Driver_Name';tick();eq(target.id,37)
v.candidates={};local n=scans;check(v:selectNearest(true));eq(scans,n+1,'On-demand main scan fills empty cache')
check(v:requestSelection(11));state.session='new';tick();check(not v.selected,'Old selection request cannot cross reconnect');state.session='s';tick()
-- Manual radio reports with no vehicle still use the same frozen executor plan.
local cpModule=require 'pa26_copilot';local plans={};v.selected=nil;v.candidates={};rows={}
local cp=cpModule.new({vehicle=v,settings=function()return cfg.copilot end,profile=function()return{name='Officer Name',callsign='',department='',gender='female'}end,codec=codec,equal=equal,driver=function()return driver end,start=function(p)plans[#plans+1]=p;return true end})
state.gender='female';state.colleagues={autoCallsign='1-L-1',station='LSPS',nearbyOfficers={},nearbyCruisers=0,ownCruiserRole='solo'}
cp:tick(state,now);check(not cp:view().visible,'New default hides idle on-duty card');cfg.copilot.always_show_on_duty=true;check(cp:view().visible,'Saved user opt-in still shows idle on-duty card');eq(cp:view().statusCode,4)
for _,action in ipairs({'call911','arrived','break_report'})do
 local proposal,err=cp:propose(action);check(proposal,err);check(proposal.carFree and proposal.car==nil);check(cp:accept(proposal));local prior=#plans;cp:tick(state,now+1);eq(#plans,prior+1)
 check(cp:validPlan(plans[#plans]));cp:onExecution('completed',{plan=plans[#plans]});check(not cp.phase,'Quick report must not start traffic stop')
end
check(cp:propose('lost'),'Lost report uses an editable vehicle fallback');state.inVehicle=false;cp:tick(state,now+2);check(not cp:view().visible);state.patrolActive=true;cp:tick(state,now+3);check(cp:view().visible,'Foot patrol card');state.patrolStatus='paused';cp:tick(state,now+4);check(cp:view().statusTitle:find('ПАУЗА',1,true))
cfg.copilot.hud=false;check(not cp:view().visible);cfg.copilot.hud=true;state.focused=false;cp:tick(state,now+5);check(not cp:view().visible);state.focused=true
-- Weapon guard does not consume text, system key messages or unrelated keys.
for _,message in ipairs({0x100,0x101})do for _,key in ipairs({0x30,0x39,0x60,0x69,0x51,0x45})do check(bridge.weaponKey(message,key))end end
for _,message in ipairs({0x102,0x104,0x105})do check(not bridge.weaponKey(message,0x31))end
check(not bridge.weaponKey(0x100,0x41))
local b=bridge.new({settings=function()return{enabled=true}end});b:observeInput(0x100,0x75,1000,true);check(b:inputBusy(1349,350));check(not b:inputBusy(1350,350))
b:observeInput(0x100,0x54,1400,false);check(not b:inputBusy(1401,350));b:observeInput(0x100,0x54,1500,true);b:observeInput(0x100,13,1501,false);check(not b:inputBusy(1502,350))
local fixture=require 'support.fixture';local f=fixture({demo=false});f.step();if f.frames[1].condition()then f.commands.pa26();f.step()end
local restores=0;setCurrentCharWeapon=function(ped,w)check(not f.rendererContext);eq(ped,PLAYER_PED);f.weapon=w;restores=restores+1 end
f.weapon=24;f.step();f.chatBridge.server={accept=function()return nil,'timeout'end,close=function()end}
onWindowMessage(0x100,0x75);local consumed=f.consumed;onWindowMessage(0x100,0x31);check(f.consumed>consumed)
consumed=f.consumed;onWindowMessage(0x102,0x31);eq(f.consumed,consumed,'WM_CHAR must reach CEF')
f.weapon=25;f.step();eq(f.weapon,24);eq(restores,1)
f.step(400);consumed=f.consumed;onWindowMessage(0x100,0x32);eq(f.consumed,consumed,'Grace expires')
onWindowMessage(0x101,0x31);check(f.consumed>consumed,'A held key release remains consumed after grace')
f.workspace.library.settings.cef_chat_weapon_guard=false;onWindowMessage(0x100,0x75);consumed=f.consumed;onWindowMessage(0x100,0x33);eq(f.consumed,consumed)
f.workspace.library.settings.cef_chat_weapon_lock=false;f.chat=true;f.weapon=27;f.step();eq(f.weapon,27)
check(not f.hasLog('Ошибка интерфейса'));onScriptTerminate(f.script)
-- Auto city reaches live bind snapshots and is retained only inside this
-- connection's interior. Explicit manual city remains editable and effective.
f=fixture({demo=false});f.step();getCharActiveInterior=function()return 0 end
getCharCoordinates=function(ped)if ped==PLAYER_PED then return 1500,-1500,10 end;return 1,1,0 end
f.step();local binding=model.newBinding(88);binding.script='{city}'
local snap=assert(f.workspace:snapshot(binding,{}));eq(snap.values.city,'Лос-Сантос')
getCharActiveInterior=function()return 1 end;getCharCoordinates=function()return 2000,2000,10 end;f.step()
snap=assert(f.workspace:snapshot(binding,{}));eq(snap.values.city,'Лос-Сантос','Interior does not mistake interior coordinates for LV')
f.workspace.library.map_grid.auto_city=false;f.workspace.library.profile.city='Свой город';f.step();snap=assert(f.workspace:snapshot(binding,{}));eq(snap.values.city,'Свой город')
check(not f.hasLog('Ошибка интерфейса'));onScriptTerminate(f.script)
local colleagues=require 'pa26_colleagues';local radarCfg=cpPrefs.defaults();local skins={[1]=281,[2]=280,[3]=280,[4]=100}
local natives={storeCarCharIsInNoSave=function()return 101 end,isCharInAnyCar=function()return true end,doesVehicleExist=function()return true end,getDriverOfCar=function(h)return h-100 end,
 getNumberOfPassengers=function()return 1 end,getCharModel=function(p)return skins[p]end,getCharCoordinates=function()return 0,0,0 end,
 getCharActiveInterior=function()return 0 end,getAllChars=function()return{1,2,3,4}end,doesCharExist=function()return true end,isCharDead=function()return false end,
 sampGetPlayerIdByCharHandle=function(p)return true,p end,sampGetCharHandleBySampPlayerId=function(p)return true,p end,
 sampIsPlayerConnected=function()return true end,sampIsPlayerNpc=function()return false end,sampGetPlayerNickname=function(p)return'Officer_'..p end,
 getAllVehicles=function()return{101,102,103,104}end,getCarCoordinates=function()return 0,5,0 end,getCarModel=function(h)return h==102 and 560 or 541 end}
local radar=colleagues.new({settings=function()return radarCfg end,read=function(k,...)if natives[k]then return natives[k](...)end end,profile=function()return{department='',callsign=''}end,partners=function()return{}end})
state.inVehicle=true;radar:tick(state,1000);local view=radar:view();eq(view.nearbyCruisers,3,'PD Sultan/Bullet included; civilian Bullet excluded');eq(view.station,'LSPS');eq(view.ownCruiserRole,'driver');eq(view.autoCallsign,'1-A-1')
eq(colleagues.callsign({department='SFPS'},281,1),'2-L-1');eq(colleagues.callsign({department='LVPS'},282,1),'3-L-1');eq(colleagues.callsign({department='EPD'},281,1),'1-L-1')
radarCfg.colleagues_enabled=false;radar:tick(state,2000);eq(radar:view().ownCruiserRole,'driver','Own role works even when the radar is disabled')
-- New default start report is usable with ordinary limits and unknown place
-- fields, and preserves all words through the normal radio splitter.
local session=require('pa26_patrol_session').new({profile=function()return{name='Иван Петров',rank='Сержант'}end,codec=codec})
local record={officer='Иван Петров',callsign='',station='LSPS',unit='1-L-1',vehicle='',sector='',post='',crew={},elapsed_ms=0,id=1}
local ps={area='Ganton',local_tag='[EPD]',city='Лос-Сантос',direction='Север',map_square='H-7',radioText={split_enabled=true,max_lines=3,continuation='...'}}
local prepared,why=session:prepareLine('start',record,ps,patrol.defaults());check(prepared,why);check(#prepared.lines<=3)
for _,line in ipairs(prepared.lines)do check(#assert(codec.encode(line))<=127)end
