local fixture=require 'support.fixture';local model=require 'pa26_bindings';local core=require 'pa26_core'
local accent='[Русский акцент]:';local text=string.rep('один два три четыре ',6):match('^(.-)%s*$')
local function setup()
    local seed=model.defaults(core.defaults());seed.profile.accent=accent;seed.rp_text.body_limit=60
    local s=fixture({productionWindows=true,demo=false,library=seed});s.step();if s.frames[1].condition()then s.commands.pa26();s.step()end
    return s
end
local function drain(s)
    s.chat=false
    for _=1,6 do s.step(1800)end
    check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0)
end
for _,command in ipairs({'','/me ','/do ','/try '})do
    local s=setup();s.chat=true;s.chatText=command..text;s.step()
    onWindowMessage(0x100,13)
    local result=command==''and s.events.onSendChat(codec.encode(s.chatText))or s.events.onSendCommand(codec.encode(s.chatText))
    eq(result,false);eq(#s.sent,0,'Original long RPC is suppressed')
    drain(s);check(#s.sent>=2 and #s.sent<=3)
    for i,row in ipairs(s.sent)do
        check(#codec.encode(row.line)<=127)
        if command~=''then check(row.line:sub(1,#command)==command)end
        if i>1 then check(not row.line:find(accent,1,true))end
    end
    onScriptTerminate(s.script)
end
local s=setup();s.chat=true;s.chatText=string.rep('слово ',100)
local original=s.chatText;onWindowMessage(0x100,13);eq(s.chatText,original);eq(#s.sent,0);check(s.consumed)
onScriptTerminate(s.script)
-- IPC retries must not start the same manual message a second time.
s=setup();s.chat=false
local packet={schema=1,page='manual-e2e',chat=false,dialog=false,busy=false,
    events={{id=1,kind='manual',text=text,session=s.chatBridge.env.session()}}}
local response=decodeJson(assert(s.chatBridge:exchange(encodeJson(packet),s.now)))
eq(response.manualResult.status,'accepted');eq(#s.sent,0)
eq(decodeJson(s.chatBridge:exchange(encodeJson(packet),s.now)).manualResult.status,'accepted')
drain(s);local count=#s.sent;check(count>=2 and count<=3)
response=decodeJson(s.chatBridge:exchange(encodeJson(packet),s.now));eq(response.manualResult.status,'completed')
drain(s);eq(#s.sent,count);onScriptTerminate(s.script)
