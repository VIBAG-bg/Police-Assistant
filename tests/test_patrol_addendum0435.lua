local model=require 'pa26_bindings';local core=require 'pa26_core';local V=require 'pa26_vehicle'
local cfg=require('pa26_vehicle_settings').defaults();local own={handle=50,id=10,model_id=597,x=0,y=0}
local v=V.new({settings=function()return cfg end,ownCar=function()return own and model.copy(own)end})
local state={inVehicle=true}
v:direction(state,1000,cfg);eq(v.lastDirectionValue,nil)
own.y=10;v:direction(state,1500,cfg);eq(v:reportDirection(state),'Север')
v:direction(state,2000,cfg);eq(v:reportDirection(state),'Север')
own.x=10;v:direction(state,2500,cfg);eq(v:reportDirection(state),'Восток')
v:direction(state,3000,cfg);eq(v:reportDirection(state),'Восток')
own.y=0;v:direction(state,3500,cfg);eq(v:reportDirection(state),'Юг')
v:direction(state,4000,cfg);eq(v:reportDirection(state),'Юг')
own.x=nil;check(pcall(v.direction,v,state,4500,cfg));eq(v.lastDirectionValue,'Юг');own.x=10
v:direction(state,5000,cfg);own.y=-10;v:direction(state,5500,cfg);eq(v.lastDirectionValue,'Юг')
local saved=own;own=nil;state.inVehicle=false;v:direction(state,6000,cfg);eq(v:reportDirection(state),'')
cfg.direction_on_foot=true;eq(v:reportDirection(state),'Юг');cfg.direction_on_foot=false
own=model.copy(saved);own.id=11;state.inVehicle=true;v:direction(state,6500,cfg);eq(v.lastDirectionValue,nil)
own.y=10;v:direction(state,7000,cfg);eq(v.lastDirectionValue,'Север')
own.y=1000;v:direction(state,20000,cfg);eq(v.lastDirectionValue,nil,'Teleport over a long gap is not a valid bearing')
local fresh=V.new(v.env);fresh:direction(state,21000,cfg);eq(fresh.lastDirectionValue,nil,'Reload never fabricates heading')
local ps=require 'pa26_patrol_settings';local report=require 'pa26_report_context'
local stock=ps.defaults();check(not stock.finish_template:find('{duration}',1,true));check(ps.variables.duration)
for key,text in pairs(ps.legacyTemplates)do local raw=ps.defaults();raw[key]=text;raw.radio_templates_version=1
 eq(assert(ps.validate(raw))[key],stock[key],'Only recognized stock is migrated: '..key)
 raw[key]='Мой текст: {duration}.';eq(assert(ps.validate(raw))[key],raw[key])
end
check(report.directionTemplate(stock.start_template,{directionKnown=false}))
check(not report.directionTemplate('Личный курс: {direction}',{directionKnown=false}))
local Session=require 'pa26_patrol_session';local Patrol=require 'pa26_patrol'
local function setup()
 local s={now=1000,wall=1000,cfg=ps.defaults(),profile={name='Иван Петров',callsign='',gender='male'},plans={}}
 s.cfg.enabled=true;s.cfg.reporter_self=false
 s.state={session='one',local_nick='Ivan_Petrov',ped=1,demo=false,alive=true,focused=true,paused=false,blocked=false,onDuty=true,radioEnabled=true,area='Downtown',city='Сан-Фиерро',map_square='J-6'}
 local c=Session.new({settings=function()return s.cfg end,profile=function()return s.profile end,contacts=function()return{}end,codec=codec,equal=require('pa26_author_presets').equal,resolve=function()end,observe=function()end})
 function s.tick(game,wall)c:tick(s.state,game or s.now,wall or s.wall);s.now=game or s.now;s.wall=wall or s.wall end
 s.tick();local p=assert(c:propose('start'));check(c:accept(p));s.tick()
 return c,s
