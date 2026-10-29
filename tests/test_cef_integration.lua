local fixture=require 'support.fixture';local model=require 'pa26_bindings';local core=require 'pa26_core'
local seed=model.defaults(core.defaults());seed.profile.accent='[Русский акцент]:'
local s=fixture({demo=false,library=seed});s.step()
local bridge=s.chatBridge;check(bridge);check(bridge.commands.pa26)
local function poll(chat,events)
    for _,event in ipairs(events or{})do event.session=bridge.env.session()end
    return bridge:exchange(encodeJson({schema=1,page='test-cef',chat=chat,dialog=false,busy=chat,events=events or{}}),s.now)
end
-- CEF chat is active while the native chat API reports false.
eq(s.chat,false);check(poll(true));s.step(16,{[120]=true});eq(s.frames[1].condition(),false,'F9 must not open over CEF typing')
eq(#s.sent,0);check(s.imgui.DisableInput)
check(poll(false));s.step();s.step(16,{[120]=true});check(s.frames[1].condition());s.step()
-- A stale generic cursor flag is not evidence that the CEF chat owns input.
s.commands.pa26();s.step();check(not s.frames[1].condition())
s.cursor=true;s.step(16,{[120]=true});check(s.frames[1].condition());eq(#s.sent,0)
s.step();check(s.frames[1].condition());s.cursor=false;s.commands.pa26();check(poll(false));s.step()
-- /pa26 typed in the CEF chat executes the registered callback once, not a server send.
check(poll(false,{{id=1,kind='local',text='/pa26'}}));s.step();check(s.frames[1].condition());eq(#s.sent,0)
check(poll(false,{{id=1,kind='local',text='/pa26'}}));s.step();check(s.frames[1].condition(),'retry must not execute the command twice')
-- Native and CEF incoming messages share filters and identity processing.
s.workspace.library.filters={{enabled=true,prefix='HIDE:'}}
local r=decodeJson(assert(poll(false,{{id=2,kind='message',text='HIDE: text'}})));eq(r.filters[1],'HIDE:')
eq(s.events.onServerMessage(1,codec.encode('HIDE: text')),false)
-- No implicit accent on another script's outgoing chat when input is closed.
local text=codec.encode('Автоматическая реплика.');eq(s.events.onSendChat(text),nil)
s.workspace.library.settings.accent_live_input=false;s.chat=true;s.chatText=codec.encode('Привет');s.step();onWindowMessage(0x0100,0x0D)
eq(codec.decode(s.chatText),'Привет');eq(s.events.onSendChat(s.chatText),nil)
s.chat=false;s.workspace.library.settings.cef_chat_support=false
r=decodeJson(assert(poll(false)));check(not r.enabled)
onScriptTerminate(s.script);check(bridge.closed)
-- An old saved library gains CEF support without resetting a user's explicit accent switch.
seed.settings.cef_chat_support=nil;seed.settings.accent_live_input=false
local valid=assert(model.validate(seed,core.defaults()));check(valid.settings.cef_chat_support);check(not valid.settings.accent_live_input)
-- The GUI uses one master accent switch and persists the CEF switch independently.
s=fixture({demo=false,library=seed});s.step();if not s.frames[1].condition()then s.commands.pa26()end;s.page('settings');require('support.ui_routes').chat(s,'accent')
s.toggle='Добавлять акцент при отправке обычной речи##accent-live';s.render();s.step(650);check(s.workspace.library.settings.accent_live_input)
require('support.ui_routes').chat(s,'filters');s.toggle='Поддержка чата лаунчера##cef-chat';s.render();s.step(650);check(not s.workspace.library.settings.cef_chat_support)
local saved=s.savedLibrary()
check(saved.settings.accent_live_input);check(not saved.settings.cef_chat_support);eq(saved.profile.accent,seed.profile.accent)
onScriptTerminate(s.script)
-- Ordinary bind speech is exact, and opening CEF input cancels the remaining steps.
local b=model.newBinding(90);b.command='pa26_ceftest';b.script='Первая.\n@wait(1500)\nВторая.'
seed=model.defaults(core.defaults());seed.profile.accent='[Русский акцент]:';seed.bindings[#seed.bindings+1]=b;seed.next_id=91
s=fixture({demo=false,library=seed});s.step();s.commands.pa26_ceftest('');s.step();s.step(100)
eq(#s.sent,1);eq(s.sent[1].line,'Первая.')
bridge=s.chatBridge;check(poll(true));s.step(1600);eq(#s.sent,1)
check(poll(false));s.step(1600);eq(#s.sent,1,'opening chat must not leave an old bind that sends later')
onScriptTerminate(s.script)
