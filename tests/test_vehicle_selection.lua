local world=require 'pa26_vehicle_world';local settings=require 'pa26_vehicle_settings';local vehicle=require 'pa26_vehicle';local model=require 'pa26_bindings'
local origin={x=0,y=0,z=0};local forward={x=0,y=1}
eq(world.angle(origin,forward,{x=0,y=10,z=0},65,8),0)
check(not world.angle(origin,forward,{x=0,y=-10,z=0},65,8));check(not world.angle(origin,forward,{x=10,y=0,z=0},65,8))
check(not world.angle(origin,forward,{x=0,y=10,z=9},65,8));check(world.angle(origin,forward,{x=0,y=10,z=100},65,0))
check(not world.angle(origin,{x=0,y=0},{x=0,y=1,z=0},65,8))
for degree=-180,180 do
    local a=math.rad(degree);local point={x=math.sin(a)*20,y=math.cos(a)*20,z=0}
    local found=world.angle(origin,forward,point,65,8)
    eq(found~=nil,math.abs(degree)<=65)
    if found then check(math.abs(found-math.abs(degree))<.00001)end
end
local cfg=settings.defaults();eq(cfg.height_tolerance,15,'Default tolerates hills while filtering other floors');cfg.height_tolerance=8;cfg.close_radius=0
local own=100;local backwardsCamera=false;local missing=false
local cars={[10]={x=1,y=15,z=0},[20]={x=0,y=25,z=0},[30]={x=0,y=-5,z=0},[40]={x=0,y=10,z=15},[50]={x=15,y=0,z=0},[100]=origin}
local calls={}
local funcs={doesCharExist=function()return true end,getCharCoordinates=function()return 0,0,0 end,isCharInAnyCar=function()return own~=nil end,storeCarCharIsInNoSave=function()return own end,
    doesVehicleExist=function(h)return cars[h]~=nil end,getAllVehicles=function()return{10,20,30,40,50,100}end,
    sampGetVehicleIdByCarHandle=function(h)return true,h end,sampGetCarHandleBySampVehicleId=function(id)return true,id end,
    getCarCoordinates=function(h)local c=cars[h];return c.x,c.y,c.z end,getCarModel=function()return 597 end,getCarColours=function()return 0,1 end,
    isCarOnScreen=function()return true end,isLineOfSightClear=function()return true end,getDriverOfCar=function()return 1 end,
    getOffsetFromCarInWorldCoords=function()if not missing then return 0,1,0 end end,
    getActiveCameraCoordinates=function()if not missing then return 0,0,0 end end,
    getActiveCameraPointAt=function()if not missing then return 0,backwardsCamera and -1 or 1,0 end end,
    sampGetPlayerIdByCharHandle=function()return true,37 end,sampGetCharHandleBySampPlayerId=function()return true,1 end,
    sampIsPlayerConnected=function()return true end,sampIsPlayerNpc=function()return false end,sampGetPlayerNickname=function()return'Driver_Name'end}
local api=world.new(function(n,...)calls[n]=(calls[n]or 0)+1;if funcs[n]then return funcs[n](...)end end,codec,function()return 1 end)
local function ids(rows)local t={};for _,r in ipairs(rows)do t[r.id]=true end;return t end
local rows=api.scan(cfg);local found=ids(rows);check(found[10]and found[20]);check(not found[30]and not found[40]and not found[50]and not found[100])
eq(calls.getCharCoordinates,1,'One origin sample per scan')
backwardsCamera=true;found=ids(api.scan(cfg));check(found[10]and found[30],'Auto accepts either cruiser or camera cone')
cfg.selection_mode='camera';found=ids(api.scan(cfg));check(found[30]and not found[10],'Explicit camera cone follows camera')
cfg.selection_mode='auto';own=nil;found=ids(api.scan(cfg));check(found[30]and not found[10],'On foot auto follows camera')
cfg.selection_mode='vehicle';eq(#api.scan(cfg),0,'Strict vehicle mode needs a known own car')
own=100;missing=true;eq(#api.scan(cfg),0,'Unknown direction cannot silently select in strict mode')
cfg.selection_mode='auto';found=ids(api.scan(cfg));check(found[10]and found[30]);check(api.status():find('недоступно',1,true))
cfg.selection_mode='screen';cfg.height_tolerance=0;found=ids(api.scan(cfg));check(found[40]);check(found[50])
missing=false;backwardsCamera=false;cfg=settings.defaults();cfg.close_radius=0;rows=api.scan(cfg)
-- Enable the optional height filter for the directional ranking example.
cfg.height_tolerance=8;rows=api.scan(cfg)
local state={session='test',ped=1,alive=true,focused=true,paused=false,onDuty=true,radioEnabled=true}
cfg.enabled=true
local controller=vehicle.new({settings=function()return cfg end,scan=function()return model.copy(rows)end,resolve=function(c)return c end,ownCar=function()end})
controller:tick(state,1000);eq(controller:view().nearest.id,20,'Central candidate wins over nearer side candidate')
cfg.selection_ranking='distance';controller:tick(state,1500);eq(controller:view().nearest.id,10)
for _,bad in ipairs({'unknown','',false})do local c=settings.defaults();c.selection_mode=bad;check(not settings.validate(c))end
for _,field in ipairs({'cone_angle','height_tolerance'})do local c=settings.defaults();c[field]=0/0;check(not settings.validate(c))end
local personal=settings.defaults();personal.traffic_stop_template='Мой текст {area}.';personal.selection_mode=nil;personal.selection_ranking=nil;personal.cone_angle=nil;personal.height_tolerance=nil
local upgraded=assert(settings.validate(personal));eq(upgraded.traffic_stop_template,personal.traffic_stop_template);eq(upgraded.selection_mode,'auto')
local f=require('support.fixture')({demo=false});f.step();f.page('partners');f.click='Транспорт##Напарники и служба##partners-pagevehicle';f.render();eq(f.click,nil)
local originalSlider=f.imgui.SliderInt;local visited={}
f.imgui.SliderInt=function(label,value,minimum,maximum)
    if label=='##vehicle-cone_angle'then value[0]=42;visited.angle=true;return true end
    if label=='##vehicle-height_tolerance'then value[0]=8;visited.height=true;return true end
    return originalSlider(label,value,minimum,maximum)
end
f.render();f.imgui.SliderInt=originalSlider;f.step(700)
check(visited.angle and visited.height);eq(f.workspace.library.vehicle.cone_angle,42);eq(f.workspace.library.vehicle.height_tolerance,8)
local saved=f.savedLibrary();eq(saved.vehicle.cone_angle,42);eq(saved.vehicle.height_tolerance,8)
eq(f.vehicleController.env.settings().cone_angle,42,'Saved GUI values must reach the live selector');eq(#f.sent,0);check(not f.hasLog('Ошибка интерфейса'));eq(#f.scopes,0)
onScriptTerminate(f.script)
