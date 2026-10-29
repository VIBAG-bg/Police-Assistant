local startup=dofile('moonloader/lib/pa26_startup.lua')
local originalOpen,originalRemove=io.open,os.remove
local files={};local fail=false;local writes={};local faultAt
io.open=function(path,mode)
    if fail then return nil end
    if mode=='wb'then
        writes[#writes+1]=path
        return {write=function(_,v)files[path]=v;if faultAt=='write-throw'then error('write failed')end;if faultAt=='write'then return nil end;return true end,
            flush=function()if faultAt=='flush-throw'then error('flush failed')end;if faultAt=='flush'then return nil end;return true end,
            close=function()if faultAt=='close-throw'then error('close failed')end;if faultAt=='close'then return nil end;return true end}
    end
    if not files[path]then return nil end
    return {read=function(_,n)if faultAt=='read-throw'then error('read failed')end;if faultAt=='read'then return nil end;return files[path]:sub(1,n)end,close=function()return true end}
end
os.remove=function(path)files[path]=nil;return true end
local dir='virtual-qa';local path=startup.path(dir)
check(startup.block(dir,'Missing mimgui\nsecond line'));eq(startup.read(dir),'blocked')
local status,message=startup.read(dir);eq(message,'Missing mimgui second line')
check(startup.ready(dir));eq(startup.read(dir),'ready');check(startup.clear(dir));eq(startup.read(dir),nil)
check(startup.disable(dir));eq(startup.read(dir),'disabled')
check(startup.clear(dir));check(startup.ready(dir));eq(startup.read(dir),'ready')
for _,fault in ipairs({'write','write-throw','flush','flush-throw','close','close-throw','read','read-throw'})do
 faultAt=fault;check(not startup.disable(dir),'Stop must fail on '..fault);faultAt=nil
 eq(startup.read(dir),'ready','Failed stop must restore the running handshake: '..fault)
end
for _,bad in ipairs({'ready','ready\nextra\n','unknown\nreason','ready\n\0',string.rep('x',2049)})do files[path]=bad;eq(startup.read(dir),nil)end
check(startup.block(dir,string.rep('x',5000)));check(#files[path]<=startup.LIMIT);eq(startup.read(dir),'blocked')
for _,p in ipairs(writes)do eq(p,path,'Startup can only write its own ephemeral flag')end
fail=true;check(not startup.ready(dir));check(not startup.disable(dir));eq(startup.read(dir),nil)
io.open,os.remove=originalOpen,originalRemove
local messages,logs={},{}
local api={print=function(v)logs[#logs+1]=v end,isSampAvailable=function()return true end,
    sampAddChatMessage=function(v)messages[#messages+1]=v end}
check(startup.announce('Ошибка: mimgui',nil,api));check(messages[1]:find('Startup failed',1,true));check(logs[1]:find('mimgui',1,true))
local enc={CP1251={encode=function(_,s)return codec.encode(s)end}}
check(startup.announce('Ошибка: mimgui',enc,api));check(codec.decode(messages[2]):find('Ошибка: mimgui',1,true))
api.isSampAvailable=function()return false end;check(not startup.announce('Ошибка',enc,api));eq(#messages,2)
-- The real main script reports startup failure and never reaches frame registration.
local fixture=require 'support.fixture'
for _,opts in ipairs({{missingLibrary=true},{missingApi=true},{missingAvailability=true}})do
    local s=fixture(opts);eq(s.startupState,'blocked');check(s.startupMessage:find('Ошибка запуска',1,true))
    check(not s.hasLog('загружен заново'))
end
-- A guard must observe the ready handshake, not merely script.load returning an object.
local core=require 'pa26_core';local recovery=require 'pa26_recovery'
local now=10000;local live={path='moonloader\\police_assistant_2026.lua'}
local self={path='moonloader\\pa26_guard.lua'};local flag='ready';local loads=0;local commands={};messages={}
local cfg=core.recoveryDefaults();cfg.delay_ms=1000
package.loaded.pa26_startup={clear=function()flag=nil end,read=function()return flag end,
    announce=function(t)messages[#messages+1]=t end}
package.loaded.pa26_config={load=function()return {recovery=cfg},{}end,fs={write=function()return true end}}
package.loaded.encoding=enc
script_name=function()end;script_author=function()end;script_version=function()end;script_description=function()end;script_properties=function()end
getWorkingDirectory=function()return 'moonloader'end;getGameTimer=function()return now end;thisScript=function()return self end
isSampAvailable=function()return true end;sampRegisterChatCommand=function(n,f)commands[n]=f end
sampUnregisterChatCommand=function(n)commands[n]=nil end;wait=function()coroutine.yield()end
script={find=function()return live end,load=function(path)loads=loads+1;live={path=path};return live end}
dofile('moonloader/pa26_guard.lua');local co=coroutine.create(main)
local function step(dt)now=now+(dt or 100);local ok,e=coroutine.resume(co);check(ok,tostring(e))end
step();local dead=live;live=nil;onScriptTerminate(dead,false);step(1000);eq(loads,1);eq(flag,nil)
step(1000);eq(#messages,0,'A live object alone does not prove initialization')
flag='ready';step();eq(#messages,1);check(messages[1]:find('загружен заново',1,true));step(1000);eq(#messages,1)
dead=live;flag='blocked';live=nil;onScriptTerminate(dead,false);step(100000);eq(loads,1)
commands.pa26restart();step();eq(loads,2);eq(flag,nil)
flag='blocked';dead=live;live=nil;onScriptTerminate(dead,false);step(100000);eq(loads,2);eq(#messages,1)
onQuitGame();step();eq(coroutine.status(co),'dead')
