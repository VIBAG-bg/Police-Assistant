local module=require 'pa26_colleagues';local prefs=require 'pa26_copilot_settings';local core=require 'pa26_core'
local copy=require('pa26_bindings').copy
local cfg=prefs.defaults();check(prefs.validate(cfg));check(not prefs.validate({skin_ids='280,../1'}));check(not prefs.validate({scan_ms=0}))
local skins={300,301,267,280,281,282,283,284,285,288,295,211,265,266,306,307};local total=0
for _ in pairs(module.pdSkins)do total=total+1 end;eq(total,16)
for _,id in ipairs(skins)do check(module.pdSkins[id].label);check(module.pdSkins[id].station)end
eq(module.callsign({department='LSPS'},280,1),'1-L-1');eq(module.callsign({department='SFPS'},281,2),'2-A-1')
eq(module.callsign({},285,1),'DAVID-1');eq(module.callsign({callsign='CUSTOM'},285,2),'CUSTOM')
local mode,role,n=module.role(true,true,1);eq(mode,'ADAM');eq(role,'driver');eq(n,2)
mode,role=module.role(true,false,1);eq(mode,'ADAM');eq(role,'navigator')
mode,role=module.role(true,true,0);eq(mode,'LINCOLN');eq(role,'solo');check(not module.role(false))
local s={session='s',ped=1,alive=true,onDuty=true,inVehicle=true};local peds={1,2,3,4};local model=280
local api={getCharCoordinates=function(p)return 0,p==4 and 100 or 3,0 end,getCharActiveInterior=function()return 0 end,
 getAllChars=function()return peds end,doesCharExist=function()return true end,isCharDead=function()return false end,
 sampGetPlayerIdByCharHandle=function(p)return true,p+10 end,sampGetCharHandleBySampPlayerId=function(id)return true,id-10 end,
 sampIsPlayerConnected=function()return true end,sampIsPlayerNpc=function()return false end,sampGetPlayerNickname=function(id)return({[12]='Radio_Partner',[13]='Third_Officer',[14]='Far_Officer'})[id]end,
 getCharModel=function(p)return p==2 and model or 281 end,getAllVehicles=function()return{50,51,51}end,doesVehicleExist=function()return true end,
 getCarModel=function()return 597 end,getCarCoordinates=function()return 0,5,0 end,getDriverOfCar=function(car)return car==50 and 1 or nil end,
 storeCarCharIsInNoSave=function()return 50 end,getNumberOfPassengers=function()return 1 end}
local radar=module.new({settings=function()return cfg end,read=function(k,...)if api[k]then return api[k](...)end end,profile=function()return{department='SFPS',callsign=''}end,partners=function()return{}end})
radar:tick(s,0);local v=radar:view();eq(#v.nearbyOfficers,2);eq(v.nearbyCruisers,1);eq(v.ownCruiserRole,'driver')
for _,skin in ipairs(skins)do model=skin;radar:tick(s,skin*1000);eq(#radar:view().nearbyOfficers,2)end
model=10;radar:observe('[R] Radio_Partner[12]: На связи.');radar:tick(s,400000);eq(#radar:view().nearbyOfficers,2)
radar:observe('[F] New_Partner[20]: На связи.');check(radar.knownColleagues.new_partner)
radar:observe('Обычный текст Fake_Officer[33]: [R]');check(not radar.knownColleagues.fake_officer)
radar:observe('- Unknown_Name(32) [Телефон: 123]');check(radar.findNames.unknown_name);check(not radar.knownColleagues.unknown_name)
s.session='new';radar:tick(s,401000);check(not next(radar.knownColleagues));eq(#radar:view().nearbyOfficers,1)
api.sampIsPlayerNpc=function()return true end;radar:tick(s,402000);eq(#radar:view().nearbyOfficers,0)
check(module.guard(cfg,'Ganton',2,false));check(not module.guard(cfg,'Ganton',3,false));check(not module.guard(cfg,'Ganton',1,true));check(not module.guard(cfg,'Doherty',1,false))
local t=core.moscowTime(0);eq(t.hour,3);eq(t.day,1)
local raw=copy(cfg);raw.enabled=false;raw.templates.stop='Мой текст.';local validated=assert(prefs.validate(raw));check(not validated.enabled);eq(validated.templates.stop,'Мой текст.')
