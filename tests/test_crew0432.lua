local module=require 'pa26_colleagues';local cfg=require('pa26_copilot_settings').defaults();local name='Partner_Name';local skin=281;local npc=false;local connected=true;local seated=true
local calls=0
local api={getAllChars=function()return{1}end,getDriverOfCar=function()return 1 end,
 getCharInCarPassengerSeat=function(car,seat)calls=calls+1;return seat==2 and 2 or 0 end,
 doesCharExist=function(p)return p==1 or p==2 end,isCharDead=function()return false end,
 isCharInAnyCar=function()return seated end,storeCarCharIsInNoSave=function()return 50 end,
 sampGetPlayerIdByCharHandle=function(p)return true,p+10 end,sampGetCharHandleBySampPlayerId=function(id)return true,id-10 end,
 sampIsPlayerConnected=function()return connected end,sampIsPlayerNpc=function()return npc end,sampGetPlayerNickname=function()return name end,getCharModel=function()return skin end}
local contacts={};local c=module.new({read=function(key,...)if api[key]then return api[key](...)end end,settings=function()return cfg end,partners=function()return contacts end})
local state={ped=1};eq(c:carCrew(state,50,2),2);eq(calls,20);eq(c.physicalCrew[1].name,'Partner_Name')
skin=10;eq(c:carCrew(state,50,2),1,'A random passenger is not a partner');contacts={{id=1,nickname=name,ic_name='Иван Петров'}};eq(c:carCrew(state,50,2),2);eq(c.physicalCrew[1].ic_name,'Иван Петров')
seated=false;eq(c:carCrew(state,50,2),1,'A planned contact outside the car is not crew');seated=true
npc=true;eq(c:carCrew(state,50,2),1);npc=false;connected=false;eq(c:carCrew(state,50,2),1);connected=true
api.sampGetCharHandleBySampPlayerId=function()return true,3 end;eq(c:carCrew(state,50,2),1,'A reused ID / broken round trip is excluded')
eq(c:carCrew(state,nil,10),1)
local ctx=require 'pa26_report_context';local values=ctx.values({gender='female',my_nick='Officer_Name',colleagues={patrolOccupants=1,patrolCrew={}}},{department='SFPS'},{})
eq(values.unit,'2-L-1');eq(values.patrol_start,'начинаю патруль');eq(values.patrol_available,'доступна')
