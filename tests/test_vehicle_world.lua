local world=require 'pa26_vehicle_world'
local cfg=require('pa26_vehicle_settings').defaults()
local calls={};local missing,own,wall,visible,badMap=false,nil,false,true,false
local functions={doesCharExist=function()return true end,getCharCoordinates=function()return 0,0,0 end,
    isCharInAnyCar=function()return own~=nil end,storeCarCharIsInNoSave=function()return own end,
    doesVehicleExist=function(h)return h==10 or h==20 end,getAllVehicles=function()return {10,20,10,0/0}end,
    sampGetVehicleIdByCarHandle=function(h)return true,h+100 end,sampGetCarHandleBySampVehicleId=function(id)return true,badMap and 123 or id-100 end,
    getCarCoordinates=function(h)return 0,h,0 end,getCarModel=function(h)return h==10 and 411 or 597 end,getDriverOfCar=function()return 99 end,
    isCarOnScreen=function()return visible end,isLineOfSightClear=function()return not wall end,
    getCarColours=function()return 1,0 end,getNameOfVehicleModel=function()return 'INFERNUS'end,
    getGxtText=function()return 'Infernus'end}
local api=world.new(function(name,...)calls[name]=(calls[name]or 0)+1;if not missing and functions[name]then return functions[name](...)end end,codec,function()return 1 end)
local cars=api.scan(cfg);eq(#cars,2);eq(cars[1].id,110);eq(cars[1].model_name,'Infernus');eq(cars[1].color2,0)
check(calls.sampGetCarHandleBySampVehicleId>0,'Every native handle is cross-checked against its SA:MP ID')
own=10;eq(#api.scan(cfg),1);eq(api.ownCar().handle,10);own=nil
wall=true;eq(#api.scan(cfg),0);wall=false;visible=false;eq(#api.scan(cfg),0);visible=true
badMap=true;eq(#api.scan(cfg),0);badMap=false
cfg.radius=5;eq(#api.scan(cfg),0);cfg.radius=40
local old=cars[1];check(api.resolve(old,cfg));functions.doesVehicleExist=function()return false end;check(not api.resolve(old,cfg))
missing=true;eq(#api.scan(cfg),0);check(not api.ownCar())
