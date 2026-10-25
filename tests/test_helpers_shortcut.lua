local model=require 'pa26_bindings';local core=require 'pa26_core';local fixture=require 'support.fixture'
local input=require 'pa26_input'
local d=model.defaults(core.defaults());eq(d.assist.open_shortcut.key,0x73)
local old=model.copy(d);old.assist.open_shortcut=nil;eq(assert(model.validate(old,core.defaults())).assist.open_shortcut.key,0x73)
old.bindings[1].shortcut={key=0x73,ctrl=false,alt=false,shift=false}
local safe=assert(model.validate(old,core.defaults()));eq(safe.assist.open_shortcut.key,0);eq(safe.bindings[1].shortcut.key,0x73)
d.assist.open_shortcut={key=0,ctrl=false,alt=false,shift=false};eq(assert(model.validate(d,core.defaults())).assist.open_shortcut.key,0)
local function ready(extra)
    local s=fixture(extra or{demo=false});s.step();if s.frames[1].condition()then s.commands.pa26()end;s.step();return s
end
local function tap(s,key)
    onWindowMessage(0x100,key,0);onWindowMessage(0x101,key,0);s.step()
end
local s=ready();local before=s.consumed;tap(s,0x46);check(not s.windows['Police Assistant · Помощники##pa26-assist']);eq(s.consumed,before,'F stays with GTA')
tap(s,0x73);check(s.windows['Police Assistant · Помощники##pa26-assist']);check(s.consumed>before);check(not s.frames[1].condition());eq(#s.sent,0)
s.step();check(s.frames[4].condition());tap(s,0x73);check(not s.frames[4].condition())
s.down[0x73]=true;onWindowMessage(0x100,0x73,0);s.step();check(s.frames[4].condition())
onWindowMessage(0x100,0x73,0x40000000);s.step();check(s.frames[4].condition(),'holding F4 never toggles twice')
onWindowMessage(0x101,0x73,0);s.down[0x73]=false;s.step();tap(s,0x73);check(not s.frames[4].condition())
s.chat=true;tap(s,0x73);check(not s.frames[4].condition());s.chat=false;s.step()
s.dialog=true;tap(s,0x73);check(not s.frames[4].condition());s.dialog=false;s.step()
onWindowMessage(0x100,0x73,0);onWindowMessage(0x8,0);onWindowMessage(0x7,0);s.step();check(not s.frames[4].condition())
onWindowMessage(0x101,0x73,0);s.step();tap(s,0x73);check(s.frames[4].condition())
-- The same saved field drives tools, the window and key capture.
s.workspace.studio.assistPage='evidence';tap(s,0x73);tap(s,0x73);eq(s.workspace.studio.assistPage,'evidence')
s.toggle=nil;s.click='Убрать##assist-key-clear-assist-open_shortcut';s.render();s.step()
local saved=s.savedLibrary();eq(saved.assist.open_shortcut.key,0)
tap(s,0x73);check(s.frames[4].condition(),'disabled shortcut cannot close the current window')
saved.assist.open_shortcut={key=0x75,ctrl=true,alt=false,shift=false};check(s.workspace:save(saved));s.step()
tap(s,0x75);check(s.frames[4].condition(),'exact modifiers required')
s.down[0x11]=true;tap(s,0x75);check(not s.frames[4].condition());s.down[0x11]=false;s.step()
eq(#s.sent,0);eq(s.invalidIOReads,0);check(not s.hasLog('Ошибка интерфейса'));onScriptTerminate(s.script)
local p=input.new(function()return 0 end);local keys={physical=true,keys={[0x75]=false},ctrl=true,alt=false,shift=false,super=false}
local chord={key=0x75,ctrl=true,alt=false,shift=false};p:menuPressed(0x75,true,keys,false,chord);keys.keys[0x75]=true
check(p:menuPressed(0x75,true,keys,false,chord));check(not p:menuPressed(0x75,true,keys,false,chord))