end
for _,duration in ipairs({10000,120000,900000})do
 local c,s=setup();s.state.paused=true;s.tick(1000,1001);s.tick(1000,1001+duration)
 eq(c.data.active.elapsed_ms,duration+1);s.state.paused=false;s.tick(1001,1002+duration)
 eq(c.data.active.elapsed_ms,duration+2);eq(#s.plans,0)
 check(c:pause());s.state.paused=true;s.tick(1001,2000+duration);s.tick(1001,4000+duration)
 eq(c.data.active.elapsed_ms,duration+2,'Manual patrol pause stays paused')
end
for _,change in ipairs({'focus','focusEpoch','server','character','missing','respawn','clockRollback','hugeJump','stall'})do
 local c,s=setup();s.state.paused=true;s.tick(1000,1001);local before=c.data.active.elapsed_ms
 if change=='focus'then s.state.focused=false
 elseif change=='focusEpoch'then s.state.focusEpoch=2
 elseif change=='server'then s.state.session='other'
 elseif change=='character'then s.state.local_nick='Other_Person'
 elseif change=='missing'then s.state.ped=nil
 elseif change=='respawn'then s.state.respawnConfirmed=true
 elseif change=='stall'then s.state.paused=false;s.tick(1001,1002);before=c.data.active.elapsed_ms end
 local wall=change=='clockRollback'and 0 or change=='hugeJump'and 90000000 or 121002
 s.tick(1002,wall)
 check(not c.data.active or c.data.active.elapsed_ms==before,change)
end
local clock=require 'pa26_elapsed_clock'
eq(clock.delta(20,4294967290,1030,1000,{focused=true,paused=false},{focused=true,paused=false},{}),30)
local cfg2={enabled=true,hud=true,mode='police',confirmation=true,police_channel='/r',police_template='Доклад.',police_interval_ms=60000,post='',count_map_time=true,map_max_gap_ms=3600000}
local calls,previews=0,0;local a=model.copy(select(2,setup()).state)
local p=Patrol.new({settings=function()return cfg2 end,preview=function()previews=previews+1;return'pending'end,ready=function()return true end,dispatch=function()calls=calls+1;return true end})
p:tick(a,1000,1000);a.paused=true;p:tick(a,1000,1001);p:tick(a,1000,901001)
eq(p.remaining,0);eq(calls,0);eq(previews,0,'No automatic confirmation while on the map')
a.paused=false;p:tick(a,1001,901002);eq(calls,1);eq(previews,1)
-- Current location belongs to the post-map report, not a replayed queue.
a.area='Commerce';p:tick(a,1002,901003);check(calls<=2,'Only one retained producer occurrence, no elapsed-cycle loop')
-- Real main/session/radio/notifications/executor integration, simulated Esc.
local lib=model.defaults(core.defaults());lib.profile.name='Иван Петров';lib.profile.callsign=''
lib.alerts.on_duty=true;lib.patrol_session.enabled=true;lib.patrol_session.interval_ms=60000;lib.patrol_session.confirmation=false
lib.radio_guard.lead_ms=1000
local s=require('support.fixture')({library=lib,demo=false,alerts=true,notifications=true});s.step()
if s.frames[1].condition()then s.commands.pa26();s.step()end
local start=assert(s.patrolSession:propose('start'));check(s.patrolSession:accept(start))
for _=1,10 do s.step(1500)end;check(s.patrolSession.data.active)
local before=#s.sent;local elapsed=s.patrolSession.data.active.elapsed_ms
s.wallTime=s.now;s.paused=true;s.step(0);s.wallTime=s.wallTime+120000;s.step(0)
eq(#s.sent,before);eq(s.patrolSession.data.active.elapsed_ms,elapsed+120000);eq(#s.radioGuard:candidates(),0)
s.paused=false
for _=1,12 do s.wallTime=s.wallTime+500;s.step(500);s.render()end
eq(#s.sent,before,'Even a saved confirmation=OFF cannot auto-send the report deferred by Esc')
local ticket;for _,t in pairs(s.radioGuard.tickets)do if t.phase=='confirm'then ticket=t end end
check(ticket and ticket.spec.mapDeferred and ticket.spec.confirmation,'One current post-map confirmation')
check(not s.workspace.library.patrol_session.confirmation,'The saved preference itself remains untouched')
check(s.radioGuard:decide(ticket.token,false));for _=1,5 do s.wallTime=s.wallTime+500;s.step(500)end
eq(#s.sent,before);check(not s.hasLog('Ошибка интерфейса'));eq(s.invalidIOReads,0);onScriptTerminate(s.script)
