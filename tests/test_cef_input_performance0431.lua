-- Regressions for the typing hot path, not wall-clock timing assertions.
local fixture=require 'support.fixture'
local s=fixture({demo=false,render=false});s.step()
if s.frames[1].condition()then s.commands.pa26();s.step()end
local bridge=s.chatBridge
bridge.server={accept=function()return nil,'timeout'end,close=function()end}
local function input(chat,dialog)
    bridge.state={at=s.now,busy=chat or dialog,chat=chat,dialog=dialog}
end
input(true,false);s.step()
local counts={workspace=0,modal=0,input=0,assets=0}
local function wrap(object,key,counter)
    local original=object[key]
    object[key]=function(self,...)counts[counter]=counts[counter]+1;return original(self,...)end
end
wrap(s.workspace,'cancel','workspace');wrap(s.workspace.studio,'cancelModal','modal')
wrap(bridge,'inputBusy','input');wrap(bridge,'installed','assets')
local consumed=s.consumed
for _=1,100 do
    for _,message in ipairs({0x102,0x103,0x10D,0x10F,0x200,0x201,0x202})do onWindowMessage(message,0x49,0)end
end
eq(counts.input,0,'character/IME/mouse selection must not query the bridge')
eq(counts.modal,0);eq(counts.workspace,0);eq(s.consumed,consumed)
for _=1,100 do
    for _,key in ipairs({0x41,0x49,0x4A,0x4B,0x54,0x25,0x27,0x08})do
        onWindowMessage(0x100,key,0);onWindowMessage(0x101,key,0)
    end
end
eq(counts.modal,0,'ordinary CEF typing cannot reset modal state')
eq(counts.workspace,0,'ordinary CEF typing cannot cancel an idle workspace')
eq(s.consumed,consumed);eq(#s.sent,0)
for _=1,400 do input(true,false);s.step(16)end
eq(counts.assets,0,'no periodic asset filesystem verification while typing')
eq(counts.modal,0,'idle typing frames cannot repeat modal resets');eq(counts.workspace,0)
-- Weapon keys remain blocked for the game, while their text messages pass.
for _,key in ipairs({0x31,0x69,0x51,0x45})do
    consumed=s.consumed;onWindowMessage(0x100,key,0);check(s.consumed>consumed)
    consumed=s.consumed;onWindowMessage(0x102,key,0);eq(s.consumed,consumed)
    input(false,false);consumed=s.consumed;onWindowMessage(0x101,key,0)
    check(s.consumed>consumed,'a held guard key release is cleaned after closing chat')
    input(true,false)
end
input(false,false);s.step();check(counts.assets>0,'deferred asset check resumes when input closes')
local checked=counts.assets;s.step();eq(counts.assets,checked,'asset repair stays deadline bounded')
-- A new action/UI that really needs cancellation is still closed exactly once.
s.commands.pa26();s.step();check(s.frames[1].condition())
input(true,false);local resets=counts.modal;s.step();check(not s.frames[1].condition());check(counts.modal>resets)
resets=counts.modal;input(true,false);s.step();eq(counts.modal,resets)
-- A genuine queued bind is cancelled on opening chat and never resumes itself.
input(false,false);s.step()
local model=require 'pa26_bindings'
local item=model.newBinding(990);item.command='pa26_inputtest';item.script='Один.\n@wait(1500)\nДва.'
s.workspace.library.bindings[#s.workspace.library.bindings+1]=item
s.workspace:request({kind='prepare',id=990,start=true,returnTo='quick'});s.step();s.step(100)
check(s.workspace.executor.queue);local sent=#s.sent
input(true,false);s.step();eq(s.workspace.executor.queue,nil)
input(false,false);s.step(2000);eq(#s.sent,sent,'interrupted sends cannot return after chat closes')
onScriptTerminate(s.script)
-- Deadline checks do not build settings on every frame; busy inputs defer reads.
local m=require 'pa26_chat_bridge';local reads,settings=0,0
local b=m.new({path='virtual/',assetFs={read=function()reads=reads+1;return nil end},
    settings=function()settings=settings+1;return{enabled=true}end})
b.server={accept=function()return nil,'timeout'end};b.waitWarned=true
for _,dialog in ipairs({false,true})do
    for now=1,500 do b.state={at=now,busy=true,chat=not dialog,dialog=dialog};b:tick(now)end
end
eq(reads,0);eq(settings,0)
b.assetAt=501;b.state={at=502,busy=false,chat=false,dialog=false}
for now=502,600 do b:tick(now)end
eq(reads,0);eq(settings,0,'not-due asset checks do not build the settings payload')
b:close()
