local core=require'pa26_core';local model=require'pa26_bindings';local rules=require'pa26_chat_text';local fixture=require'support.fixture'
local settings={manual_radio_prefix=true,local_tag='[SIGMA]:'}
local cases={{'/r Доклад.','/r [SIGMA]: Доклад.'},{'/R Доклад.','/R [SIGMA]: Доклад.'},
    {'  /r   Доклад.  ','  /r   [SIGMA]: Доклад.  '},{'/r [SIGMA]: Доклад.','/r [SIGMA]: Доклад.'},
    {'/r [SIGMA]:Доклад.','/r [SIGMA]:Доклад.'},{'.к Доклад.','/r [SIGMA]: Доклад.'}}
for _,row in ipairs(cases)do
    for _,utf in ipairs({true,false})do
        local raw=utf and row[1]or codec.encode(row[1]);local actual,err=model.submitSpeech(raw,'[Акцент]:',codec,utf,settings)
        check(actual,err);eq(utf and actual or codec.decode(actual),row[2])
    end
end
for _,text in ipairs({'/r','/r ','/r     ','/rn Доклад.','/radio Доклад.','/r1 Текст.','/r_foo','/f Доклад.','/d Доклад.',
    '/me /r текст.','/do Слышен /r.','!r Доклад.','.5','Текст /r','Привет.'})do
    local result,used=rules.radioCommand(text,settings);eq(result,text);eq(used,false)
end
for _,tag in ipairs({'SIGMA','[Сигма]:','Альфа','%s[%1]:','S:','[1]:'})do
    local cfg={local_tag=tag};eq(rules.radioCommand('/r Текст.',cfg),'/r '..tag..' Текст.')
    eq(rules.radioCommand('/r '..tag..' Текст.',cfg),'/r '..tag..' Текст.')
