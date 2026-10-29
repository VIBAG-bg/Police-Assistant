local Life=require 'pa26_local_life';local cfg=require('pa26_patrol_settings').defaults()
local model=require 'pa26_bindings'
local function setup()
    local s={session='server:7777',local_nick='Officer_Name',ped=1,alive=true,spawned=true,health=100,x=0,y=0,z=5,interior=0}
    local l=Life.new({settings=function()return cfg end});l:tick(s,1000)
    return l,s
end
for _,nativeAlive in ipairs({false,true})do
    local l,s=setup();s.health=0;s.alive=nativeAlive;s.spawned=nativeAlive;l:tick(s,1100)
    check(l:view().incapacitated);check(l:view().sceneAlive);eq(l.epoch,0)
    for i=1,60 do l:tick(s,1100+i*1000);eq(l.epoch,0);check(l:view().incapacitated)end
    s.health=100;s.alive=true;s.spawned=true;l:tick(s,62000)
    check(not l:view().incapacitated);eq(l.epoch,0,'Revival in place does not end the scene')
end
local l,s=setup();l:observe('spawn_requested');l:observe('spawn_approved',true);l:tick(s,1200)
eq(l.epoch,0,'A spawn request outside incapacitation is not a confirmed death')
l,s=setup();s.health=0;s.alive=false;s.spawned=false;l:tick(s,1200)
l:observe('spawn_requested');l:observe('spawn_approved',true)
s.health=100;s.alive=true;s.spawned=true;l:tick(s,1300)
eq(l.epoch,0,'Even spawn events do not turn an in-place revival into hospital respawn')
-- Hospital door/ordinary teleport while healthy never ends a situation.
l,s=setup();l:observe('spawn_info',{x=1000,y=1000,z=20});l:observe('teleport',{x=1000,y=1000,z=20})
s.x=1000;s.y=1000;s.z=20;s.interior=1;l:tick(s,1500);eq(l.epoch,0)
-- A relocation alone after injury is insufficient without spawn evidence.
l,s=setup();s.health=0;l:tick(s,1200);l:observe('teleport',{x=1000,y=0,z=5})
s.x=1000;s.health=100;l:tick(s,1300);eq(l.epoch,0)
-- Independent spawn flow + actual new observed placement confirms exactly once.
l,s=setup();s.health=0;s.alive=false;s.spawned=false;l:tick(s,1200)
l:observe('spawn_approved',true);l:observe('spawn_requested');l:observe('teleport',{x=1500,y=0,z=5})
s.x=1500;s.health=100;s.alive=true;s.spawned=true;l:tick(s,1400)
eq(l.epoch,1);check(l:view().confirmed);check(not l:view().incapacitated)
l:tick(s,1500);eq(l.epoch,1);check(not l:view().confirmed)
-- An explicitly supplied new server spawn position can corroborate a teleport.
l,s=setup();s.health=0;l:tick(s,1200)
l:observe('spawn_info',{x=300,y=0,z=5});l:observe('teleport',{x=300,y=0,z=5})
s.x=300;s.health=100;l:tick(s,1300);eq(l.epoch,1)
l,s=setup();s.health=0;l:tick(s,1200)
l:observe('spawn_info',{x=1000,y=0,z=5});l:observe('teleport',{x=1000,y=0,z=5});l:tick(s,1300)
s.health=100;s.x=1000;l:tick(s,1300+cfg.respawn_evidence_ms+1)
eq(l.epoch,0,'Expired events are not reused as proof')
l,s=setup();s.health=0;l:tick(s,1200);s.session='different:7777';s.health=100;l:tick(s,1300)
eq(l.epoch,0,'Changing server is a connection transition, not a hospital claim')
check(not l:observe('teleport',{x=0/0,y=0,z=0}));check(not l:observe('unknown'))
for i=1,16 do check(l:observe('death_reported'))end;check(not l:observe('death_reported'))

-- Actual PA integration: keep patrol, vehicle selection and Copilot counters at
-- 0 HP; revoke outgoing work; only a confirmed changed scene archives the patrol.
local fixture=require 'support.fixture';local core=require 'pa26_core'
local lib=model.defaults(core.defaults());lib.profile.name='Officer Name';lib.patrol_session.enabled=true
lib.patrol_session.reporter_self=false;lib.alerts.enabled=true;lib.alerts.on_duty=true
lib.bindings[1].target_required=false;lib.bindings[1].script='Автодействие недоступно раненому персонажу.'
local f=fixture({demo=false,library=lib,alerts=true});f.step();f.commands.pa26();f.step()
local p=assert(f.patrolSession:propose('start'));check(f.patrolSession:accept(p));f.step()
check(f.patrolSession.data.active);local patrolId=f.patrolSession.data.active.id
f.copilot.phase='Преследование';f.copilot.tireWarnings=2;local cpLife=f.copilot.life
f.health=0;f.localDead=true;f.step(1000)
check(f.patrolSession.data.active);eq(f.patrolSession.data.active.id,patrolId)
eq(f.copilot.phase,'Преследование');eq(f.copilot.tireWarnings,2);eq(f.copilot.life,cpLife)
f.step(5000);check(f.patrolSession.data.active);eq(#f.patrolSession.data.history,0);eq(#f.sent,0)
f.commands.pa26run('1');f.step();eq(#f.sent,0,'An automatic PA bind is held while incapacitated')
-- Explicit human speech, including continuation, remains usable for calling medics.
local raw=string.rep('Нужна помощь медиков. ',9)
f.chat=true;f.chatText=raw;f.step();onWindowMessage(0x100,13)
check(f.events.onSendChat(codec.encode(raw))==false,'Long manual text is handled by the chat splitter')
f.chat=false
for i=1,4 do f.step(2000)end
local manualSent=#f.sent;check(manualSent>=2,'The downed player can still type and send continued chat')
for _,line in ipairs(f.sent)do check(not line.line:find('Автодействие',1,true))end
f.events.onSendSpawn();f.step();check(f.patrolSession.data.active);eq(f.copilot.life,cpLife)
f.localDead=false;f.health=100;f.step(1000)
check(f.patrolSession.data.active);eq(#f.patrolSession.data.history,0)
-- Observe a second downed episode, then an actual correlated server relocation.
f.health=0;f.localDead=true;f.step()
local originalCoordinates=getCharCoordinates
f.events.onRequestSpawnResponse(true);f.events.onSendSpawn();f.events.onSetPlayerPos({x=1500,y=0,z=5})
getCharCoordinates=function(ped)if ped==PLAYER_PED then return 1500,0,5 end;return originalCoordinates(ped)end
f.localDead=false;f.health=100;f.step(1000)
check(not f.patrolSession.data.active);eq(#f.patrolSession.data.history,1)
check(f.patrolSession.data.history[1].reason:find('респавн',1,true));eq(f.copilot.tireWarnings,0)
eq(#f.sent,manualSent);check(not f.hasLog('Ошибка интерфейса'));onScriptTerminate(f.script)
