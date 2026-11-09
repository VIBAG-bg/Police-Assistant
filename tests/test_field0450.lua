local model=require 'pa26_bindings';local core=require 'pa26_core';local prefs=require 'pa26_field_settings'
local cfg=core.defaults();local lib=model.defaults(cfg);local old=model.copy(lib)
local raw=model.copy(lib);raw.field=nil;local migrated=assert(model.validate(raw,cfg))
eq(#migrated.notes,#old.notes);eq(#migrated.bindings,#old.bindings);eq(migrated.field.enabled,false)
eq(migrated.profile.name,old.profile.name);eq(migrated.bindings[1].script,old.bindings[1].script)
local bad=prefs.validate({enabled='true',navigation={observe_ms=0/0,max_segments=99999},coordinates={channel='/su',phone='/cuff 5'}})
eq(bad.enabled,false);eq(bad.navigation.max_segments,256);eq(bad.coordinates.channel,'/fn');eq(bad.coordinates.phone,'')
local legacyPath='D:\\Saved graph.bin'
lib.field.navigation.road_external=legacyPath
eq(assert(model.validate(lib,cfg)).field.navigation.road_external,legacyPath,'Legacy GPS preferences remain serializable')
local t,revision,reads=0,1,0;local plans={};local warnings={}
local field=require('pa26_field_services').new({library=function()return lib end,revision=function()return revision end,
 codec=codec,clock=function()return t end,gameNow=function()return t end,waypoint=function()reads=reads+1;return true,100,200,0 end,
 openRoads=function()error('Frozen GPS must never open a graph')end,
 notice=function(x)warnings[#warnings+1]=x end,start=function(p)plans[#plans+1]=p;return true end,
 templateContext=function()return{values={unit='1-L-1'},gender='female'}end})
local s={session='s',ped=1,demo=false,interior=0,x=1,y=2,z=3,area='Ganton',map_square='H-18',focused=true,alive=true,paused=false,blocked=false,typing=false,modal=false}
for i=1,10000 do t=i;field:tick(s,i)end;eq(reads,0,'Master OFF never polls waypoint')
lib.field.enabled=true;lib.field.navigation.enabled=true;lib.field.navigation.observe_waypoint=true
field:tick(s,t);t=t+100;field:tick(s,t)
t=t+200;s.paused=true;field:tick(s,1);eq(reads,0,'Stored GPS settings do not activate waypoint reads')
for _,name in ipairs({'pa26_navigation','pa26_navigation_roads','pa26_road_sources'})do eq(package.loaded[name],nil)end
s.paused=false;lib.field.coordinates.enabled=true;lib.field.coordinates.observe=true;t=t+300;field:tick(s,t)
local proposal=assert(field:propose('share'));eq(#plans,0);check(proposal.lines[1]:match('^/fn '))
check(field:accept(proposal));s.typing=true;t=t+1;field:tick(s,t);eq(#plans,0);eq(field.intent,nil);s.typing=false
proposal=assert(field:propose('share'));revision=revision+1;check(not field:accept(proposal))
proposal=assert(field:propose('share'));check(field:accept(proposal));t=t+1;field:tick(s,t);eq(#plans,1)
field:execution('completed',{plan=plans[1]});eq(field.queued,nil)
local leader=lib.field.leadership;leader.enabled=true;leader.verified=true;leader.source='User test evidence';leader.tag='EPD'
leader.lines={'Первая строка.','Вторая строка.','Третья строка.'}
proposal=assert(field:propose('gnews'));eq(#proposal.plan.steps,5);eq(proposal.plan.steps[2].ms,1500)
leader.lines[2]=string.rep('я',200);check(not field:propose('gnews'));eq(#plans,1,'Overlong second line rejects entire batch')
leader.lines={'Юнит {unit}.','/cuff 3','Третья.'};check(not field:propose('gnews'))
leader.lines={'Юнит {unknown}.','',''};check(not field:propose('gnews'))
leader.lines={'Юнит {unit}.','',''};proposal=assert(field:propose('gnews'));eq(proposal.lines[1],'/gnews EPD | Юнит 1-L-1.')
field:reset();eq(field.coordinates.mark,nil);eq(field.coordinates.offer,nil)
-- The marker has its own confirmation and lifetime.
lib.field.navigation.enabled=false;t=t+300;field:tick(s,t)
check(field:paste('200 300 5'));local token=field.coordinates.offer.token;field.coordinates:shown(token)
check(field.coordinates:decide(token,true));t=t+300;field:tick(s,t);check(field.coordinates.mark)
check(field.snapshot.hud:find('по прямой',1,true));eq(field.snapshot.points,nil)
t=t+300;field:tick(s,t);check(field.coordinates.mark,'Independent OOC marker persists until its own TTL')
t=field.coordinates.mark.expires;field:tick(s,t);eq(field.coordinates.mark,nil);eq(field.snapshot.target,nil)
local function place(text)
 check(field:paste(text));local key=field.coordinates.offer.token;field.coordinates:shown(key)
 check(field.coordinates:decide(key,true));t=t+1;field:tick(s,t)
end
place('200 300 5');check(field.coordinates.mark)
field:clear();t=t+1;field:tick(s,t);eq(field.snapshot.target,nil)
lib.field.coordinates.arrival_clear=true
place('1 2 3');eq(field.coordinates.mark,nil,'Arrival removes a confirmed-height point')
place('1 2');check(field.coordinates.mark,'Unknown height cannot confirm arrival')
s.interior=1;t=t+1;field:tick(s,t);eq(field.coordinates.mark,nil)
s.interior=0;t=t+1;field:tick(s,t)
place('200 300 5');check(field.coordinates.mark)
s.session='reconnected';t=t+1;field:tick(s,t);eq(field.coordinates.mark,nil)
place('200 300 5');check(field.coordinates.mark)
lib.field.coordinates.enabled=false;t=t+1;field:tick(s,t);eq(field.coordinates.mark,nil,'OFF cleans only the owned mark')
lib.field.coordinates.enabled=true
for i,row in ipairs(lib.field.leadership.briefings)do for j=1,#row.lines do check(field:propose('briefing',{index=i,line=j}))end end
local invalid=model.copy(lib);invalid.field.leadership.briefings[1].name='';check(not model.validate(invalid,cfg),'Invalid draft is rejected, never silently dropped on save')
local again=assert(model.validate(lib,cfg));eq(#again.field.leadership.briefings,#lib.field.leadership.briefings,'Roundtrip never duplicates the built-in library')
local cruiser=require 'pa26_cruiser_assist';local released=0
local c=cruiser.new({verified=true,drive=function()error('Failure after injecting control')end,release=function()released=released+1 end})
local cc=prefs.defaults().cruiser;cc.enabled=true;cc.cruise=true
local state={session='s',alive=true,focused=true,driver=true,vehicle=5,vehicle_class='car',speed=30}
check(c:engage(state,cc));c:tick(state,cc);eq(released,1);eq(c.active,false)
for _,flag in ipairs({'paused','typing','modal','blocked','brake','handbrake'})do
 c.backend.drive=function()return true end;check(c:engage(state,cc));c:tick(state,cc);local before=released
 state[flag]=true;c:tick(state,cc);eq(c.active,false,flag);eq(released,before+1);state[flag]=nil
end
check(not cruiser.new():engage(state,cc));state.vehicle_class='bike';check(not c:engage(state,cc))
local pin=require 'pa26_pinned_note'
for _,wh in ipairs({{1152,864},{1366,768},{1920,1080},{2560,1440},{640,480}})do
 local r=pin.geometry(prefs.defaults().pinned,wh[1],wh[2]);check(r.x>=0 and r.y>=0);check(r.x+r.w<=wh[1] and r.y+r.h<=wh[2])
end
