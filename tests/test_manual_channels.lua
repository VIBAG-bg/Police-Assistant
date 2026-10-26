local manual=require 'pa26_manual_chat';local prefs=require 'pa26_rp_settings';local chat=require 'pa26_chat_text'
local cfg=manual.defaults();local rp=prefs.defaults();local words=string.rep('синяя куртка и чёрные брюки ',5):match('^(.-)%s*$')
local settings={local_tag='[Адам-12]:',manual_radio_prefix=true}
for _,head in ipairs({'/r','/rn','/f','/fn','/d','/df','/l','/ln','/bkn','/n','/s','/m','/b'})do
    local p,err=manual.prepare(head..' '..words,cfg,rp,'[Акцент]:',settings,codec,'Officer_Name')
    check(p,err);check(p.eligible);check(#p.lines>=2 and #p.lines<=3)
    for i,line in ipairs(p.lines)do
        check(line:sub(1,#head+1)==head..' ');check(#p.wires[i]<=127);check(not line:find('[Акцент]',1,true))
        if i>1 then check(not line:find('[Адам-12]',1,true));check(line:sub(#head+2):match('^%.%.%. '))end
    end
    if head=='/r'then check(p.lines[1]:find('[Адам-12]',1,true))end
end
local speech=string.rep('примета ',14):match('^(.-)%s*$');local action=string.rep('я',60)
local raw='/todo '..speech..'*'..action
local p,err=manual.prepare(raw,cfg,rp,'[Акцент]:',settings,codec,'Officer_Name');check(p,err);check(#p.lines>=2)
for i,line in ipairs(p.lines)do
    local spoken,act=line:match('^/todo (.-)%*(.*)$');eq(act,action);check(#p.wires[i]<=127)
    if i>1 then check(spoken:match('^%.%.%. '))end
    if i<#p.lines then check(spoken:match(' %.%.%.$'))end
end
for _,bad in ipairs({'/todo текст*'..string.rep('я',61),'/todo текст*одно*два','/todo *действие','/todo текст*','/todo '..string.rep('слово ',100)..'*действие'})do
    check(not manual.prepare(bad,cfg,rp,'',settings,codec,'Officer_Name'),bad)
end
local old=prefs.defaults();old.todo_action_limit=nil;eq(assert(prefs.validate(old)).todo_action_limit,60)
local narrow=prefs.defaults();narrow.todo_action_limit=10
check(not manual.prepare('/todo текст*'..string.rep('я',11),cfg,narrow,'',settings,codec,'Officer_Name'))
local policy=chat.policy({manual_chat=cfg,rp_text=rp,local_tag='[Адам-12]:'})
eq(policy.manual.todoActionLimit,60);check(policy.manual.channels['/df'])
-- Cancellation reconstructs only the remaining speech, with exactly one action.
local sent={};local now=1000;local state={session='A',alive=true,focused=true,paused=false,blocked=false,chatActive=false,ownWindow=false,dialogActive=false}
local q=manual.new({codec=codec,context=function()return state end,now=function()return now end,epoch=function()return 1 end,
    interval=function()return 1200 end,busy=function()return false end,
    settings=function()return cfg,rp,'',settings,'Officer_Name'end,send=function(v)sent[#sent+1]=v;return true end})
eq(q:offer(raw,'todo').status,'accepted');q:tick();eq(#sent,1)
local receipt=q:cancel('Остановлено.');eq(receipt.status,'cancelled')
eq(select(2,receipt.raw:gsub('%*','')),1);check(receipt.raw:sub(-#action)==action)
local remaining=assert(manual.prepare(receipt.raw,cfg,rp,'',settings,codec,'Officer_Name'));check(#remaining.lines<#p.lines)
eq(q:offer('/todo текст*'..string.rep('я',61),'bad').status,'rejected');eq(#sent,1)
-- The GUI action cap is saved and then applied by the same policy builder.
local fixture=require 'support.fixture';local f=fixture();f.step();f.page('settings')
require('support.ui_routes').chat(f,'split')
f.intEdits={['Максимум символов для действия после * в /todo (1–60)##rp-todo_action_limit']=40};f.render();f.intEdits={};f.step(700)
eq(f.workspace.library.rp_text.todo_action_limit,40)
check(not f.hasLog('Ошибка интерфейса'));onScriptTerminate(f.script)
