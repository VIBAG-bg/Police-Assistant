local core=require 'pa26_core';local model=require 'pa26_bindings'
local P=require 'pa26_command_policy';local E=require 'pa26_executor'
local cfg=require('pa26_manual_actions').defaults();cfg.rules.setmark.rp='/me {gender:открыл|открыла} терминал.\n/do Запрос подготовлен.'
local ctx={gender='female',demo=false,session='s',now=1000,values={my_nick='Demo_Officer'},focused=true,paused=false,blocked=false,window=false,alive=true}
local generation=1;local connected=true
local p=P.new({codec=codec,settings=function()return cfg end,context=function()return ctx end,
 capture=function(id)return connected and{id=id,name='Target_Player',generation=generation}or nil end,
 valid=function(a)return connected and a.generation==generation end})
local function plan(lines)
 local out={binding={id=1,name='test',stat='none'},steps={},lines={},requirements={},demo=false,session='s',createdAt=1000}
 for _,line in ipairs(lines)do if type(line)=='number'then out.steps[#out.steps+1]={kind='wait',ms=line}
  else out.steps[#out.steps+1]={kind='message',text=line,wire=assert(core.encodeWire(line,codec))};out.lines[#out.lines+1]=line end end
 return out
end
for _,entry in ipairs({'F4','F9','wheel','custom','author','favorite','quick','shortcut','manual','imported-profile'})do
 local source=plan({'/setmark 37'});source.entry=entry
 local ready=assert(p:prepare(source));eq(#ready.steps,3,entry);eq(ready.steps[1].text,'/me открыла терминал.')
 eq(ready.steps[3].text,'/setmark 37');eq(#source.steps,1,'Never mutate persisted binding')
 local again=assert(p:prepare(ready));eq(#again.steps,3,'Idempotent re-preparation')
 check(not p:beforeSend({plan=ready,delivered={}},ready.steps[3]))
 check(p:beforeSend({plan=ready,delivered={[1]=true,[2]=true}},ready.steps[3]))
end
local ready=assert(p:prepare(plan({'/me открыла терминал.',1500,'/do Запрос подготовлен.',2500,'/setmark 37'})))
eq(#ready.steps,5);eq(ready.steps[2].ms,1500);eq(ready.steps[4].ms,2500)
ready=assert(p:prepare(plan({'/me другое действие.','/setmark 37'})));eq(#ready.steps,4)
check(not p:prepare(plan({'/setmark 37 extra'})));check(not p:prepare(plan({'/setmark -1'})))
local bad=plan({'/setmark 37'});bad.steps[1].wire='/setmark 38';check(not p:prepare(bad))
bad=plan({'/setmark 37'});bad.target={id=38};check(not p:prepare(bad))
cfg.enabled=false;cfg.rules.setmark.enabled=false;eq(#assert(p:prepare(plan({'/setmark 37'}))).steps,3)
ready=assert(p:prepare(plan({'/setmark 37'})));generation=2;check(not p:valid(ready));generation=1
connected=false;check(not p:prepare(plan({'/setmark 37'})));connected=true
local sent={};local now=1000;local last
local e=E.new({commandPolicy=p,context=function()return ctx end,now=function()return now end,demo=function()return false end,
 validate=function(t)return t end,lastSent=function()return last end,markSent=function(n)last=n end,
 send=function(w)sent[#sent+1]=codec.decode(w);return true end})
check(e:start(plan({'/setmark 37'}),false,1000));e:step();eq(#sent,1)
generation=3;now=2000;e:step();eq(e.queue,nil);eq(#sent,1,'Identity reuse stops remaining RP and command');generation=1
last=nil;check(e:start(plan({'/setmark 37'}),false,1000));e:step();e:cancel();now=3000;e:step();eq(#sent,2)
last=nil;check(e:start(plan({'/setmark 37'}),false,1000));e:step();now=4000;e:step();now=5000;e:step()
eq(sent[#sent],'/setmark 37');eq(e.queue,nil)
-- A failed RP send must never authorize the later command.
local fail=E.new({commandPolicy=p,context=function()return ctx end,now=function()return 1000 end,demo=function()return false end,
 lastSent=function()end,markSent=function()end,send=function()return false end})
check(fail:start(plan({'/setmark 37'}),false,1000));fail:step();eq(fail.queue,nil)
local custom=plan({'/me ввела ориентировку в терминал и запросила пеленг.',1200,'/do На компьютере сектор нахождения Target Player.',800,'/setmark 37'})
custom.target={id=37,name='Target_Player'}
local original=assert(p:prepare(custom));eq(#original.steps,5,'Same-target custom preparation is not duplicated')
eq(original.steps[2].ms,1200);eq(original.steps[4].ms,800)
original=assert(p:prepare(plan({'/setmark 37'})));cfg.rules.setmark.rp='/me другой терминал.\n/do Другой запрос.'
check(not p:prepare(original),'Changed mandatory template cancels an already previewed plan')
