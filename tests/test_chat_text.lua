local rules=require 'pa26_chat_text'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local fixture=require 'support.fixture'
local assist=require 'pa26_assist_settings'
local prefix='[Русский акцент]:'
local cases={
    {'.к Запрашиваю помощь.','/r Запрашиваю помощь.'},{'.ыефеы','/stats'},
    {'.К  Запрашиваю помощь.  ','/R  Запрашиваю помощь.  '},
    {'.stats 37','/stats 37'},{'.ЫЕФЕЫ','/STATS'},{'.pa26_имя','/pa26_bvz'},
    {'.su 37 2 "Причина. Ещё причина."','/su 37 2 "Причина. Ещё причина."'},
    {'.nosuchcommand123 _текст_ /r .к ! ( )','/nosuchcommand123 _текст_ /r .к ! ( )'},
}
for _,row in ipairs(cases)do
    local text,converted=rules.dotCommand(row[1]);eq(text,row[2]);eq(converted,true)
    for _,utf in ipairs({true,false})do
        local raw=utf and row[1]or codec.encode(row[1]);local actual,err,changed=model.submitSpeech(raw,prefix,codec,utf)
        check(actual,err);eq(utf and actual or codec.decode(actual),row[2]);eq(changed,true)
    end
end
local untouched={'','.', '..','...', '.5','.123','.5 текст','. Привет','.\tstats',
    ' .ыефеы','\t.ыефеы','Текст .к','Привет.','/r Текст.','!r Текст.',
    '.foo.com','.stats/37','.r,','.r-1','._stats','.r🙂','.ю','.х','.ё','.ї',
    '．ыефеы',') .к','( .к'}
for _,text in ipairs(untouched)do local actual,converted=rules.dotCommand(text);eq(actual,text,text);eq(converted,false,text)end
eq(rules.dotCommand('.ыефеы',{chat_dot_commands=false}),'.ыефеы')
local policy=rules.policy();eq(policy.version,1);eq(policy.keyboardMap['к'],'r');eq(policy.keyboardMap['Ы'],'S')
policy.keyboardMap['к']='x';eq(rules.policy().keyboardMap['к'],'r','exported map cannot mutate native rules')
for _,text in ipairs({'(привет',') Привет','   ) Привет','\t( привет'})do
    for _,utf in ipairs({true,false})do
        local raw=utf and text or codec.encode(text);eq(model.manualSpeech(raw,prefix,codec,utf),raw)
        local result,owned=model.liveSpeech(raw,prefix,codec,nil);eq(result,raw);eq(owned,nil)
    end
end
eq(model.manualSpeech('Привет (текст).',prefix,codec,true),prefix..' Привет (текст).')
eq(model.manualSpeech(') Привет.',prefix,codec,true,{accent_skip_brackets=false}),prefix..' ) Привет.')
eq(model.applyAccent(') Явный {accent}.',prefix),prefix..' ) Явный {accent}.','explicit bind accents retain author intent')
eq(model.liveSpeech('.к',prefix,codec),'.к','never convert unfinished input')
local _,owned=model.liveSpeech('Привет',prefix,codec)
eq(model.liveSpeech(owned..'.к Текст.',prefix,codec,owned),'.к Текст.')
eq(model.submitSpeech(owned..'.к Текст.',prefix,codec,true,nil,owned),'/r Текст.')
eq(model.submitSpeech('.к Текст.','',codec,true),'/r Текст.','conversion independent of accent')
eq(model.submitSpeech('.к Текст.',prefix,codec,true,{chat_dot_commands=false}),prefix..' .к Текст.')
eq(model.submitSpeech('.r '..string.rep('Я',124),prefix,codec,true),'/r '..string.rep('Я',124))
local long,err=model.submitSpeech('.r '..string.rep('Я',125),prefix,codec,true);check(not long);check(err:find('127',1,true))
check(not model.submitSpeech('.r Привет 🙂',prefix,codec,true))
check(not model.submitSpeech('.r\tТекст',prefix,codec,true),'control characters must not enter wire')
check(not model.submitSpeech('.r\n/help',prefix,codec,true),'multiline command must not enter wire')
local old=model.defaults(core.defaults());old.settings.accent_skip_brackets=nil;old.settings.chat_dot_commands=nil
local migrated=assert(model.validate(old,core.defaults()));eq(migrated.settings.chat_dot_commands,true);eq(migrated.settings.accent_skip_brackets,true)
for _,name in ipairs({'chat_dot_commands','accent_skip_brackets'})do
    old.settings[name]=false;eq(assert(model.validate(old,core.defaults())).settings[name],false)
    old.settings[name]='yes';check(not model.validate(old,core.defaults()));old.settings[name]=nil
