local model=require 'pa26_bindings';local core=require 'pa26_core';local fixture=require 'support.fixture'
local prefix='[Русский акцент]:'
for _,utf in ipairs({false,true})do
    local function encode(s)return utf and s or codec.encode(s)end
    local raw=encode('Привет!');local prepared,owned=model.liveSpeech(raw,prefix,codec)
    eq(prepared,encode(prefix..' Привет!'));check(owned)
    local repeated,newOwned=model.liveSpeech(prepared,prefix,codec,owned);eq(repeated,prepared);eq(newOwned,owned)
    local command=model.liveSpeech(owned..encode('/me действие'),prefix,codec,owned);eq(command,encode('/me действие'))
    eq(model.liveSpeech(prepared,'',codec,owned),raw)
    eq(model.liveSpeech(owned,prefix,codec,owned),'')
    eq(model.liveSpeech(encode('/do Описание.'),prefix,codec),encode('/do Описание.'))
    local changed=model.liveSpeech(prepared,'[Акцент]:',codec,owned);eq(changed,encode('[Акцент]: Привет!'))
end
local seed=model.defaults(core.defaults());seed.profile.accent=prefix
for _,events in ipairs({true,false})do
    local s=fixture({library=seed,sampEvents=events,demo=false});s.step();s.chat=true;s.chatText=codec.encode('Прямой чат SA:MP.')
    -- No onWindowMessage callback: simulate native/CEF handling Enter first.
    s.step();eq(codec.decode(s.chatText),'Прямой чат SA:MP.');eq(s.chatWrites or 0,0)
    s.step();eq(s.chatWrites or 0,0,'typing never moves the cursor')
    if events then local r=s.events.onSendChat(s.chatText);check(r and codec.decode(r[1])==prefix..' Прямой чат SA:MP.')end
    s.workspace.library.profile.accent='';s.step();eq(codec.decode(s.chatText),'Прямой чат SA:MP.')
    s.workspace.library.profile.accent=prefix;s.chatText=codec.encode('/me действие');s.step();eq(codec.decode(s.chatText),'/me действие')
    s.chatText=codec.encode('Текст.');s.step();eq(codec.decode(s.chatText),'Текст.')
    s.workspace.library.settings.accent_live_input=false;s.step();eq(codec.decode(s.chatText),'Текст.')
    s.workspace.library.settings.accent_live_input=true;s.chatText=codec.encode(string.rep('Я',127));s.step()
    eq(codec.decode(s.chatText),string.rep('Я',127));eq(#s.sent,0)
    check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0);onScriptTerminate(s.script)
end
-- Old libraries get the input helper once, with all personal data intact.
seed.settings.accent_live_input=nil
local valid=assert(model.validate(seed,core.defaults()));check(valid.settings.accent_live_input);eq(valid.profile.accent,prefix)
valid.settings.accent_live_input=false;check(not assert(model.validate(valid,core.defaults())).settings.accent_live_input)
-- No CEF page/adapter/socket: native speech, commands and PA binds still work.
seed=model.defaults(core.defaults());seed.profile.accent=prefix;seed.settings.cef_chat_support=false
local b=model.newBinding(77);b.command='pa26_nativeonly';b.script='Обычная строка бинда.\n/me осмотрелся.\n/do Обстановка спокойная.'
seed.bindings[#seed.bindings+1]=b;seed.next_id=78
local native=fixture({demo=false,library=seed});native.step()
eq(native.chatBridge.status,'disabled');eq(native.chatBridge.reason,'setting_disabled');eq(native.chatBridge.server,nil)
native.chat=true;native.chatText=codec.encode('Привет.');native.step();eq(codec.decode(native.chatText),'Привет.')
onWindowMessage(0x100,13);local result=native.events.onSendChat(native.chatText);check(not result or result[1]==native.chatText)
for _,text in ipairs({'/me осмотрелся.','/do Всё спокойно.','/r Доклад.','!r Доклад.'})do
    native.chatText=codec.encode(text);native.step();eq(codec.decode(native.chatText),text)
end
native.chat=false;native.step();native.commands.pa26_nativeonly('');native.step();native.step(100);native.step(1500);native.step(1500)
eq(#native.sent,3);eq(native.sent[1].line,'Обычная строка бинда.');eq(native.sent[2].line,'/me осмотрелся.');eq(native.sent[3].line,'/do Обстановка спокойная.')
check(not native.hasLog('Ошибка интерфейса'));onScriptTerminate(native.script)
