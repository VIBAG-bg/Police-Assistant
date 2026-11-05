local m=require 'pa26_bindings';local core=require 'pa26_core';local rc=require 'pa26_rp_context';local binder=require 'pa26_binder';local ex=require 'pa26_executor'
local b=m.newBinding(104);b.script='/m Этап один!\n@wait(1400)\n/m Этап два!\n@wait(1400)\n/m Этап три!'
b.rp_context={vehicle='traffic',bike_script='/m Мотоцикл, этап один!\n@wait(1400)\n/m Мотоцикл, этап два!\n@wait(1400)\n/m Мотоцикл, этап три!',checkpoints={}}
for i=1,3 do b.rp_context.checkpoints[i]={before=i,prompt='Подтвердить этап '..i..'?'}end
for _,id in ipairs({448,461,522,586})do eq(rc.class({car={model_id=id}}),'bike')end
for _,id in ipairs({400,596,560})do eq(rc.class({car={model_id=id}}),'car')end
for _,id in ipairs({0,99999,481,471})do eq(rc.class({car={model_id=id}}),'unknown')end
eq(rc.class({car={model_id=596,stale=true}}),'unknown')
local unknown={life=3};local a,err,choice=rc.resolve(b,unknown);eq(a,nil);check(choice)
check(assert(rc.resolve(b,unknown,'bike')).script:find('Мотоцикл',1,true));eq(assert(rc.resolve(b,unknown,'car')).script,b.script)
for _,bad in ipairs({{vehicle='bike'},{identity=1},{checkpoints={{before=0,prompt='x'}}},{checkpoints={{before=1,prompt='x'},{before=1,prompt='y'}}},{unknown='x'}})do check(not rc.validate(bad))end
local t={id=37,ped=9,name='Target'};local ctx={values={},target=t,gender='female',session='x',now=1000,demo=false}
local plan=assert(binder.compile(b,ctx,{},codec));eq(#plan.lines,3)
local clock,shown,sent,cleared=1000,nil,{},0
local state={session='x',focused=true,paused=false,blocked=false,window=false,alive=true}
local valid=true;local queue=ex.new({context=function()return state end,now=function()return clock end,validate=function(v)return v end,demo=function()return false end,
 send=function(w)sent[#sent+1]=w;return true end,lastSent=function()end,markSent=function()end,confirm=function(token,step)shown={token=token,step=step}end,
 clearConfirmation=function()cleared=cleared+1;shown=nil end,bindingContextValid=function()return valid end})
check(queue:start(plan,false,1000));queue:step();check(shown);eq(#sent,0)
for _=1,12 do clock=clock+100;queue:step()end;eq(#sent,0,'Waiting never sends')
check(not queue:decide('stale',true));check(queue:decide(shown.token,true));queue:step();queue:step();eq(#sent,1)
for _=1,20 do clock=clock+100;queue:step()end;check(shown);eq(#sent,1)
check(queue:decide(shown.token,false));queue:step();eq(queue.queue,nil);eq(#sent,1)
clock=ctx.now;shown=nil;check(queue:start(plan,false,1000));queue:step();check(queue:decide(shown.token,true));valid=false;queue:step();eq(queue.queue,nil);eq(#sent,1)
valid=true;clock=ctx.now;check(queue:start(plan,false,1000));queue:step();clock=clock+90001;queue:step();eq(queue.queue,nil)
check(cleared>=3)
b=m.newBinding(105);b.script='/me осмотрела документы {select_name}.';b.rp_context={identity=true}
ctx.values.select_name='Client Nick';local p=assert(binder.compile(b,ctx,{},codec));eq(p.steps[1].kind,'confirm')
ctx.icIdentity=true;p=assert(binder.compile(b,ctx,{},codec));eq(p.steps[1].kind,'message')
b.rp_context.checkpoints={{before=4,prompt='Missing'}};check(not binder.compile(b,ctx,{},codec))
-- A decision between mandatory RP lines does not cause a second /setmark
-- preparation. Both RP messages still have to be delivered before the command.
local template='/me запросила пеленгацию в терминале.\n/do Запрос подготовлен.'
local policy=require('pa26_command_policy').new({codec=codec,settings=function()return{rules={setmark={rp=template}}}end,
 context=function()return ctx end,gender=function()return ctx.gender end,capture=function(id)return{id=id,name='Target'}end,valid=function()return true end})
b=m.newBinding(106);b.target_required=true;b.script=template..'\n/setmark {select_id}';b.rp_context={checkpoints={{before=2,prompt='Результат запроса получен?'}}}
ctx.values.select_id='37';local raw=assert(binder.compile(b,ctx,{},codec));local guarded=assert(policy:prepare(raw,ctx));eq(#guarded.lines,3,'No duplicate RP')
local command=guarded.steps[#guarded.steps];eq(command.text,'/setmark 37');eq(#command.setmarkPolicy.required,2)
local q={plan=guarded,delivered={}};check(not policy:beforeSend(q,command))
for _,i in ipairs(command.setmarkPolicy.required)do q.delivered[i]=true end;check(policy:beforeSend(q,command))