end
local notices=assist.defaults();eq(notices.interaction.started_detail,'Саспект выбран.')
notices.interaction.started_detail='Собеседник выбран.';eq(assert(assist.validate(notices)).interaction.started_detail,'Саспект выбран.')
notices.interaction.started_detail='Выбран {name} [{id}].';eq(assert(assist.validate(notices)).interaction.started_detail,'Выбран {name} [{id}].')

local function setup(extra)
    local seed=model.defaults(core.defaults());seed.profile.accent=prefix
    local options={demo=false,library=seed};for k,v in pairs(extra or{})do options[k]=v end
    local s=fixture(options);s.step();if s.frames[1].condition()then s.commands.pa26()end;s.chat=true;return s
end
-- Native field is changed just before Enter, with and without SAMP.Lua.
for _,events in ipairs({true,false})do
    for _,utf in ipairs({true,false})do
        local s=setup({sampEvents=events});local encode=function(text)return utf and text or codec.encode(text)end
        s.chatText=encode('.к Запрашиваю помощь.');s.step();eq(s.chatText,encode('.к Запрашиваю помощь.'))
        onWindowMessage(0x100,13);eq(s.chatText,encode('/r Запрашиваю помощь.'));eq(#s.sent,0)
        s.workspace.library.settings.accent_live_input=false;s.chatText=encode('.ыефеы');onWindowMessage(0x100,13);eq(s.chatText,encode('/stats'))
        s.workspace.library.settings.chat_dot_commands=false;s.chatText=encode('.ыефеы');onWindowMessage(0x100,13);eq(s.chatText,encode('.ыефеы'))
        s.workspace.library.settings.accent_live_input=true;s.chatText=encode(') Привет.');s.step();eq(s.chatText,encode(') Привет.'))
        onWindowMessage(0x100,13);eq(s.chatText,encode(') Привет.'));eq(#s.sent,0);onScriptTerminate(s.script)
    end
end
-- With no input APIs, cancel the Chat RPC and send exactly one Command RPC.
local s=setup({chatInputBackend=false});onWindowMessage(0x100,13)
eq(s.events.onSendChat(codec.encode('.к Доклад.')),false);eq(#s.sent,0)
eq(s.events.onSendChat(codec.encode('.к Доклад.')),false,'duplicate callback is cancelled')
s.chat=false;s.step();eq(#s.sent,1);eq(s.sent[1].line,'/r Доклад.');s.step();eq(#s.sent,1)
s.chat=true;onWindowMessage(0x100,13);eq(s.events.onSendChat(codec.encode('.unknown_command')),false)
s.chat=false;s.step();eq(#s.sent,2);eq(s.sent[2].line,'/unknown_command','server decides whether a generic command exists')
onScriptTerminate(s.script)
-- Cancellation by previous handlers wins; focus/session/time changes drop work.
s=setup({chatInputBackend=false,sendChatHandler=function()return false end});onWindowMessage(0x100,13)
eq(s.events.onSendChat(codec.encode('.ыефеы')),false);s.chat=false;s.step();eq(#s.sent,0);onScriptTerminate(s.script)
for _,kind in ipairs({'focus','timeout','disabled','session'})do
    s=setup({chatInputBackend=false});onWindowMessage(0x100,13);eq(s.events.onSendChat(codec.encode('.ыефеы')),false)
    if kind=='focus'then onWindowMessage(0x8,0);onWindowMessage(0x7,0)
    elseif kind=='disabled'then s.workspace.library.settings.chat_dot_commands=false
    elseif kind=='session'then s.address='new.server'end
    s.chat=false;s.step(kind=='timeout'and 1100 or 16);eq(#s.sent,0,kind);onScriptTerminate(s.script)
end
s=setup({chatInputBackend=false});onWindowMessage(0x100,13);eq(s.events.onSendChat(codec.encode('.pa26unknown')),false)
s.chat=false;s.step();eq(#s.sent,0);check(s.hasLog('нет такой команды'));onScriptTerminate(s.script)
-- Real profile controls autosave explicit off and leave binds/profile intact.
s=setup();s.chat=false;if not s.frames[1].condition()then s.commands.pa26()end;s.page('settings')
require('support.ui_routes').chat(s,'accent');local before=model.copy(s.workspace.library.bindings)
local function same(a,b)
    eq(type(a),type(b));if type(a)~='table'then eq(a,b);return end
    for key,value in pairs(a)do same(value,b[key])end
    for key in pairs(b)do check(a[key]~=nil)end
end
for _,row in ipairs({{'chat_dot_commands','Команды с точкой на русской раскладке##chat-dot-commands'},
    {'accent_skip_brackets','Без акцента после ( и ) в начале сообщения##accent-brackets'}})do
    s.toggle=row[2];s.render();s.step(650)
    local saved=s.savedLibrary()
    eq(saved.settings[row[1]],false);eq(assert(model.validate(saved,core.defaults())).settings[row[1]],false)
    same(saved.bindings,before);eq(saved.profile.accent,prefix)
end
check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0);onScriptTerminate(s.script)
