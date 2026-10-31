local chat=require 'pa26_chat_text';local model=require 'pa26_bindings';local manual=require 'pa26_manual_chat'
for _,row in ipairs({{'/b .и Привет!','/n Привет!'}, {' /b   .и   Hello, мир!','/n Hello, мир!'},
 {'/B .И Привет!','/n Привет!'}, {'/b Привет!','/b Привет!'}, {'/b .информация','/b .информация'},
 {'/b .и','/b .и'}, {'/b .и   ','/b .и   '}, {'/n Привет!','/n Привет!'}, {'/b .i Hi','/b .i Hi'}})do
 eq(chat.dotCommand(row[1],{}),row[2]);eq(model.submitSpeech(codec.encode(row[1]),'',codec,false,{}),codec.encode(row[2]))
end
eq(chat.dotCommand('/b .и Привет!',{chat_dot_commands=false}),'/b .и Привет!')
eq(model.submitSpeech('/b .и Привет!','',codec,true,{}),'/n Привет!')
local plan=assert(manual.prepare('/b .и '..string.rep('слово ',35),manual.defaults(),require('pa26_rp_settings').defaults(),'',{},codec,'Ivan_Petrov'))
check(plan.eligible);check(#plan.lines>=2);for _,line in ipairs(plan.lines)do check(line:match('^/n '));check(#codec.encode(line)<=127)end
local fixture=require 'support.fixture';local s=fixture({demo=false});s.step()
s.chat=true;s.chatText='/b .и Привет!';s.step();onWindowMessage(0x100,13)
local out=s.events.onSendCommand(codec.encode('/b .и Привет!'))
if type(out)=='table'then eq(codec.decode(out[1]),'/n Привет!')else eq(out,false)end
for _=1,5 do s.chat=false;s.step(1500)end
check(not s.hasLog('Ошибка интерфейса'));eq(s.invalidIOReads,0);onScriptTerminate(s.script)
