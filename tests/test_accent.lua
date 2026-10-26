local core=require 'pa26_core'
local model=require 'pa26_bindings'
local binder=require 'pa26_binder'
local fixture=require 'support.fixture'
local prefix='[Русский акцент]:'
local libraryPath='moonloader\\config\\police_assistant_2026_library.json'

-- Speech is transformed once; action/command text is untouched.
eq(model.applyAccent('Здравствуйте.',prefix),prefix..' Здравствуйте.')
eq(model.applyAccent(prefix..' Здравствуйте.',prefix),prefix..' Здравствуйте.')
eq(model.applyAccent(prefix..'Здравствуйте.',prefix),prefix..'Здравствуйте.')
for _,value in ipairs({'','  ','Без акцента','нет акцента','НЕТ','none'}) do
    eq(model.applyAccent('Здравствуйте.',value),'Здравствуйте.')
end
for _,line in ipairs({'/me достал удостоверение','/do Удостоверение в руке.','/r Доклад.','  /me действие','  '}) do
    eq(model.applyAccent(line,prefix),line)
end
check(not model.applyAccent('Текст.','Строка\nещё строка'))
eq(model.applyAccent('Russian-speaking','Russian'),'Russian Russian-speaking','a word prefix must not swallow a longer word')
local info=model.variableInfo('accent'); eq(info.kind,'profile'); check(info.detail:find('автоматически',1,true))

