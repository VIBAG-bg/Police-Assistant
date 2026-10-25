local m=require 'pa26_manual_chat';local rp=require 'pa26_rp_settings';local core=require 'pa26_core'
local cfg=m.defaults();local prefs=rp.defaults();local accent='[Русский акцент]:'
local body=string.rep('синяя куртка и чёрные брюки ',5):match('^(.-)%s*$')
local function reconstruct(p)
    local out={}
    for i,line in ipairs(p.lines)do
        check(#p.wires[i]<=127);eq(codec.decode(p.wires[i]),line)
        local text=p.channel~=''and line:sub(#p.channel+2)or line
        if #p.lines>1 then
            if i>1 then check(text:sub(1,4)=='... ');text=text:sub(5)end
            if i<#p.lines then check(text:sub(-4)==' ...');text=text:sub(1,-5)end
        end
        out[#out+1]=text
    end
    return table.concat(out,' ')
end
for _,channel in ipairs({'','/me','/do','/try','/TRY','.ьу'})do
    local text=channel==''and body or channel..' '..body
    local p,why=m.prepare(text,cfg,prefs,accent,{},codec,'Officer_Name');check(p,why);check(#p.lines>=2 and #p.lines<=3)
    eq(reconstruct(p),(channel==''and accent..' 'or'')..body)
    if channel~=''then for _,line in ipairs(p.lines)do check(line:sub(1,#p.channel+1)==p.channel..' ')end end
    if channel==''then check(not p.lines[2]:find(accent,1,true))end
end
for _,threshold in ipairs({24,50,90,99,120})do
    prefs.body_limit=threshold
    for count=1,65 do
        local text=string.rep('слово ',count):match('^(.-)%s*$')
        local p=m.prepare(text,cfg,prefs,accent,{},codec,'Officer_Name')
        if p then check(#p.lines<=3);eq(reconstruct(p),accent..' '..text)end
    end
end
prefs=rp.defaults()
for _,bad in ipairs({string.rep('слово ',100),string.rep('я',300),'/me '..string.rep('я',300),'Привет 🙂','中文','/me один\n/su 37 8 1'})do
    check(not m.prepare(bad,cfg,prefs,accent,{},codec,'Officer_Name'))
end
for _,command in ipairs({'/su 37 8 1','/setmark 37','/help','!r текст'})do
    local p=assert(m.prepare(command,cfg,prefs,accent,{},codec));eq(p.eligible,false)
end
check(not m.validate({enabled=true,max_parts=4,interval_ms=1500}));check(not m.validate({enabled=true,max_parts=3,interval_ms=0/0}))
local now=1000;local ctx={session='one',alive=true,focused=true,paused=false,blocked=false,chatActive=false,ownWindow=false,dialogActive=false}
local epoch=1;local busy=false;local sent={};local fails=false
local queue=m.new({codec=codec,now=function()return now end,epoch=function()return epoch end,context=function()return ctx end,
    interval=function()return 1800 end,settings=function()return cfg,prefs,accent,{},'Officer_Name'end,busy=function()return busy end,
    send=function(wire)if fails then return false end;sent[#sent+1]=codec.decode(wire);return true end})
local result=queue:offer(body,'ticket');eq(result.status,'accepted');eq(#sent,0)
eq(queue:offer(body,'ticket'),result,'replayed IPC event is idempotent')
ctx.chatActive=true;ctx.blocked=true;queue:tick();eq(#sent,0)
ctx.chatActive=false;ctx.blocked=false;queue:tick();eq(#sent,1);queue:tick();eq(#sent,1)
now=now+1799;queue:tick();eq(#sent,1);now=now+1;queue:tick();eq(#sent,2)
while queue.queue do now=now+1800;queue:tick()end
eq(queue.result.status,'completed');eq(queue:offer(body,'ticket').status,'completed');local before=#sent;queue:tick();eq(#sent,before)
for _,change in ipairs({'session','epoch','death','focus','pause','busy','settings','send'})do
    ctx={session='one',alive=true,focused=true,paused=false,blocked=false,chatActive=false,ownWindow=false,dialogActive=false}
    cfg=m.defaults();busy=false;fails=false;epoch=1;now=now+10000;sent={}
    queue.queue=nil;eq(queue:offer(body,'cancel-'..change).status,'accepted');queue:tick();eq(#sent,1)
    if change=='session'then ctx.session='two'elseif change=='epoch'then epoch=2 elseif change=='death'then ctx.alive=false
    elseif change=='focus'then ctx.focused=false elseif change=='pause'then ctx.paused=true elseif change=='busy'then busy=true
    elseif change=='settings'then cfg.max_parts=2 else fails=true end
    now=now+1800;queue:tick();eq(queue.queue,nil);eq(queue.result.status,'cancelled');eq(#sent,1)
    check(queue.draft and queue.draft~='');check(not queue.draft:find(accent,1,true),'Already sent accent is not added to the remainder')
end
ctx={session='one',alive=true,focused=true,paused=false,blocked=false,chatActive=false,ownWindow=false,dialogActive=false}
busy=false;fails=false;cfg=m.defaults();epoch=1
eq(queue:offer(string.rep('слово ',100),'oversized').status,'rejected');eq(queue.queue,nil)
local accepted=queue:offer(body,'held');eq(accepted.status,'accepted')
eq(queue:offer(body,'second-enter').status,'rejected');eq(queue.queue.key,'held');queue:cancel('Остановлено пользователем.')
