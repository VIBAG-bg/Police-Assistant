-- Shared fine form remains independent; wanted now has its own two-phase suite.
local mod=require 'pa26_case_forms';local prefs=require 'pa26_procedure_settings';local model=require 'pa26_bindings'
local function equal(a,b)
    if type(a)~='table'or type(b)~='table'then return a==b end
    for k,v in pairs(a)do if not equal(v,b[k])then return false end end
    for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local function fixture()
    local s={cfg=prefs.defaults(),now=1000,stamp=1,plans={},target={id=37,ped=99,name='Player_Name'},
        state={session='test:7777',ped=1,alive=true,demo=false,focused=true,paused=false,blocked=false,inVehicle=false}}
    s.cfg.enabled=true;s.cfg.fine_command='/mockfine {id} {amount} {basis}';s.cfg.fine_verified=true;s.cfg.fine_source='LOCAL MOCK'
    local c;c=mod.new({settings=function()return s.cfg end,target=function()return s.target,s.stamp end,identity=function()return s.identity end,
        equal=equal,codec=codec,validTarget=function(t,stamp)return t and s.target and t.id==s.target.id and t.ped==s.target.ped and t.name==s.target.name and stamp==s.stamp end,
        start=function(p)check(c:validPlan(p));s.plans[#s.plans+1]=p;return true end,cancel=function()s.cancelled=true end})
    function s.tick(ms)s.now=s.now+(ms or 0);c:tick(s.state,s.now)end
    function s.form()local f=assert(c:begin('fine'));f.passport_seen='yes';f.ic_name='John Smith';f.mask='no';f.basis='Проверенное основание';f.amount='1000';return f end
    s.tick();return c,s
end
check(prefs.validate(nil));check(not prefs.validate(false))
local c,s=fixture();local f=s.form();eq(c:branch(f),'passport')
f.mask='yes';check(not c:branch(f));f.mask='unknown';check(not c:branch(f));f.mask='no';f.mode='ooc';check(not c:branch(f));f.mode='ic'
for _,bad in ipairs({'0','-1','2.5','1e2','',string.rep('9',10),'nan'})do f.amount=bad;check(not c:preview(f))end
f.amount='0002';eq(c:preview(f).values.amount,'2');f.basis='bad\n/r spam';check(not c:preview(f));f.basis='ПМ 4.1'
local b=assert(c:draft(f,20));check(not b.enabled);check(model.validateBinding(b));check(b.script:find('{param:amount}',1,true))
local p=assert(c:offer(f));eq(#s.plans,0);check(c:accept(p));check(not c:accept(p));s.tick();eq(#s.plans,1)
check(not table.concat(s.plans[1].lines,'\n'):find('/mockfine',1,true));check(c:validPlan(s.plans[1]));c:onExecution('completed',{plan=s.plans[1]});local final=assert(c:takeCommandConfirmation());eq(final.phase,'command');check(c:accept(final));s.tick();eq(s.plans[2].lines[1],'/mockfine 37 2 ПМ 4.1');s.stamp=2;s.tick();check(s.cancelled)
for _,key in ipairs({'session','ped','localId','local_nick','demo','alive'})do
    c,s=fixture();f=s.form();p=assert(c:offer(f));check(c:accept(p));s.state[key]=key=='alive'and false or 'changed';s.tick();eq(#s.plans,0,key)
end
c,s=fixture();f=s.form();p=assert(c:offer(f));s.tick(60001);check(not c:accept(p))
c,s=fixture();f=s.form();s.tick(-1000);check(not c:preview(f));c:tick(s.state,0/0);check(not c:preview(f))
for _,bad in ipairs({'/r text','/me text\n/su 37 2 reason','/me {unsupported}','/do bad\0text','/me \255'})do local cfg=prefs.defaults();cfg.fine_passport_rp=bad;check(not prefs.validate(cfg))end
