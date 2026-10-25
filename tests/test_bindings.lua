local core=require 'pa26_core'
local model=require 'pa26_bindings'
local binder=require 'pa26_binder'
local executor=require 'pa26_executor'
local journal=require 'pa26_journal'
local cfg=core.defaults(); local lib=model.defaults(cfg)
check(model.validate(lib,cfg)); eq(#lib.bindings,6)
eq(model.casefold('ПРОВЕРКА Ёж ABC'),'проверка ёж abc')
eq(model.casefold('ПРОВЕРКА'),'проверка')
local b=model.newBinding(7); b.script='/me {gender:предъявил|предъявила} документ\n@wait(1500)\n{greeting}, я {my_name}. ID {id}.'
local target={id=0,ped=99,name='Visible_Name'}
local ctx={values={id='0',my_name='Victor Auditore',greeting='Здравствуйте'},gender='female',target=target,session='test',now=10000,demo=false}
local plan,err=binder.compile(b,ctx,{},codec); check(plan,err); eq(#plan.steps,3); eq(#plan.lines,2)
eq(plan.lines[1],'/me предъявила документ'); check(plan.lines[2]:find('ID 0.',1,true))
check(plan.requirements.target); check(not plan.has_command)
local malformed={'@wait(-1)','@wait(60001)','@wait(nan)','@sleep(Unknown)','@sleep(0)','@speak(9)','@unknown(test)'}
for _,text in ipairs(malformed) do check(not binder.parse(text),text) end
check(binder.parse('@check(false)')); check(not binder.requirements({target_required=false,script='@check(false)'}).target)
b.script='@check(false)\nЗдравствуйте.'; ctx.target=nil; check(binder.compile(b,ctx,{},codec)); ctx.target=target
b.script=string.rep('x\n',65); check(not binder.compile(b,ctx,{},codec))
b.script='@wait(60000)\n@wait(60000)\n@wait(60000)\n@wait(60000)\n@wait(60000)\n@wait(1)'; check(not binder.compile(b,ctx,{},codec))
b.script=string.rep('я',127); check(not binder.compile(b,ctx,{},codec),'A word exceeding the 90-character body budget is not cut')
local wireOnly=model.copy(lib.rp_text);wireOnly.speech_enabled=false
check(binder.compile(b,ctx,{},codec,nil,{rpSettings=wireOnly}),'The explicit no-splitting setting still supports the 127-byte client boundary')
b.script=string.rep('я',128); check(not binder.compile(b,ctx,{},codec))
b.script='Первая строка\n'..string.rep('я',128); check(not binder.compile(b,ctx,{},codec),'whole script must fail before sending any line')
b.script='@random(Можно|'..string.rep('я',128)..')'; check(not binder.compile(b,ctx,{},codec,function() return 1 end),'unused invalid random branch must be detected')
b.script='@random(Здравствуйте|Добрый день), {my_name}.'
plan=binder.compile(b,ctx,{},codec,function() return 2 end); eq(plan.lines[1],'Добрый день, Victor Auditore.')
b.script='{unknown}'; check(not binder.compile(b,ctx,{},codec))
b.script='{my_name'; check(not binder.compile(b,ctx,{},codec))
b.script='Emoji 🐶'; check(not binder.compile(b,ctx,{},codec))
b.script='/pa26run 7'; check(not binder.compile(b,ctx,{},codec),'recursive local commands are blocked')
b.script='@screen'; check(not binder.compile(b,ctx,{},codec))
b.script='@speak(1)'; check(not binder.compile(b,ctx,{},codec)); check(binder.compile(b,ctx,{},codec,nil,{sound=true}))
b.script='@sleep(F9)'; check(not binder.compile(b,ctx,{},codec,nil,{reservedKeys={[0x78]=true}}))
b.script='@select(0)\nЗдравствуйте.'; check(binder.compile(b,ctx,{},codec)); b.script='@select(1)'; check(not binder.compile(b,ctx,{},codec))
b.parameters={{name='reason',label='Основание',type='text',required=true,default=''}, {name='days',label='Срок',type='integer',required=true,default='3'}}
b.script='{param:reason} · {param:days}'; check(not binder.compile(b,ctx,{},codec))
plan=binder.compile(b,ctx,{reason='Проверка 100% %s'},codec); check(plan); eq(plan.lines[1],'Проверка 100% %s · 3')
check(not binder.compile(b,ctx,{reason='test',days='3.2'},codec))
check(not binder.compile(b,ctx,{reason='test\n/quit'},codec))
b.parameters={}; b.script='{param1}'; check(not binder.compile(b,ctx,{},codec)); check(binder.compile(b,ctx,{param1='Текст'},codec))
local args=model.parseArguments('42 "две части" "кавычка \\""')
check(args); eq(args.param1,'42'); eq(args.param2,'две части'); eq(args.param3,'кавычка "')
check(not model.parseArguments('"незакрытая')); check(not model.parseArguments('1 2 3 4 5 6 7 8 9'))
check(not model.shortcut({key=0x49,ctrl=false,alt=false,shift=false}))
check(model.shortcut({key=0x31,ctrl=false,alt=true,shift=false}))
local bad=model.copy(lib); bad.bindings[2].id=1; check(not model.validate(bad,cfg))
bad=model.copy(lib); bad.bindings[1].shortcut.key=lib.settings.quick_key; check(not model.validate(bad,cfg))
bad=model.copy(lib); bad.bindings[1].parameters={{name='x',label='x',default='',type='text',required=true},{name='x',label='x',default='',type='text',required=true}}; check(not model.validate(bad,cfg))
bad=model.copy(lib); bad.bindings[1].script='bad\0text'; check(not model.validate(bad,cfg))
bad=model.copy(lib); bad.wheel[1]=999; check(not model.validate(bad,cfg))
bad=model.copy(lib); bad.profile.name=0/0; check(not model.validate(bad,cfg))

local state={now=10000,demo=false,focused=true,blocked=false,paused=false,alive=true,window=false,valid=true,session='test',sent={},pressed={},down={},last=nil}
local ex=executor.new({now=function() return state.now end,context=function() return state end,demo=function() return state.demo end,
    validate=function(t) if state.failValidation then error('validation API failed') end; return state.valid and model.copy(t) or nil end,
    send=function(wire) if state.failSend then error('send failed') end; state.sent[#state.sent+1]=wire; return true end,
    lastSent=function() return state.last end,markSent=function(now) state.last=now end,
    pressed=function(k) return state.pressed[k] end,down=function(k) return state.down[k] end})
b.parameters={}; b.script='/me текст\n@wait(3000)\n/do текст'; b.stat='documents'; ctx.now=state.now
plan=binder.compile(b,ctx,{},codec); check(ex:start(plan,false,1500)); check(not ex:start(plan,false,1500))
ex:step(); eq(#state.sent,1); ex:step(); state.now=state.now+2999; ex:step(); eq(#state.sent,1)
state.now=state.now+1; ex:step(); ex:step(); eq(#state.sent,2); eq(ex.queue,nil)
state.last=nil; ctx.now=state.now; b.script='/me текст\n/do текст'; plan=binder.compile(b,ctx,{},codec)
check(ex:start(plan,false,1500)); ex:step(); state.valid=false; state.now=state.now+2000; ex:step(); eq(ex.queue,nil); eq(#state.sent,3)
state.valid=true; state.last=nil; ctx.now=state.now; plan=binder.compile(b,ctx,{},codec); check(ex:start(plan,false,1500))
state.failValidation=true; ex:step(); state.failValidation=false; eq(ex.queue,nil); eq(#state.sent,3)
for _,key in ipairs({'blocked','window'}) do ctx.now=state.now; plan=binder.compile(b,ctx,{},codec); check(ex:start(plan,false,1500)); state[key]=true; ex:step(); eq(ex.queue,nil); state[key]=false end
ctx.now=state.now; plan=binder.compile(b,ctx,{},codec); check(ex:start(plan,false,1500)); state.failSend=true; ex:step(); eq(ex.queue,nil); state.failSend=false; ex:step(); eq(#state.sent,3)
ctx.now=state.now; plan=binder.compile(b,ctx,{},codec); state.demo=true; check(not ex:start(plan,true,1500),'a real preview cannot be reused as demo or vice versa')
ctx.demo=true; plan=binder.compile(b,ctx,{},codec); check(ex:start(plan,true,1500)); state.last=nil; ex:step(); state.now=state.now+1500; ex:step(); eq(#state.sent,3); eq(ex.queue,nil)
state.demo=false; ctx.demo=false; b.script='@sleep(F6)\nЗдравствуйте.'; ctx.now=state.now; plan=binder.compile(b,ctx,{},codec)
check(ex:start(plan,false,1500)); state.down[0x75]=true; state.pressed[0x75]=true; ex:step(); eq(ex.queue.index,1)
state.down[0x75]=false; state.pressed[0x75]=false; ex:step(); state.down[0x75]=true; state.pressed[0x75]=true; ex:step(); eq(ex.queue.index,2)
state.last=nil; ex:step(); eq(#state.sent,4); eq(ex.queue,nil)
ctx.now=state.now; plan=binder.compile(b,ctx,{},codec); check(ex:start(plan,false,1500)); ex:step(); state.now=state.now+90001; ex:step(); eq(ex.queue,nil)
state.down={}; state.pressed={}; ctx.now=state.now; plan=binder.compile(b,ctx,{},codec); state.now=state.now+60001; check(not ex:start(plan,false,1500),'stale preview')

local j=journal.new(nil,function(fmt) return fmt=='%Y-%m-%d' and '2026-10-11' or '11.10.2026 17:00:00' end)
local entry=j:record({plan=plan,demo=false,sent=1},'completed'); check(j:confirm(entry.id)); check(not j:confirm(entry.id)); eq(j.data.counters.documents,1)
local demo=j:record({plan=plan,demo=true,sent=0},'completed'); check(not j:confirm(demo.id))
local zero=j:record({plan=plan,demo=false,sent=0},'cancelled','Не отправлено'); check(not j:confirm(zero.id))
check(journal.validate(j.data)); j:clearLog(); eq(#j.data.events,0); eq(j.data.counters.documents,1)
j:resetStats(); eq(j.data.counters.documents,nil); check(journal.validate(j.data))
check(model.recruitmentResult(lib.recruitment,{age=18,level=3,lawfulness=0,land=true,weapon=true,medical=true}))
check(not model.recruitmentResult(lib.recruitment,{age=17,level=3,lawfulness=0,land=true,weapon=true,medical=true}))
