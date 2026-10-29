local settings=require 'pa26_patrol_settings';local Session=require 'pa26_patrol_session'
local model=require 'pa26_bindings';local core=require 'pa26_core';local equal=require('pa26_author_presets').equal
local cfg=settings.defaults();cfg.enabled=true;cfg.unit_number=9
local profile={name='Victor Auditore',callsign='PERSONAL',department='SFPS',gender='male'}
local s={session='one',ped=1,alive=true,focused=true,paused=false,blocked=false,onDuty=true,radioEnabled=true,demo=false,
 local_nick='Victor_Auditore',inVehicle=true,gender='male',area='Doherty',city='Сан-Фиерро',map_square='J-6',direction='Север',
 radioText={split_enabled=true,max_lines=3,continuation='...'},colleagues={patrolOccupants=1,skin=281,station='SFPS'}}
local session=Session.new({settings=function()return cfg end,profile=function()return profile end,contacts=function()return{}end,
 codec=codec,equal=equal,resolve=function()end,observe=function()end,start=function()return true end})
session:tick(s,1000)
local p,err=session:propose('start');check(p,err)
eq(p.record.unit,'2-L-9');check(p.record.unit_auto)
local lines=table.concat(p.prepared.lines,' ')
check(lines:find('начинаю патруль',1,true));check(lines:find('доступен',1,true))
check(not lines:find('PERSONAL',1,true),'Personal callsign is not silently treated as the automatic unit')
s.colleagues.patrolOccupants=3;session:tick(s,1200);check(not session:proposalValid(p),'Partner change requires a fresh confirmation')
p=assert(session:propose('start'));eq(p.record.unit,'2-A-9')
lines=table.concat(p.prepared.lines,' ');check(lines:find('начинаем патруль',1,true));check(lines:find('доступны',1,true));check(lines:find('двигаемся',1,true))
s.colleagues.patrolOccupants=1;s.gender='female';session:tick(s,1400)
p=assert(session:propose('start'));check(table.concat(p.prepared.lines,' '):find('доступна',1,true))
cfg.unit='3-ADAM-17';session:tick(s,1600);p=assert(session:propose('start'));eq(p.record.unit,'3-ADAM-17');check(not p.record.unit_auto)
cfg.unit='';s.colleagues={};session:tick(s,1800);p=assert(session:propose('start'));eq(p.record.unit,'2-L-9')
cfg.grammar.available_solo='готова к вызовам';session:tick(s,2000)
p=assert(session:propose('start'));check(table.concat(p.prepared.lines,' '):find('готова к вызовам',1,true))
local own=settings.defaults();own.start_template='Моя личная реплика {unit}.';own.unit='Мой юнит';own.unit_number=17
local valid=assert(settings.validate(own));eq(valid.start_template,own.start_template);eq(valid.unit,'Мой юнит');eq(valid.unit_number,17)
local old=settings.defaults();old.grammar=nil;old.unit_number=nil
valid=assert(settings.validate(old));eq(valid.unit_number,1);check(valid.grammar.start_team)
for _,n in ipairs({0,1000,0/0})do local bad=model.copy(cfg);bad.unit_number=n;check(not settings.validate(bad))end
local bad=model.copy(cfg);bad.grammar.available_solo='/r\nошибка';check(not settings.validate(bad))

-- Only identified colleagues in the same car contribute to automatic ADAM.
local radarModule=require 'pa26_colleagues';local radarCfg=require('pa26_copilot_settings').defaults()
local cars={[1]=50,[2]=50,[3]=50,[4]=50,[5]=51,[6]=50}
local skins={[1]=281,[2]=281,[3]=10,[4]=10,[5]=280,[6]=280}
local people={1,2,3,4,5,6,2}
local passengers=4
local partners={{nickname='Contact_Partner'}}
local api={
 storeCarCharIsInNoSave=function(p)return cars[p]end,isCharInAnyCar=function(p)return cars[p]~=nil end,
 doesVehicleExist=function()return true end,getDriverOfCar=function()return 1 end,getNumberOfPassengers=function()return passengers end,
 getCharModel=function(p)return skins[p]end,getAllChars=function()return people end,doesCharExist=function()return true end,
 isCharDead=function(p)return p==6 end,sampGetPlayerIdByCharHandle=function(p)return true,p+10 end,
 sampGetCharHandleBySampPlayerId=function(id)return true,id-10 end,sampIsPlayerConnected=function()return true end,sampIsPlayerNpc=function()return false end,
 sampGetPlayerNickname=function(id)return({[12]='Uniform_Partner',[13]='Contact_Partner',[14]='Civilian_Passenger',[15]='Other_Car',[16]='Dead_Officer'})[id]end,
 getCharCoordinates=function()return 0,0,0 end,getCharActiveInterior=function()return 0 end,getAllVehicles=function()return{}end}
local radar=radarModule.new({read=function(k,...)if api[k]then return api[k](...)end end,settings=function()return radarCfg end,
 profile=function()return profile end,partners=function()return partners end})
s.ped=1;s.onDuty=true;s.inVehicle=true;radar:tick(s,1000)
local view=radar:view();eq(view.patrolOccupants,3);eq(view.unitAuto,'2-A-1')
cars[2]=51;cars[3]=nil;passengers=1;radar:tick(s,1001)
view=radar:view();eq(view.patrolOccupants,1);eq(view.unitAuto,'2-L-1','Civilian passenger alone does not create an ADAM')
eq(view.ownCruiserRole,'solo');eq(view.unitMode,'LINCOLN')
radarCfg.colleagues_enabled=false;cars[3]=50;passengers=2;radar:tick(s,1002)
view=radar:view();eq(view.patrolOccupants,2);eq(view.unitAuto,'2-A-1','Same-car unit detection works with the radar disabled')
api.sampIsPlayerNpc=function(id)return id==13 end;radar:tick(s,2000);eq(radar:view().patrolOccupants,1)
api.getAllChars=function()return nil end;radar:tick(s,3000);eq(radar:view().patrolOccupants,1)
-- Changing the user's explicit unit and phrases remains an explicit GUI choice.
eq(profile.callsign,'PERSONAL')
