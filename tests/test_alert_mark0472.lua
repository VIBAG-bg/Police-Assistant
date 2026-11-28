local model=require 'pa26_bindings'
local alerts=require 'pa26_alerts'
local executor=require 'pa26_executor'
local core=require 'pa26_core'
local mark='/mark Требуется срочная поддержка всех свободных юнитов!'

local function fixture(demo)
    local cfg=model.alertDefaults()
    local now,last=1000,nil
    local state={session='server:1',ped=7,demo=demo==true,localId=1,alive=true,focused=true,
        paused=false,blocked=false,window=false,area='Ganton',global_tag='',health=100}
    local sent={}
    local run,failMark
    local c=alerts.new({settings=function()return cfg end,codec=codec,
        confirm=function(plan)return run:start(plan,state.demo,1200)end})
    run=executor.new({context=function()return state end,now=function()return now end,
        demo=function()return state.demo end,planValid=function(plan)return c:validPlan(plan)end,
        lastSent=function()return last end,markSent=function(t)last=t end,
        send=function(wire)
            local line=codec.decode(wire)
            if line==mark and failMark then return false end
            sent[#sent+1]=line;return true
        end,
        event=function(kind,q)c:onExecution(kind,q)end})
    local function advance(delta)
        now=now+(delta or 1);c:tick(model.copy(state),now,{})
    end
    local function offer(kind,delta)
        c:request(kind);advance(delta);return assert(c.pending)
    end
    local function pump()
        for _=1,20 do
            if not run.queue then break end
            advance(500);run:step()
        end
        eq(run.queue,nil,'Report queue completed or cancelled')
    end
    return {c=c,state=state,cfg=cfg,run=run,sent=sent,advance=advance,offer=offer,pump=pump,
        failMark=function()failMark=true end,now=function()return now end}
end
local function verifyRadio(plan,help)
    eq(plan.alert.includeHelp,help)
    for i,line in ipairs(plan.lines)do
        check(#plan.wire[i]<=core.WIRE_LIMIT)
        eq(codec.decode(plan.wire[i]),line)
        check(not line:find('  ',1,true))
        check(line:match('^/f ') or help and i==#plan.lines and line==mark,line)
    end
    if help then
        eq(plan.lines[#plan.lines],mark)
        local i=plan.alert.helpStartIndex
        eq(plan.steps[i-1].kind,'wait');eq(plan.steps[i-1].ms,1500);eq(plan.steps[i].text,mark)
    else eq(plan.alert.helpStartIndex,nil)end
end

local s=fixture()
for _,tag in ipairs({'','EPD | '})do
    s.state.global_tag=tag
    for _,kind in ipairs({'sos','shots'})do
        local plan=assert(alerts.prepare(kind,s.state,s.cfg,codec,s.now(),s.c.life))
        verifyRadio(plan,true)
        check(plan.binding.script:find('/f '..tag..(kind=='sos' and '10-70. SOS!' or 'Shots fired! По офицеру открыт огонь'),1,true)==1)
        check(plan.binding.script:find('всех свободных юнитов! 10-20: Ganton.',1,true))
    end
end
s.cfg.shots_help_enabled=false
verifyRadio(assert(alerts.prepare('shots',s.state,s.cfg,codec,s.now(),s.c.life)),false)
verifyRadio(assert(alerts.prepare('sos',s.state,s.cfg,codec,s.now(),s.c.life)),true)

for _,scenario in ipairs({{'sos','shots',120000},{'shots','sos',300000}})do
    s=fixture()
    verifyRadio(s.offer(scenario[1]).plan,true)
    check(s.c:decide(true));s.pump()
    eq(s.sent[#s.sent],mark)
    local firstMark=assert(s.c.lastHelpMark).at
    local p=s.offer(scenario[2],firstMark+scenario[3]-s.now()).plan
    verifyRadio(p,false);check(p.alert.helpSuppressed)
    local delivered=#s.sent
    check(s.c:decide(true));s.pump()
    eq(#s.sent,delivered+#p.lines)
    for i=delivered+1,#s.sent do check(s.sent[i]:match('^/f '))end
    eq(s.c.lastHelpMark.at,firstMark)
    check(s.c:helpMarkActive(firstMark+599999))
    check(not s.c:helpMarkActive(firstMark+600000))
    verifyRadio(s.offer(scenario[1],firstMark+600000-s.now()).plan,true)
    check(s.c:decide(true));s.pump()
    check(s.c.lastHelpMark.at>firstMark)
end

-- Cancelling or failing before the help step never starts the cooldown.
for _,why in ipairs({'declined','cancelled_after_radio','failed_mark','demo'})do
    s=fixture(why=='demo')
    verifyRadio(s.offer('sos').plan,true)
    if why=='declined' then
        check(s.c:decide(false))
    else
        if why=='failed_mark'then s.failMark()end
        check(s.c:decide(true))
        if why=='cancelled_after_radio'then
            s.advance(500);s.run:step();check(#s.sent>0)
            s.run:cancel()
        else s.pump() end
    end
    eq(s.c.lastHelpMark,nil,why)
    if why=='demo'then eq(#s.sent,0)end
    verifyRadio(s.offer('shots',120000).plan,true)
end

s=fixture();s.offer('sos');check(s.c:decide(true));s.pump()
local previous=s.c.lastHelpMark
verifyRadio(s.offer('shots',1000).plan,false);s.c:decide(false)
eq(s.c.lastHelpMark,previous,'Cancelling a confirmation leaves a delivered mark in effect')
s.state.ped=8;s.advance()
eq(s.c.lastHelpMark,previous,'Respawning in the same session leaves the mark in effect')
s.state.session='server:2';s.advance()
eq(s.c.lastHelpMark,nil);verifyRadio(s.offer('shots').plan,true)
s.c:decide(true);s.pump();check(s.c.lastHelpMark)
s.state.demo=true;s.advance();eq(s.c.lastHelpMark,nil)

-- Expiry refreshes an open preview, but does not add help to a started queue.
s=fixture();s.offer('sos');s.c:decide(true);s.pump()
local expiry=s.c.lastHelpMark.at+alerts.HELP_MARK_COOLDOWN_MS
local old=s.offer('shots',expiry-s.now()-1000)
local token=old.token;verifyRadio(old.plan,false)
s.advance(1000);check(s.c.pending.token~=token);verifyRadio(s.c.pending.plan,true)

s=fixture();s.offer('sos');s.c:decide(true);s.pump()
expiry=s.c.lastHelpMark.at+alerts.HELP_MARK_COOLDOWN_MS
old=s.offer('shots',expiry-s.now()-1000)
local first=#s.sent;check(s.c:decide(true));s.advance(500);s.run:step()
check(s.run.queue.plan.alert.started)
s.pump()
eq(#s.sent,first+#old.plan.lines)
for i=first+1,#s.sent do check(s.sent[i]:match('^/f '))end

-- A different configured server command remains independent of /mark.
s=fixture();s.offer('sos');s.c:decide(true);s.pump()
s.cfg.help_command='/testhelp {area}'
local p=s.offer('shots',120000).plan
check(p.alert.includeHelp);eq(p.lines[#p.lines],'/testhelp Ganton')
