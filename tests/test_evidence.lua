local M=require 'pa26_evidence'
local prefs=require 'pa26_assist_settings'
local model=require 'pa26_bindings'
local function equal(a,b)
    if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
    for k,v in pairs(a)do if not equal(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local function setup(demo)
    local s={now=1000,cfg=prefs.defaults().evidence,plans={},records={},clock=100000,reads=0,
        state={session='erp',ped=1,alive=true,focused=true,paused=false,blocked=false,demo=demo==true,area='Doherty'}}
    s.cfg.enabled=true
    local e=M.new({settings=function()return s.cfg end,equal=equal,codec=codec,files={clock=function()return s.clock end,verify=function(path,since)
        s.reads=s.reads+1;if not s.file then return nil,'Файл отсутствует'end
        eq(since,100000);return {key=s.key or 'new1',path=path,size=600}
    end},date=function()return '20.10.2026'end,start=function(p)s.plans[#s.plans+1]=p;return not s.startFail,'занято'end,
        hideUi=function()s.hidden=true end,cancel=function()s.cancelled=true end,
        record=function(r)if s.diskFail then return nil,'Диск недоступен'end;s.records[#s.records+1]=model.copy(r);return true end})
    function s.tick(dt)s.now=s.now+(dt or 20);e:tick(s.state,s.now)end
    s.tick();return e,s
end
local e,s=setup();check(not e:propose(''));local p=assert(e:propose('Задержание'));eq(#s.plans,0);eq(s.reads,0)
check(e:accept(p));check(not e:accept(p));eq(#s.plans,0)
s.state.modal=true;s.tick();eq(#s.plans,0);s.state.modal=false;s.tick();eq(#s.plans,1);check(s.hidden);eq(#s.plans[1].lines,0)
check(e:validPlan(s.plans[1]));s.tick(31000);check(e:validPlan(s.plans[1]),'A started delay does not expire with the old confirmation')
e:onExecution('completed',{plan=s.plans[1],demo=false});check(e.active);check(not e:check(''))
check(e:check('C:\\SAMP\\sa-mp-001.png'));s.file=true;s.tick();eq(#s.records,0);s.tick(499);eq(#s.records,0);s.tick(1)
eq(#s.records,1);eq(s.records[1].status,'verified');check(s.records[1].verified);check(not e.active)
s.tick(1000);eq(#s.records,1,'No repeated history writes')
for _,change in ipairs({'expired','scene','ped','mode','settings','focus','death'})do
    e,s=setup();p=assert(e:propose('Тест'))
    if change=='expired'then s.tick(30001)elseif change=='scene'then s.state.session='new';s.tick()
    elseif change=='ped'then s.state.ped=2;s.tick()elseif change=='mode'then s.state.demo=true;s.tick()
    elseif change=='settings'then s.cfg.delay_ms=42;s.tick()elseif change=='focus'then s.state.focused=false;s.tick()
    else s.state.alive=false;s.tick()end
    check(not e:accept(p),change);eq(#s.plans,0)
end
e,s=setup(true);p=assert(e:propose('Демо'));check(e:accept(p));s.tick();e:onExecution('completed',{plan=s.plans[1],demo=true});s.tick()
eq(s.records[1].status,'demo');eq(s.reads,0);check(not s.records[1].verified)
e,s=setup();s.cfg.time_enabled=true;s.cfg.time_verified=true;s.cfg.time_source='/help'
p=assert(e:propose('Со временем'));eq(p.lines[1],'/time');eq(p.steps[1].wire,'/time');eq(p.steps[2].kind,'wait')
check(e:accept(p));s.tick();s.state.typing=true;s.tick();check(not e:validPlan(s.plans[1]));s.state.typing=false;s.tick()
local mutated=model.copy(s.plans[1]);mutated.steps[1].wire='/su 1';check(not e:validPlan(mutated))
e:onExecution('completed',{plan=s.plans[1],demo=false});check(e:check('C:\\new.png'));s.tick();check(not e.checkRequest);check(not e.pendingRecord)
s.diskFail=true;e:cancel('Пользователь отменил');s.tick();check(e.pendingRecord);eq(#s.records,0);check(not e:propose('Ещё'))
s.diskFail=false;s.tick();eq(#s.records,0,'Disk failure requires explicit retry');e:retrySave();s.tick();eq(#s.records,1);eq(s.records[1].status,'cancelled')
e,s=setup();p=assert(e:propose('Таймаут'));check(e:accept(p));s.tick();e:onExecution('completed',{plan=s.plans[1],demo=false});s.tick(60001);eq(s.records[1].status,'timeout')
e,s=setup();s.startFail=true;p=assert(e:propose('Занято'));e:accept(p);s.tick();check(not e.queued);check(not e.intent);eq(#s.records,0)
e,s=setup();p=assert(e:propose('Файл ещё меняется'));e:accept(p);s.tick();e:onExecution('completed',{plan=s.plans[1],demo=false})
s.file=true;e:check('C:\\new.png');s.tick();s.key='changed';s.tick(500);eq(#s.records,0);s.tick(500);eq(#s.records,1)
