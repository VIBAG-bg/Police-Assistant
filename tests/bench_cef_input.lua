local fixture=require 'support.fixture'
local s=fixture({demo=false,render=false,categoryWheel=true});s.step()
if s.frames[1].condition()then s.commands.pa26();s.step()end
local b=s.chatBridge
b.server={accept=function()return nil,'timeout'end,close=function()end}
local counts={runtime_cancel=0,workspace_cancel=0,modal_reset=0,asset_checks=0,native_reads=0}
local function wrap(object,key,counter)
 local original=object[key];object[key]=function(self,...)counts[counter]=counts[counter]+1;return original(self,...)end
end
wrap(s.runtime,'cancel','runtime_cancel');wrap(s.workspace,'cancel','workspace_cancel')
wrap(s.workspace.studio,'cancelModal','modal_reset');wrap(b,'installed','asset_checks')
for _,name in ipairs({'sampIsChatInputActive','sampIsDialogActive','getGameTimer','isGamePaused','isSampAvailable'})do
 local original=_G[name];_G[name]=function(...)counts.native_reads=counts.native_reads+1;return original(...)end
end
local function active()b.state={busy=true,chat=true,dialog=false,at=s.now}end
active();s.step(16)
for key in pairs(counts)do counts[key]=0 end
local before=os.clock();local keys={0x41,0x49,0x4A,0x4B,0x4F,0x54,0x25,0x27,0x08}
for i=1,3000 do local key=keys[(i-1)%#keys+1]
 onWindowMessage(0x100,key);onWindowMessage(0x102,key);onWindowMessage(0x101,key)
end
local keyboard={calls=9000,cpu_ms=(os.clock()-before)*1000,counts={}}
for key,value in pairs(counts)do keyboard.counts[key]=value;counts[key]=0 end
before=os.clock()
for _=1,600 do active();s.step(16)end
local frames={calls=600,cpu_ms=(os.clock()-before)*1000,counts={}}
for key,value in pairs(counts)do frames.counts[key]=value end
onScriptTerminate(s.script)
return TEST_JSON_ENCODE({keyboard=keyboard,typing_frames=frames,game_started=false,game_written=false})
