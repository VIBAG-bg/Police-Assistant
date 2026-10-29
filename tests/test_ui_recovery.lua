local fixture=require 'support.fixture'
local core=require 'pa26_core'
local bit=require 'bit'
local name='Police Assistant 2026##pa26-main'
local function healthy(s)
    eq(#s.scopes,0);eq(s.invalidIOReads,0);eq(#s.sent,0)
end
local function physical(s,key)
    s.physicalDown={};s.step();s.physicalDown={[key]=true};s.step();s.step();s.physicalDown={};s.step()
end
-- F9 remains an actual window toggle when mimgui consumes the game's key event
-- while a text field or Ctrl-clicked slider owns keyboard capture.
local s=fixture({consumeKeyboard=true});s.step()
s.io.WantTextInput=true;s.render();s.guiDown={};physical(s,0x78)
check(not s.frames[1].condition());s.io.WantTextInput=false
physical(s,0x78);check(s.frames[1].condition());healthy(s)
-- Dragging a maximally-sized window cannot move it out of view. Geometry is
-- applied before Begin; post-Begin mutations that leave stale clip rects fail.
s.imgui.SetWindowPosVec2=function()error('position changed after Begin')end
s.imgui.SetWindowSizeVec2=function()error('size changed after Begin')end
local w,h=s.io.DisplaySize.x-32,s.io.DisplaySize.y-32
s.resizeWindows={[name]={x=w,y=h}};s.render()
check(bit.band(s.windows[name].flags,s.imgui.WindowFlags.NoMove)~=0)
for _,delta in ipairs({{-500,-500},{500,500},{-1000,1000}})do
    s.activeItem='##move-main';s.io.MouseDelta.x,s.io.MouseDelta.y=delta[1],delta[2];s.render()
    s.activeItem=nil;s.io.MouseDelta.x,s.io.MouseDelta.y=0,0;s.render()
    local r=s.windows[name];eq(r.x,16);eq(r.y,16);eq(r.width,w);eq(r.height,h);healthy(s)
end
check(not s.hasLog('position changed after Begin'));check(not s.hasLog('size changed after Begin'))
require('support.ui_routes').screen(s,'windows')
s.floatEdits={['Непрозрачность']=.66};s.render();s.floatEdits={};s.io.WantTextInput=true;s.render()
physical(s,0x78);check(not s.frames[1].condition());s.io.WantTextInput=false
local alpha=s.savedLibrary().settings.opacity
check(math.abs(alpha-.66)<.00001,'closing F9 while opacity input owns capture must save the latest value')
physical(s,0x78);check(s.frames[1].condition());healthy(s)
-- Recover only UI state. An unsaved binding and user settings survive, while
-- pending sends, native text focus and stale modal input are discarded.
s.page('binds');s.click='+ Новый сценарий ( Добавить бинд )';s.render()
s.edits={['Название##bind']='Черновик после сбоя',['##script']='Не потерять эту строку.'};s.render();s.edits={}
local before=s.workspace.library.profile.accent
-- Force the renderer-failure scene; normal navigation now asks about this draft.
local editor=s.workspace.studio;local guard=editor.requestNavigation
editor.requestNavigation=function(_,action)action();return true end
s.widgetError=true;s.page('addons');s.render();check(s.hasLog('Ошибка интерфейса'));check(not s.frames[1].condition())
s.widgetError=false;s.step(3100);check(s.frames[1].condition());check(s.hasLog('Окна PA восстановлены'))
eq(s.workspace.library.profile.accent,before);s.page('binds');s.click='Сохранить сценарий';s.render();s.step()
local saved=s.savedLibrary()
eq(saved.bindings[#saved.bindings].name,'Черновик после сбоя');eq(saved.bindings[#saved.bindings].script,'Не потерять эту строку.')
editor.requestNavigation=guard
healthy(s)
-- Manual repair works immediately and repeated errors exhaust automatic retries.
s.commands.pa26repair();s.step();check(s.frames[1].condition());healthy(s)
for i=1,4 do
    s.page('binds');s.widgetError=true;s.render();s.widgetError=false;s.step(3100)
end
check(not s.frames[1].condition(),'retry storm must stop')
s.commands.pa26repair();s.step();check(s.frames[1].condition());healthy(s)
onScriptTerminate(s.script)
-- Settings are exposed, saved without a separate button, and survive migration.
s=fixture();s.step();require('support.ui_routes').screen(s,'recovery')
s.toggle='Восстанавливать PA после ошибок##recovery-enabled';s.render()
s.intEdits={['Пауза перед восстановлением, с##recovery-delay_ms']=4,['Попыток подряд##recovery-max_attempts']=2,
    ['Сбросить счётчик после работы без ошибок, с##recovery-stable_ms']=90}
s.render();s.intEdits={}
local config=dofile('moonloader/lib/pa26_config.lua');check(s.saved)
local text=assert(config.serialize(s.saved))
local normalized,notes=core.normalizeConfig(assert(config.parse(text)))
eq(#notes,0);check(not normalized.recovery.enabled);eq(normalized.recovery.delay_ms,4000)
eq(normalized.recovery.max_attempts,2);eq(normalized.recovery.stable_ms,90000)
s.page('binds');s.widgetError=true;s.render();s.widgetError=false;s.step(60000);check(not s.frames[1].condition())
physical(s,0x78);check(s.frames[1].condition(),'F9 can manually recover with automatic recovery disabled')
healthy(s);onScriptTerminate(s.script)
-- A recovery never resumes the tail of a previously executing real bind.
local model=require 'pa26_bindings';local seed=model.defaults(core.defaults())
seed.bindings[1].target_required=false;seed.bindings[1].script='Первая строка\n@wait(10000)\nНе повторять после восстановления'
s=fixture({demo=false,library=seed,categoryWheel=true});s.step();s.commands.pa26run('1');s.step(100);s.step(100);eq(#s.sent,1)
if not s.frames[1].condition()then s.commands.pa26();s.step()end
s.page('binds');s.widgetError=true;s.render();check(s.hasLog('Ошибка интерфейса'))
s.widgetError=false;s.step(3100);s.step(20000)
eq(#s.sent,1);check(not s.runtime.demo);check(s.workspace.executor.queue==nil)
eq(#s.scopes,0);onScriptTerminate(s.script)