end
eq(rules.radioCommand('/r SIGMAish',{local_tag='SIGMA'}),'/r SIGMA SIGMAish')
eq(rules.radioCommand('/r Доклад.',{local_tag='',manual_radio_prefix=true}),'/r Доклад.')
eq(rules.radioCommand('/r Доклад.',{local_tag='[SIGMA]:',manual_radio_prefix=false}),'/r Доклад.')
eq(rules.policy(settings).radioPrefix.localTag,'[SIGMA]:');eq(rules.policy(settings).radioPrefix.enabled,true)
local capacity=127-#('/r [SIGMA]: ')
check(model.submitSpeech('/r '..string.rep('Я',capacity),'',codec,true,settings))
check(not model.submitSpeech('/r '..string.rep('Я',capacity+1),'',codec,true,settings))
check(not model.submitSpeech('/r Привет 🙂','',codec,true,settings))
check(not model.submitSpeech('/r Текст\n/help','',codec,true,settings))
local old=model.defaults(core.defaults());old.settings.manual_radio_prefix=nil;old.profile.local_tag='[SIGMA]:'
local migrated=assert(model.validate(old,core.defaults()));eq(migrated.settings.manual_radio_prefix,true);eq(migrated.profile.local_tag,'[SIGMA]:')
old.settings.manual_radio_prefix=false;eq(assert(model.validate(old,core.defaults())).settings.manual_radio_prefix,false)
old.settings.manual_radio_prefix='yes';check(not model.validate(old,core.defaults()))
local function setup(options)
    local seed=model.defaults(core.defaults());seed.profile.local_tag='[SIGMA]:';seed.profile.accent='[Акцент]:'
    seed.settings.accent_live_input=false;seed.settings.chat_dot_commands=false
    local b=model.newBinding(77);b.command='pa26_testmanualradio';b.script='/r Свой шаблон.'
    seed.bindings[#seed.bindings+1]=b;seed.next_id=78
    local opts={demo=false,library=seed};for k,v in pairs(options or{})do opts[k]=v end
    local s=fixture(opts);s.step();if s.frames[1].condition()then s.commands.pa26()end;s.chat=true;return s
end
-- Enter works even with no accent, dot conversion disabled, and no RPC module.
for _,events in ipairs({true,false})do
    local s=setup({sampEvents=events});s.chatText=codec.encode('/r Доклад.');s.step();onWindowMessage(0x100,13)
    eq(codec.decode(s.chatText),'/r [SIGMA]: Доклад.');eq(#s.sent,0)
    if events then
        s.chat=false;local result=s.events.onSendCommand(s.chatText);eq(result,nil,'prefix already prepared once')
    end
    onScriptTerminate(s.script)
end
-- RPC-before-WindowMessage uses an exact match against the current input only.
local s=setup();s.chatText=codec.encode('/r Доклад.');s.step()
local actual=s.events.onSendCommand(s.chatText);check(type(actual)=='table');eq(codec.decode(actual[1]),'/r [SIGMA]: Доклад.')
eq(s.events.onSendCommand(codec.encode('/r Автоматическая строка.')),nil)
s.chat=false;eq(s.events.onSendCommand(codec.encode('/r Доклад.')),nil)
s.chat=true;s.chatText=codec.encode('/r '..string.rep('Я',127));s.step();onWindowMessage(0x100,13)
check(s.messageConsumed);eq(codec.decode(s.chatText),'/r '..string.rep('Я',127));eq(#s.sent,0)
onScriptTerminate(s.script)
-- A previous handler can cancel; a PA bind with /r keeps its authored text.
s=setup({sendCommandHandler=function()return false end});s.chatText=codec.encode('/r Доклад.');eq(s.events.onSendCommand(s.chatText),false);onScriptTerminate(s.script)
local attempts=0
s=setup({sendCommandHandler=function()attempts=attempts+1;if attempts==1 then return false end end})
local original=codec.encode('/r Доклад.');s.chatText=original;onWindowMessage(0x100,13);s.chat=false
eq(s.events.onSendCommand(original),false);eq(s.events.onSendCommand(original),nil,'cancelled Enter cannot tag a later automatic command');onScriptTerminate(s.script)
for _,kind in ipairs({'timeout','focus','session'})do
    s=setup();s.chatText=original;onWindowMessage(0x100,13);s.chat=false
    if kind=='timeout'then s.step(1100)
    elseif kind=='focus'then onWindowMessage(0x8,0);onWindowMessage(0x7,0)
    else s.address='different.server';s.step()end
    eq(s.events.onSendCommand(original),nil,kind);onScriptTerminate(s.script)
end
s=setup();s.chat=false;s.step();s.commands.pa26_testmanualradio('')
s.step();s.step(100);eq(#s.sent,0);check(s.workspace.studio.confirmPlan)
s.click='ДА##confirm-yes';s.render();s.step();s.step(100)
eq(#s.sent,1);eq(s.sent[1].line,'/r Свой шаблон.');onScriptTerminate(s.script)
-- A converted native Chat RPC follows the same rule, once, on the next frame.
s=setup({chatInputBackend=false});s.workspace.library.settings.chat_dot_commands=true;onWindowMessage(0x100,13)
eq(s.events.onSendChat(codec.encode('.к Доклад.')),false);s.chat=false;s.step()
eq(#s.sent,1);eq(s.sent[1].line,'/r [SIGMA]: Доклад.');s.step();eq(#s.sent,1);onScriptTerminate(s.script)
-- The GUI switch, literal profile tag and existing bindings survive autosave.
s=setup();s.chat=false;s.commands.pa26();s.page('settings');require('support.ui_routes').chat(s,'accent')
local count=#s.workspace.library.bindings;s.toggle='Добавлять префикс локальной волны в мой /r##manual-radio-prefix';s.render();s.step(650)
local saved=s.savedLibrary()
eq(saved.settings.manual_radio_prefix,false);eq(saved.profile.local_tag,'[SIGMA]:');eq(#saved.bindings,count)
check(not s.hasLog('Ошибка интерфейса'));eq(#s.sent,0);onScriptTerminate(s.script)
