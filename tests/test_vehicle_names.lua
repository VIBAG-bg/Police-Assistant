local names=require 'pa26_vehicle_names'
local core=require 'pa26_core'
local world=require 'pa26_vehicle_world'
local prefs=require 'pa26_vehicle_settings'
local vehicle=require 'pa26_vehicle'
local count=0;for key,name in pairs(names)do
    count=count+1;check(key>=400 and key<=611 and key==math.floor(key));check(core.validUtf8(name));check(not name:find('[^%w%s%p]'))
end;eq(count,212);eq(names[411],'Infernus');eq(names[490],'FBI Rancher');eq(names[597],'Police SF');eq(names[611],'Utility Trailer')
local id=400;local gxtReads=0
local api={doesCharExist=function()return true end,isCharInAnyCar=function()return false end,
    getCharCoordinates=function()return 0,0,0 end,doesVehicleExist=function()return true end,
    sampGetVehicleIdByCarHandle=function()return true,105 end,sampGetCarHandleBySampVehicleId=function()return true,20 end,
    getCarCoordinates=function()return 0,5,0 end,getCarModel=function()return id end,getCarColours=function()return 1,0 end,
    getAllVehicles=function()return {20}end,getDriverOfCar=function()return 99 end,isCarOnScreen=function()return true end,
    isLineOfSightClear=function()return true end}
local w=world.new(function(name,...)
    if name=='getGxtText'or name=='getNameOfVehicleModel'then gxtReads=gxtReads+1;return '\255\254Иероглифы' end
    if api[name]then return api[name](...)end
end,{decode=function()error('GXT must not be decoded as CP1251')end},function()return 1 end)
local cfg=prefs.defaults()
for modelId=400,611 do id=modelId;local rows=w.scan(cfg);eq(#rows,1);eq(rows[1].model_name,names[modelId])end
eq(gxtReads,0,'Font-encoded GXT must never reach a vehicle label')
for _,bad in ipairs({399,612,411.5,0/0,math.huge})do id=bad;eq(#w.scan(cfg),0)end
id=411;local c=w.scan(cfg)[1];cfg.model_aliases['411']='Мой Infernus';local value=assert(vehicle.describe(c,cfg));eq(value.model,'Мой Infernus')
eq(c.model_name,'Infernus','A personal alias does not mutate native identity')