local binding=model.newBinding(7)
local ctx={values={accent=prefix},gender='male',session='test',now=10000,demo=false}
binding.script='Здравствуйте.\n/me достал удостоверение\n/do Удостоверение в руке.\n{accent} Уже с префиксом.'
local plan,err=binder.compile(binding,ctx,{},codec)
check(plan,err); check(not plan.requirements.target); check(not plan.requirements.closest)
eq(plan.lines[1],'Здравствуйте.'); eq(plan.lines[2],'/me достал удостоверение')
eq(plan.lines[3],'/do Удостоверение в руке.'); eq(plan.lines[4],prefix..' Уже с префиксом.')
for i,line in ipairs(plan.lines) do eq(codec.decode(plan.wire[i]),line) end
ctx.values.accent=''
plan,err=binder.compile(binding,ctx,{},codec); check(plan,err); eq(plan.lines[1],'Здравствуйте.')
ctx.values.accent=prefix; binding.script='@random(Здравствуйте.|Добрый день.)'
plan,err=binder.compile(binding,ctx,{},codec,function() return 2 end)
check(plan,err); eq(plan.lines[1],'Добрый день.')
local capacity=90-#codec.encode(prefix)-1
binding.script='{accent} '..string.rep('Я',capacity)
plan,err=binder.compile(binding,ctx,{},codec); check(plan,err); eq(#plan.wire[1],90)
binding.script='{accent} '..string.rep('Я',capacity+1)
plan,err=binder.compile(binding,ctx,{},codec);check(plan,err);check(#plan.lines>1)
for _,wire in ipairs(plan.wire)do check(#wire<=90,'The accent is included in the complete part budget')end
binding.script='{accent} @random(Коротко.|'..string.rep('Я',91)..')'
check(not binder.compile(binding,ctx,{},codec,function() return 1 end),'every random variant must fit, not only the selected one')
ctx.values.accent='🙂'; binding.script='{accent} Текст.'
check(not binder.compile(binding,ctx,{},codec),'unsupported CP1251 accent must not send replacement characters')

local function open(s,page)
    if not s.frames[1].condition() then s.commands.pa26() end
    s.page(page)
end
local function saveAccent(s,value)
    open(s,'settings'); require('support.ui_routes').chat(s,'accent')
    s.edits={['Акцент##profile']=value}; s.render()
    s.step(650)
    eq(s.savedLibrary().profile.accent,value)
end
local function createSpeech(s,script)
    open(s,'binds'); s.click='+ Новый сценарий ( Добавить бинд )'; s.render()
    s.edits={['Название##bind']='Речь с акцентом',['Команда запуска (pa26_имя)##bind']='pa26_accent',['##script']=script}
    s.render(); s.click='Общее##editor-tab'; s.render()
    s.click='Сохранить сценарий'; s.render(); s.step()
end
local function outbound(s,line)
    local old=s.chat;s.chat=true
    local result=s.events.onSendChat(codec.encode(line));s.chat=old
    if type(result)=='table' then return codec.decode(result[1]) end
    if result==false then return false end
    return line
end
local function start(s)
    check(s.commands.pa26_accent); s.commands.pa26_accent(''); s.step(16); s.step(100)
end

-- The actual script hook uses saved state, not an unsaved text buffer.
local s=fixture({demo=false}); s.step()
check(type(s.events.onSendChat)=='function'); eq(outbound(s,'Здравствуйте.'),'Здравствуйте.')
saveAccent(s,prefix)
eq(outbound(s,'Здравствуйте.'),prefix..' Здравствуйте.')
eq(outbound(s,prefix..' Уже есть.'),prefix..' Уже есть.')
for _,line in ipairs({'/me действие','/do Действие.','/b OOC','/r Доклад.'}) do eq(outbound(s,line),line) end
s.edits={['Акцент##profile']=''}; s.render()
eq(outbound(s,'Несохранённое поле.'),prefix..' Несохранённое поле.')
s.libraryWriteFail=true; s.step(650)
eq(outbound(s,'Не удалось сохранить.'),prefix..' Не удалось сохранить.')
s.click='ОК##warning-ok'; s.render(); s.render()
s.libraryWriteFail=false; s.click='Повторить запись##autosave-profile'; s.render(); s.step()
eq(outbound(s,'Теперь без акцента.'),'Теперь без акцента.')
eq(s.savedLibrary().profile.accent,'')
saveAccent(s,prefix)
local sentBefore=#s.sent
-- The original 127-byte single-message contract remains available when the
-- newly configurable manual splitter is explicitly disabled.
s.workspace.library.settings.manual_chat.enabled=false
local manualCapacity=core.WIRE_LIMIT-#codec.encode(prefix)-1
eq(outbound(s,string.rep('Я',manualCapacity)),prefix..' '..string.rep('Я',manualCapacity))
eq(outbound(s,string.rep('Я',manualCapacity+1)),false)
eq(#s.sent,sentBefore,'a rejected manual line is not resent by the helper')
check(s.localChat[#s.localChat]:find('127 байт',1,true)); check(s.hasLog('Сообщение не отправлено'))
s.workspace.library.settings.manual_chat.enabled=true

-- Bind preview and execution share a frozen prefix. Profile changes affect the next run.
createSpeech(s,'{accent} Первая.\n@wait(5000)\n{accent} Вторая.\n/me действие\n/do Действие.')
start(s); eq(#s.sent,1); eq(s.sent[1].line,prefix..' Первая.')
saveAccent(s,'[Американский акцент]:')
eq(outbound(s,'Вручную.'),'[Американский акцент]: Вручную.')
s.step(5000); s.step(); s.step(1500); s.step(1500)
eq(#s.sent,4); eq(s.sent[2].line,prefix..' Вторая.'); eq(s.sent[3].line,'/me действие'); eq(s.sent[4].line,'/do Действие.')
saveAccent(s,''); s.sent={}; s.step(1500); start(s)
eq(s.sent[1].line,' Первая.'); s.step(); s.step(5000); s.step(); s.step(1500); s.step(1500)
eq(#s.sent,4); eq(s.sent[2].line,' Вторая.')
onScriptTerminate(s.script); eq(s.events.onSendChat,nil)

-- Failed native send releases ownership, so subsequent ordinary chat still receives the prefix.
s=fixture({demo=false}); s.step(); saveAccent(s,prefix); createSpeech(s,'Проверка отправки.')
s.sendError=true; start(s); eq(#s.sent,0); check(s.hasLog('Ошибка отправки'))
s.sendError=false; eq(outbound(s,'Ручное сообщение.'),prefix..' Ручное сообщение.')
onScriptTerminate(s.script)

-- Preserve the previous hook's edits/cancellation and restore only our own handler.
local previousCalls=0
local previous=function(raw)
    previousCalls=previousCalls+1
    local line=codec.decode(raw)
    if line=='Отменить.' then return false end
    if line=='Заменить.' then return {codec.encode('Изменено.')} end
end
s=fixture({sendChatHandler=previous}); s.step(); saveAccent(s,prefix)
eq(outbound(s,'Заменить.'),prefix..' Изменено.'); eq(outbound(s,'Отменить.'),false)
eq(outbound(s,'Оставить.'),prefix..' Оставить.'); eq(previousCalls,3)
onScriptTerminate(s.script); eq(s.events.onSendChat,previous)
s=fixture({sendChatHandler=previous}); s.step(); saveAccent(s,prefix)
local later=function() return false end
s.events.onSendChat=later; onScriptTerminate(s.script); eq(s.events.onSendChat,later)

-- Native pre-Enter input preparation also works when SAMP.Lua is unavailable.
s=fixture({demo=false,sampEvents=false}); s.step(); saveAccent(s,prefix)
eq(s.events.onSendChat,nil);s.chat=true;s.chatText=codec.encode('Ручной чат.');onWindowMessage(0x0100,0x0D)
eq(codec.decode(s.chatText),prefix..' Ручной чат.');eq(#s.sent,0);s.chat=false
createSpeech(s,'Проверка без SAMP.Lua.'); start(s)
eq(#s.sent,1); eq(s.sent[1].line,'Проверка без SAMP.Lua.')
onScriptTerminate(s.script)

-- Regression for hover text squeezed into a column and glyph-dependent action buttons.
s=fixture(); s.step(); open(s,'binds')
s.wrapValues={}; s.hover='##bind-up1'; s.render()
check(s.triangleIcons>0)
local explicitWrap=false
for _,width in ipairs(s.wrapValues) do if width>=360 and width<700 then explicitWrap=true end end
check(explicitWrap,'information tooltip must use an explicit positive wrap width')
local play,information,title
for _,call in ipairs(s.buttonCalls) do
    if call.label=='##bind-run1' then play=call end
    if call.label=='##bind-up1' then information=call end
    if call.label:find('##bind1',1,true) and not call.label:find('info',1,true) then title=call end
end
check(play and information and title); eq(play.width,34); eq(play.height,34); eq(information.width,34); eq(information.height,20)
s.io.DisplaySize.x,s.io.DisplaySize.y=640,480; s.wrapValues={}; s.render()
check(#s.scopes==0); check(not s.hasLog('Ошибка отрисовки'))
onScriptTerminate(s.script)
