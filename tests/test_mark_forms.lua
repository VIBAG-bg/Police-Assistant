local module=require 'pa26_case_forms'
local prefs=require 'pa26_procedure_settings'
local model=require 'pa26_bindings'
local function equal(a,b)
    if type(a)~='table'or type(b)~='table'then return a==b end
    for k,v in pairs(a)do if not equal(v,b[k])then return false end end
    for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local function fixture(command)
    local s={cfg=prefs.defaults(),now=1000,stamp=1,plans={},target={id=37,ped=99,name='Player_Name'},
        state={session='test:7777',ped=1,alive=true,demo=false,focused=true,paused=false,blocked=false}}
    s.cfg.enabled=true
    if command then s.cfg.mark_command=command;s.cfg.mark_source='LOCAL TEST CONTRACT';s.cfg.mark_verified=true end
    local c
    c=module.new({settings=function()return s.cfg end,target=function()return s.target,s.stamp end,
        identity=function()return s.identity end,equal=equal,codec=codec,
        validTarget=function(t,stamp)return t.id==s.target.id and t.name==s.target.name and t.ped==s.target.ped and stamp==s.stamp end,
        start=function(p)check(c:validPlan(p));s.plans[#s.plans+1]=p;return true end,cancel=function()s.cancelled=true end})
    function s.tick(dt)s.now=s.now+(dt or 0);c:tick(s.state,s.now)end
    function s.form()
        local f=assert(c:begin('mark'));f.basis='проверенное основание'
        f.phone_active='yes';f.phone_known='yes';f.phone_number='555-0100';f.phone_source='Сообщён в IC-разговоре';return f
    end
    s.tick();return c,s
end
eq(prefs.defaults().mark_command,'');check(not prefs.defaults().mark_verified)
for _,cmd in ipairs({'/setmark','/setmark {id}','/setmark {phone_number}'})do check(prefs.command(cmd,'mark',true))end
for _,cmd in ipairs({'/setmark 37','/setmark 5550100','/mark {id}','/setmark {unknown}','/setmark {id}\n/r spam'})do
    check(not prefs.command(cmd,'mark',true))
end
local c,s=fixture();local f=s.form();local p=assert(c:preview(f));eq(p.branch,'ic');eq(#p.lines,2);check(not p.ready)
eq(p.values.amount,'');check(not c:offer(f));eq(#s.plans,0)
f.phone_known='unknown';check(not c:branch(f));f.phone_known='no';check(not c:branch(f));f.phone_known='yes'
f.phone_source='';check(not c:branch(f));f.phone_source='Разговор';f.phone_number='';check(not c:branch(f))
f.phone_number='555-0100';f.passport_seen='no';f.mask='yes';f.face_before='no';eq(c:branch(f),'ic','Phone provenance is separate from passport and face')
f.mode='ooc';check(not c:branch(f));f.ooc_ack=true;eq(c:branch(f),'ooc')
f.phone_known='no';f.phone_number='';f.phone_source='';check(not c:preview(f),'OOC never bypasses RP phone provenance')
f.phone_active='yes';f.phone_known='yes';f.phone_number='555-0100';f.phone_source='Разговор';p=assert(c:preview(f));check(not table.concat(p.lines,'\n'):find('Player_Name',1,true))
s.cfg.allow_ooc=false;check(not c:preview(f))
-- Phone as RP evidence and the technical command target are separate variables.
for _,cmd in ipairs({'/setmark {id}','/setmark {phone_number}','/setmark'})do
    c,s=fixture(cmd);f=s.form();p=assert(c:offer(f));check(c:accept(p));eq(#s.plans,0);s.tick()
    eq(#s.plans,1);local plan=s.plans[1];eq(#plan.steps,5);eq(plan.steps[1].kind,'message');eq(plan.steps[2].ms,1500)
    eq(plan.steps[3].kind,'message');eq(plan.steps[4].ms,1500)
    eq(plan.steps[5].text,cmd=='/setmark {id}'and '/setmark 37'or cmd=='/setmark {phone_number}'and '/setmark 555-0100'or '/setmark')
    eq(plan.binding.stat,'none');check(plan.target.id==37);eq(plan.caseProcedure.rpCount,2)
    s.stamp=2;s.tick();check(s.cancelled);check(not c:validPlan(plan))
end
-- Personal-card telephone data prefill; editing/expiry cannot reuse stale evidence.
c,s=fixture('/setmark {id}')
s.identity={record={stamp=1,nonce=2,version=3,target=s.target,passport_seen='unknown',mask='unknown',face_before='unknown',
    phone_known='yes',phone_number='555-0100',phone_source='IC-карточка'}}
f=assert(c:begin('mark'));eq(f.phone_number,'555-0100');eq(f.phone_source,'IC-карточка');check(not c:branch(f),'Saved phone evidence does not prove the phone is on now');f.phone_active='yes';eq(c:branch(f),'ic')
s.identity.record.version=4;check(not c:preview(f))
c,s=fixture('/setmark {id}');f=s.form();local b=assert(c:draft(f,21));check(model.validateBinding(b))
check(not b.enabled);check(b.target_required);check(b.script:find('/setmark {id}',1,true))
check(b.script:find('{param:phone_number}',1,true));check(not b.script:find('555-0100',1,true));check(b.script:find('@wait(1500)',1,true))
for _,param in ipairs(b.parameters)do eq(param.default,'');check(param.required)end
f.phone_number='номер\n/r spam';check(not c:preview(f));f.phone_number=string.rep('5',121);check(not c:preview(f))
