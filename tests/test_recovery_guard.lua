local core=require 'pa26_core'
local recovery=require 'pa26_recovery'
local model=require 'pa26_bindings'
local settings=core.recoveryDefaults();check(not settings.demo_after_recovery);settings.demo_after_recovery=true -- Explicit opt-in path below.
local r=recovery.new()
r:trip(100,'ui','failure');check(not r:ready(3099,settings));check(r:ready(3100,settings))
check(r:begin(3100,settings));eq(r.attempts,1);check(not r:ready(50000,settings))
for i=2,3 do r:trip(i*10000,'ui','failure');check(r:begin(i*10000+3000,settings))end
r:trip(40000,'ui','failure');check(not r:ready(100000,settings));check(r:begin(100001,settings,true));eq(r.attempts,1)
r:healthy(160001,settings);eq(r.attempts,0)
r:trip(4294967200,'ui','wrap');check(r:ready(3100,settings));r:stop();eq(r.pending,nil)
local old=core.defaults();old.recovery=nil
local text=assert(require('pa26_config').serialize(old));local normalized,notes=core.normalizeConfig(assert(require('pa26_config').parse(text)))
eq(#notes,0);check(normalized.recovery.enabled)
local invalid=model.copy(settings);invalid.delay_ms=0;check(not core.validateRecovery(invalid))
invalid=model.copy(settings);invalid.max_attempts=100;check(not core.validateRecovery(invalid))
-- The separate guard is exercised as a real MoonLoader script with only host
-- management APIs mocked. It never sends a game message or patches a process.
local now=10000;local files={};local loads=0;local sent=0;local stopping=false;local commands={};local unregistered=0
local self={path='moonloader\\pa26_guard.lua'}
local live={path='moonloader\\police_assistant_2026.lua',dead=false}
local fs={read=function(path)return files[path]end,write=function(path,value)files[path]=value;return true end,
    remove=function(path)files[path]=nil;return true end}
check(recovery.writeMarker('marker',fs));check(recovery.consumeMarker('marker',fs));eq(files.marker,nil)
check(recovery.writeMarker('marker',fs));local remove=fs.remove;fs.remove=function()return nil end
check(recovery.consumeMarker('marker',fs),'failure to delete the flag must never bypass demo');fs.remove=remove;fs.remove('marker')
local failures=0
script_name=function()end;script_author=function()end;script_version=function()end;script_description=function()end;script_properties=function()end
getWorkingDirectory=function()return 'moonloader'end;getGameTimer=function()return now end;thisScript=function()return self end
isSampAvailable=function()return true end
sampRegisterChatCommand=function(name,callback)commands[name]=callback;return true end
sampUnregisterChatCommand=function(name)commands[name]=nil;unregistered=unregistered+1 end
sampSendChat=function()sent=sent+1 end;sampAddChatMessage=function()end
package.loaded.encoding={CP1251={encode=function(_,value)return codec.encode(value)end}}
package.loaded.pa26_config={fs=fs,load=function()return{recovery=settings},{}end}
wait=function(delay)eq(delay,100);coroutine.yield()end
script={find=function()return live end,load=function(path)
    eq(path,'moonloader\\police_assistant_2026.lua');loads=loads+1
    if failures>0 then failures=failures-1;return nil end
    check(recovery.consumeMarker('moonloader\\config\\police_assistant_2026_restart.flag',fs))
    live={path=path,dead=false};onScriptLoad(live);return live
end}
dofile('moonloader/pa26_guard.lua')
local co=coroutine.create(main)
local function step(dt)now=now+(dt or 100);local ok,err=coroutine.resume(co);check(ok,tostring(err))end
step();check(commands.pa26restart)
commands.pa26restart();step();eq(loads,0,'a working main script must not be reloaded and lose drafts')
local stopped=live;live=nil;onScriptTerminate(stopped,false);step(2999);eq(loads,0);step(1);eq(loads,1)
step(20000);eq(loads,1,'no duplicate main script')
onScriptTerminate({path='moonloader\\foreign.lua'},false);step(5000);eq(loads,1)
-- Disable automatic recovery, then use the independent emergency command.
settings.enabled=false;stopped=live;live=nil;onScriptTerminate(stopped,false);step(4000);eq(loads,1)
commands.pa26restart();step();eq(loads,2)
settings.enabled=true;settings.max_attempts=2;failures=20;stopped=live;live=nil;onScriptTerminate(stopped,false)
step(3000);step(3000);step(100000);eq(loads,3,'previous manual recovery and one failed reload exhaust the current burst')
commands.pa26restart();step();eq(loads,4)
onQuitGame();onScriptTerminate({path='moonloader\\police_assistant_2026.lua'},true);step(20000)
eq(loads,4);eq(sent,0);eq(commands.pa26restart,nil);eq(coroutine.status(co),'dead')
