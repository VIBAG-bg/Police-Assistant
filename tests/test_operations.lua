local module=require 'pa26_operations'
local settings=require 'pa26_operation_settings'
local copy=require('pa26_patrol_settings').copy
local function fixture()
    local s={cfg=settings.defaults(),now=100,state={session='server-a',alive=true,ped=10,localId=1,demo=false}}
    s.cfg.enabled=true
    local c=module.new({settings=function()return s.cfg end,date=function()return '15.10.2026 22:00:00'end,
        send=function()error('A journal must never send a command')end})
    function s.tick(ms)s.now=s.now+(ms or 0);c:tick(s.state,s.now)end
    s.tick();return c,s
end
check(settings.validate(nil));check(not settings.validate(false));eq(settings.defaults().enabled,false)
local parsed=settings.parseCommands('/CUFF\nfrisk\ncuff\n\nsetmark');eq(#parsed,3);eq(parsed[1],'cuff')
for _,v in ipairs({'cuff 17','/r text','pa26run','-bad','cuff\0','ёж'})do check(not settings.parseCommands(v))end
check(not settings.validate({commands={'cuff','CUFF'}}));check(not settings.validate({commands={[2]='cuff'}}))
for _,row in ipairs({{'enabled',1},{'manual','yes'},{'timeout_ms',999},{'timeout_ms',3600001},{'confirm_ms',0},{'history_limit',501}})do
    check(not settings.validate({[row[1]]=row[2]}))
end
local c,s=fixture();eq(#c:view().rows,0)
for _,line in ipairs({'/cuffin 3','/r cuff','cuff 3','/pa26run 1','/cuff 3\n/s injected','/cuff \255'})do check(not c:observe(line,'manual',nil,'observed'))end
local id=c:observe('/cuff 3','manual',nil,'observed');eq(id,1)
local r=c:view().rows[1];eq(r.transport,'observed');eq(r.source,'none');eq(r.status,'waiting');eq(r.target,nil)
eq(c:view().totals.success,0);s.tick(30000);eq(c:find(id).status,'timeout');eq(c:view().totals.failure,0)
check(not c:propose(id,'success',''));check(not c:propose(id,'server_success','Message'))
local p=c:propose(id,'success','Проверил результат вручную');check(p)
local changed=copy(p);changed.outcome='failure';check(not c:accept(changed),'Edited confirmation cannot change the proposed decision')
check(c:accept(p));eq(c:find(id).source,'none','GUI only queues the decision');check(not c:accept(p))
s.tick();eq(c:find(id).source,'manual');eq(c:find(id).status,'manual_success');eq(c:view().totals.success,1)
check(not c:accept(p),'Consumed proposal cannot increment counts twice')
p=c:propose(id,'failure','Уточнил: сервер отказал');check(c:accept(p));s.tick()
eq(c:view().totals.success,0);eq(c:view().totals.failure,1);eq(#c.data.rows,1,'Correction does not create another operation')
local v=c:view();v.rows[1].source='server';eq(c:find(id).source,'manual')
local valid=module.validate(c.data);check(valid);eq(valid.rows[1].source,'manual')
for _,key in ipairs({'status','transport','origin','source'})do local bad=copy(c.data);bad.rows[1][key]='invented';check(not module.validate(bad))end
local bad=copy(c.data);bad.rows[1].demo=true;check(not module.validate(bad))
bad=copy(c.data);bad.rows[1].target={id=3,name='Nick',ped=999};local normalized=module.validate(bad);check(normalized);eq(normalized.rows[1].target.ped,nil)
bad=copy(c.data);bad.rows[1].target={id=-1,name='Nick'};check(not module.validate(bad))
bad=copy(c.data);bad.rows[2]=copy(bad.rows[1]);check(not module.validate(bad),'Repeated record ID rejected')
bad=copy(c.data);bad.rows[1].text='/frisk 3';check(not module.validate(bad),'Command name and stored text must agree')
bad=copy(c.data);bad.rows[1].text='/cuff 3\n/s injected';check(not module.validate(bad),'Stored command is one line')

-- Demonstrations and successful client calls are independent of server results.
c,s=fixture();local q={plan={binding={name='Test'},target={id=3,name='Nick',ped=99}},index=1}
c:onExecution('preview_line',q,'/cuff 3');eq(#c.data.rows,1);eq(c:find(1).status,'preview');check(not c:propose(1,'success','Fake'))
c:onExecution('preview_line',q,'/cuff 3');eq(#c.data.rows,1)
q.index=2;c:onExecution('preview_line',q,'/cuff 3');eq(#c.data.rows,2)
q={plan={binding={name='Test'},caseProcedure={kind='wanted'},target={id=3,name='Nick',ped=99}},index=1}
c:onExecution('sent_line',q,'/su 3 1 test');eq(#c.data.rows,3);eq(c:find(3).origin,'procedure');eq(c:find(3).transport,'client')
eq(c:find(3).target.ped,nil);eq(c:view().totals.success,0)
c:onExecution('sent_line',q,'/su 3 1 test');eq(#c.data.rows,3,'Native and executor ownership cannot duplicate a step callback')
q={plan=q.plan,index=1};c:onExecution('sent_line',q,'/su 3 1 test');eq(#c.data.rows,4,'Two separate calls with identical text are two observations')

-- Every source can be disabled; configuration changes invalidate open decisions.
for _,row in ipairs({{'manual','manual','observed'},{'binder','binder','client'},{'demo','binder','preview'}})do
    c,s=fixture();s.cfg[row[1]]=false;s.tick();eq(c:observe('/cuff 3',row[2],nil,row[3]),nil);eq(#c.data.rows,0)
end
c,s=fixture();id=c:observe('/cuff 3','manual',nil,'observed');p=c:propose(id,'success','Observed')
s.cfg.timeout_ms=20000;check(not c:accept(p));s.tick();eq(c.offer,nil)
p=c:propose(id,'unknown','No definite answer');s.tick(s.cfg.confirm_ms+1);check(not c:accept(p))
c,s=fixture();id=c:observe('/cuff 3','manual',nil,'observed');p=c:propose(id,'success','Observed');check(c:accept(p))
s.state.session='server-b';s.tick();eq(c:find(id).status,'interrupted');eq(c:find(id).source,'none');eq(c:view().totals.success,0)
for _,key in ipairs({'alive','demo','ped','localId'})do
    c,s=fixture();id=c:observe('/cuff 3','manual',nil,'observed');p=c:propose(id,'success','Observed');check(c:accept(p))
    s.state[key]=({alive=false,demo=true,ped=11,localId=2})[key];s.tick();eq(c:find(id).status,'interrupted');eq(c:find(id).source,'none')
end
c,s=fixture();id=c:observe('/cuff 3','manual',nil,'observed');s.cfg.enabled=false;s.tick();eq(c:find(id).status,'interrupted')
eq(c:observe('/cuff 3','manual',nil,'observed'),nil)
p=c:propose(id,'unknown','Поздняя ручная оценка истории');check(c:accept(p));s.tick();eq(c:find(id).status,'manual_unknown','Disabling observation does not lock existing history')
c,s=fixture();id=c:observe('/cuff 3','manual',nil,'observed');s.now=-10;c:tick(s.state,s.now);eq(c:find(id).status,'interrupted')
c,s=fixture();s.cfg.history_limit=20;s.tick()
for i=1,25 do check(c:observe('/cuff '..i,'manual',nil,'observed'))end
eq(#c.data.rows,20);eq(c.data.rows[1].id,6);eq(c.data.next_id,26);check(module.validate(c.data))
eq(c:find(1),nil);check(not c:propose(1,'success','Pruned'))
local count=0;for _ in pairs(c.pending)do count=count+1 end;eq(count,20)
-- Recording does not require a target and must not infer one from a command argument.
c,s=fixture();check(not c:observe('/cuff 3','manual',{id=3,name='Nick\nInjected'},'observed'))
id=c:observe('/cuff 321','manual',nil,'observed');eq(c:find(id).target,nil)
-- Even maximum-length records fit the shared bounded store after trimming.
c,s=fixture();s.cfg.history_limit=500;s.tick()
for i=1,500 do
    id=c:observe('/cuff '..string.rep('a',2000),'manual',nil,'observed');check(id)
    local offer=c:propose(id,'unknown',string.rep('a',2000));check(c:accept(offer));s.tick()
end
check(#c.data.rows<500);check(#c.data.rows>20);check(c:view().sizeLimited)
check(#TEST_JSON_ENCODE(c.data)<require('pa26_library').MAX_BYTES);check(module.validate(c.data));eq(c.data.next_id,501)
-- Trimming removes open decisions rather than applying them to another row.
c,s=fixture();s.cfg.history_limit=20;s.tick();id=c:observe('/cuff 3','manual',nil,'observed');p=c:propose(id,'success','Observed')
for i=1,20 do c:observe('/cuff '..i,'manual',nil,'observed')end
check(not c:accept(p));eq(c:view().totals.success,0)
-- Optional contextual chat is bounded evidence for a human, never a success parser.
c,s=fixture();s.cfg.capture_chat=true;s.cfg.chat_limit=2;s.tick();id=c:observe('/cuff 3','manual',nil,'observed')
check(c:capturesChat());check(c:onChat('Вы успешно выполнили команду'))
eq(c:find(id).source,'none');eq(c:view().totals.success,0);eq(#c:find(id).chat,1);check(module.validate(c.data))
p=c:propose(id,'success','Проверяю вручную');s.tick(10);check(c:onChat('Другой игрок сказал: это /me, не доказательство'))
check(not c:accept(p),'Changed context needs a fresh manual review');check(not c:capturesChat());check(not c:onChat('third'))
eq(#c:find(id).chat,2);eq(c:find(id).chat[2].after_ms,10)
local altered=copy(c.data);altered.rows[1].chat[1].after_ms=120001;check(not module.validate(altered))
altered=copy(c.data);altered.rows[1].chat[1].text='\0bad';check(not module.validate(altered))
for _,change in ipairs({'timeout','scene','disable','other-command','demo'})do
    c,s=fixture();s.cfg.capture_chat=true;s.tick();id=c:observe('/cuff 3','manual',nil,'observed')
    if change=='timeout'then s.tick(s.cfg.chat_window_ms+1)
    elseif change=='scene'then s.state.session='other';s.tick()
    elseif change=='disable'then s.cfg.capture_chat=false
    elseif change=='other-command'then c:observe('/help','manual',nil,'observed')
    elseif change=='demo'then c:observe('/cuff 3','binder',nil,'preview')end
    check(not c:capturesChat(),change);check(not c:onChat('A nearby chat message'));eq(#c:find(id).chat,0)
end
c,s=fixture();id=c:observe('/cuff 3','manual',nil,'observed');c:interrupt('Spawn/disconnect callback')
eq(c:observe('/cuff 4','manual',nil,'observed'),nil,'A callback invalidates the cached scene until main supplies a fresh snapshot')
s.tick();check(c:observe('/cuff 4','manual',nil,'observed'));eq(c:find(id).status,'interrupted')
return TEST_CHECKS
