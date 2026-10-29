-- The standalone recovery script used to restart an intentionally unloaded PA.
local core=require 'pa26_core';local model=require 'pa26_bindings'
local now=10000;local loads=0;local state='ready';local commands={};local files={}
local self={path='moonloader\\pa26_guard.lua'}
local live={path='moonloader\\police_assistant_2026.lua',dead=false}
local cfg=core.recoveryDefaults()
local originalStartup=package.loaded.pa26_startup
local originalConfig=package.loaded.pa26_config
package.loaded.pa26_startup={read=function()return state end,clear=function()state=nil;return true end,announce=function()end}
package.loaded.pa26_config={load=function()return{recovery=cfg},{}end,fs={read=function(p)return files[p]end,write=function(p,v)files[p]=v;return true end,remove=function(p)files[p]=nil;return true end}}
script_name=function()end;script_author=function()end;script_version=function()end;script_description=function()end;script_properties=function()end
getWorkingDirectory=function()return'moonloader'end;getGameTimer=function()return now end;thisScript=function()return self end
isSampAvailable=function()return true end;sampRegisterChatCommand=function(n,f)commands[n]=f;return true end
sampUnregisterChatCommand=function(n)commands[n]=nil end
wait=function()coroutine.yield()end
script={find=function()return live end,load=function(path)
 loads=loads+1;live={path=path,dead=false};state='ready';onScriptLoad(live);return live
end}
dofile('moonloader/pa26_guard.lua');local co=coroutine.create(main)
local function step(dt)now=now+(dt or 100);local ok,err=coroutine.resume(co);check(ok,tostring(err))end
step();local previous=live;live=nil;state='disabled';onScriptTerminate(previous,false)
for _=1,30 do step(1000)end
eq(loads,0,'Explicit shutdown must remain off beyond the recovery delay')
commands.pa26restart();step();eq(loads,1,'Only explicit manual restart may re-enable PA')
previous=live;live=nil;state='ready';onScriptTerminate(previous,false);step(3000);eq(loads,2,'A real crash still recovers')
-- Missing-script detection without a termination event follows the same rule.
live=nil;state='disabled';for _=1,40 do step(1000)end;eq(loads,2)
commands.pa26restart();step();eq(loads,3)
onQuitGame();step();eq(coroutine.status(co),'dead')
package.loaded.pa26_startup=originalStartup;package.loaded.pa26_config=originalConfig

-- Actual button path records the stop only after every personal save succeeds.
local fixture=require 'support.fixture'
local function click(s,label)s.click=label;s.render();eq(s.click,nil,label)end
local s=fixture({productionWindows=true,demo=false});s.step();s.page('home')
local startup=require 'pa26_startup';local directory=getWorkingDirectory()
click(s,'Отключить PA##home');click(s,'ДА — отключить PA##confirm-yes');s.step()
eq(startup.read(directory),'disabled');s.step();eq(s.unloadCalls,1)
for _=1,40 do s.step(1000)end;eq(s.unloadCalls,1);eq(#s.sent,0)
onScriptTerminate(s.script)
s=fixture({productionWindows=true,demo=false});s.step();s.page('home')
startup=require 'pa26_startup'
eq(startup.read(getWorkingDirectory()),'ready','A fresh main script clears the old intentional-stop state')
local knowledge=s.knowledgeUi.knowledge;knowledge.flush=function()return nil,'Injected disk failure'end
click(s,'Отключить PA##home');click(s,'ДА — отключить PA##confirm-yes');s.step()
eq(s.unloadCalls,nil);check(not s.frames[1].removed);check(startup.read(getWorkingDirectory())~='disabled')
onScriptTerminate(s.script)
s=fixture({productionWindows=true,demo=false});s.step();s.page('home');s.startupDisableFail=true
click(s,'Отключить PA##home');click(s,'ДА — отключить PA##confirm-yes');s.step()
eq(s.unloadCalls,nil);check(not s.frames[1].removed);check(s.workspace.studio:hasWarning())
eq(s.startupState,'ready','A failed stop handshake cannot disable recovery')
onScriptTerminate(s.script)
