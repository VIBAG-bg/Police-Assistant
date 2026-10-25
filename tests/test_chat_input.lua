local fixture=require 'support.fixture';local model=require 'pa26_bindings';local core=require 'pa26_core'
local prefix='[Русский акцент]:'
local seed=model.defaults(core.defaults());seed.profile.accent=prefix
local function setup(extra)
    local options={demo=false,library=seed};for k,v in pairs(extra or{})do options[k]=v end
    local s=fixture(options);s.step();s.chat=true;return s
end
for _,available in ipairs({true,false})do
    local s=setup({sampEvents=available});s.chatText=codec.encode('Обычный чат.')
    onWindowMessage(0x0100,0x54);eq(codec.decode(s.chatText),'Обычный чат.');eq(s.chatWrites,nil)
    onWindowMessage(0x0100,0x0D);eq(codec.decode(s.chatText),prefix..' Обычный чат.');eq(s.chatWrites,1);eq(#s.sent,0)
    onWindowMessage(0x0100,0x0D);eq(s.chatWrites,1,'no double accent on repeated Enter')
    if available then local r=s.events.onSendChat(s.chatText);check(not r or r[1]==s.chatText)end
    for _,text in ipairs({'/me действие','/do Действие.','/r Доклад.','/b OOC',' /su 37 2 основание',''})do
        s.chatText=codec.encode(text);onWindowMessage(0x0100,0x0D);eq(codec.decode(s.chatText),text)
    end
    s.chatText='Текст UTF-8.';onWindowMessage(0x0100,0x0D);eq(s.chatText,prefix..' Текст UTF-8.')
    s.chat=false;s.chatText=codec.encode('Закрытый ввод.');onWindowMessage(0x0100,0x0D);eq(codec.decode(s.chatText),'Закрытый ввод.')
    onScriptTerminate(s.script)
end
local s=setup();s.chatText=codec.encode(string.rep('Я',127));onWindowMessage(0x0100,0x0D)
check(s.messageConsumed);eq(#s.sent,0);check(s.hasLog('Одно слово'));eq(codec.decode(s.chatText),string.rep('Я',127))
s.chatWriteError=true;s.chatText=codec.encode('Ошибка записи.');onWindowMessage(0x0100,0x0D);eq(#s.sent,0);check(s.messageConsumed)
s.workspace.library.profile.accent='';s.chatText=codec.encode('Без акцента.');s.chatReadError=true;s.messageConsumed=false
onWindowMessage(0x0100,0x0D);check(not s.messageConsumed,'disabled accent must not depend on input APIs');onScriptTerminate(s.script)
s=setup({chatInputBackend=false});s.chatText=codec.encode('RPC fallback.');onWindowMessage(0x0100,0x0D)
eq(codec.decode(s.chatText),'RPC fallback.');eq(codec.decode(s.events.onSendChat(s.chatText)[1]),prefix..' RPC fallback.')
onScriptTerminate(s.script)
