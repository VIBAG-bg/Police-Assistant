local input=require 'pa26_input';local fixture=require 'support.fixture'
local key=120
local function keys(down,ctrl)return{physical=true,keys={[key]=down},ctrl=ctrl==true,alt=false,shift=false,super=false}end
local p=input.new(function()return 0 end)
check(not p:menuPressed(key,true,keys(false),false))
check(p:menuPressed(key,true,keys(true),true));check(not p:menuPressed(key,true,keys(true),false))
check(not p:menuPressed(key,true,keys(false),true),'legacy edge on release must not toggle again')
check(p:menuPressed(key,true,keys(true),true));check(not p:menuPressed(key,true,keys(false),false))
-- A complete quick key press between two main-loop frames is not lost.
p:observeMenu(0x100,key,key,0);p:observeMenu(0x101,key,key,0)
check(p:menuPressed(key,true,keys(false),false));check(not p:menuPressed(key,true,keys(false),true))
-- A late WM event for a physical press cannot produce a second toggle.
check(p:menuPressed(key,true,keys(true),false));p:observeMenu(0x100,key,key,0)
check(not p:menuPressed(key,true,keys(false),true))
-- Windows autorepeat and modifiers do not toggle the menu.
p:observeMenu(0x100,key,key,0x40000000);check(not p:menuPressed(key,true,keys(false),false))
p:observeMenu(0x100,key,key,0);check(not p:menuPressed(key,true,keys(true,true),false))
check(not p:menuPressed(key,true,keys(true),false));check(not p:menuPressed(key,true,keys(false),false))
p:observeMenu(0x100,key,key,0);check(not p:menuPressed(key,false,keys(true),false))
check(not p:menuPressed(key,true,keys(true),false));p:menuPressed(key,true,keys(false),false)
-- Legacy-only clients retain edge detection; key changes require a release.
local legacy=input.new(function()return 0 end)
check(legacy:menuPressed(key,true,nil,true));check(not legacy:menuPressed(key,true,nil,true))
check(not legacy:menuPressed(key,true,nil,false));check(legacy:menuPressed(key,true,nil,true))
check(not p:menuPressed(121,true,{physical=true,keys={[121]=true}},true))
check(not p:menuPressed(121,true,{physical=true,keys={[121]=false}},false))
check(p:menuPressed(121,true,{physical=true,keys={[121]=true}},true))
-- Actual PA: F9 opens and stays open with a stale cursor flag, then closes once.
local s=fixture({demo=false});s.step();if s.frames[1].condition()then s.commands.pa26()end;s.step()
s.cursor=true;s.step(16,{[key]=true});check(s.frames[1].condition(),'cursor visibility alone must not lock out the menu')
s.step();check(s.frames[1].condition(),'the new menu must not immediately close')
s.step(16,{[key]=true});check(not s.frames[1].condition());s.step()
s.cursor=false;onWindowMessage(0x100,key,0);onWindowMessage(0x101,key,0);s.step();check(s.frames[1].condition(),'fast WM tap opens the actual menu')
s.step();check(s.frames[1].condition());eq(#s.sent,0)
-- A real input field continues to block F9 and gameplay.
s.commands.pa26();s.chat=true;onWindowMessage(0x100,key,0);s.step(16,{[key]=true});check(not s.frames[1].condition())
onWindowMessage(0x101,key,0);s.chat=false;s.step();onScriptTerminate(s.script)
-- Losing and regaining focus between frames discards a queued old press.
s=fixture({demo=false});s.step();if s.frames[1].condition()then s.commands.pa26()end;s.step()
onWindowMessage(0x100,key,0);onWindowMessage(0x0008,0);onWindowMessage(0x0007,0)
s.step();check(not s.frames[1].condition(),'old queued presses must not reopen after Alt+Tab')
s.step(16,{[key]=true});check(s.frames[1].condition());eq(#s.sent,0);onScriptTerminate(s.script)
