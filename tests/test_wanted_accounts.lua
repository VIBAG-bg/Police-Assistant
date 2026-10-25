local mod=require 'pa26_wanted_accounts'
local core=require 'pa26_core'
local copy=require('pa26_patrol_settings').copy
local rows,generations={},{};local calls=0;local allowRemote=true;local near
local c=mod.new({observe=function(id)calls=calls+1;return rows[id]end,
    generation=function(id)return generations[id]or 0 end,near=function(t)return near and near.id==t.id end,
    allowRemote=function()return allowRemote end})
local state={session='test',ped=1,alive=true,demo=false,localId=5}
rows[37]={connected=true,name='Remote_Player',npc=false}
c:tick(state,nil,{});local t=assert(c:select(37));check(t.account);eq(t.ped,nil);check(c:valid(t))
eq(c:current().id,37);local count=calls;check(c:valid(t));c:current();eq(calls,count,'Rendering must not call native observations')
c:tick(state,nil,{});check(c:valid(t),'No streamed ped or coordinates required')
allowRemote=false;c:tick(state,nil,{ {target=t} });check(not c:valid(t))
near={id=37,ped=99,name='Remote_Player'};c:tick(state,near,{});check(c:valid(t));allowRemote=true
for _,id in ipairs({-1,1004,1.5,math.huge})do check(not c:select(id))end
for _,name in ipairs({'','Bad Name','Bad*Name','Bad\nName','{FFFFFF}Name',string.rep('a',25)})do
    rows[37].name=name;check(not c:select(37))
end
rows[37].name='Remote_Player';t=assert(c:select(37));rows[37].name='Other_Player';c:tick(state,nil,{{target=t}});check(not c:valid(t))
rows[37].name='Remote_Player';generations[37]=2;c:tick(state,nil,{{target=t}});check(not c:valid(t),'Same nickname after quit/join is a new account generation')
t=assert(c:select(37));rows[37].connected=false;c:tick(state,nil,{{target=t}});check(not c:valid(t))
rows[37].connected=true;rows[37].npc=true;check(not c:select(37));rows[37].npc=false
for _,change in ipairs({'session','ped','alive','demo'})do
    t=assert(c:select(37));local changed=copy(state)
    changed[change]=change=='alive'and false or change=='demo'and true or 'other'
    c:tick(changed,nil,{});check(not c:valid(t));state=copy(state);c:tick(state,nil,{})
end
rows[0]={connected=true,name='Zero_Player'};t=assert(c:select(0));eq(t.id,0)
