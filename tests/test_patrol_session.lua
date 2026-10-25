local module=require 'pa26_patrol_session'
local settings=require 'pa26_patrol_settings'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local function equal(a,b)
    if type(a)~='table'or type(b)~='table'then return a==b end
    for k,v in pairs(a)do if not equal(v,b[k])then return false end end
    for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local function fixture()
    local s={now=1000,cfg=settings.defaults(),profile={name='Victor Auditore',callsign='A-1'},contacts={},players={},plans={},cancels={}}
    s.cfg.enabled=true;s.cfg.unit='A-1';s.cfg.interval_ms=60000
    s.state={session='erp:7777',ped=1,local_nick='Victor_Auditore',alive=true,demo=false,onDuty=true,radioEnabled=true,
        focused=true,paused=false,blocked=false,typing=false,recording=false,editingHud=false,draggingHud=false,
        area='Ganton',local_tag='[EPD]'}
    local c
    s.env={settings=function()return s.cfg end,profile=function()return s.profile end,contacts=function()return s.contacts end,
        codec=codec,equal=equal,date=function()return '15.10.2026 18:00:00'end,
        resolve=function(n)for id,p in pairs(s.players)do if p.connected and p.near~=false and p.name==n then return {id=id,name=n}end end end,
        observe=function(id)return s.players[id]end,
        start=function(plan)
            check(c:validPlan(plan),'Plan must be valid before enqueue')
            if s.startError then return nil,s.startError end
            s.plans[#s.plans+1]=plan;return true
        end,
        cancel=function(token) s.cancels[#s.cancels+1]=token;c:onExecution('cancelled',{plan=s.plans[#s.plans]})end}
    c=module.new(s.env)
    function s.tick(ms)s.now=s.now+(ms or 1000);c:tick(s.state,s.now)end
    function s.offer(action)local p,err=c:propose(action);check(p,err);return p end
    function s.commit(action)local p=s.offer(action);check(c:accept(p));s.tick(0);return s.plans[#s.plans]end
    function s.sent(plan)c:onExecution(s.state.demo and 'preview_line'or 'sent_line',{plan=plan or s.plans[#s.plans]})end
    function s.crew()
        s.contacts={{id=1,nickname='John_Smith',callsign='A-2'}}
        s.cfg.crew={{contact_id=1,ic_name='John Smith',role='Водитель'}}
        s.players[4]={name='John_Smith',connected=true}
    end
    s.tick(0);return c,s
end
-- Optional migration leaves the installed library's settings intact.
local old=model.defaults(core.defaults());old.patrol_session=nil
local migrated,err=model.validate(old,core.defaults());check(migrated,err);check(not migrated.patrol_session.enabled)
eq(migrated.alerts.patrol.enabled,old.alerts.patrol.enabled)
for _,bad in ipairs({false,'bad',1})do check(not settings.validate(bad))end
for _,key in ipairs({'start','resume','finish','crew','periodic'})do
    local cfg=settings.defaults();cfg[key..'_template']='{not_supported}';check(not settings.validate(cfg))
    cfg[key..'_template']='a\nb';check(not settings.validate(cfg))
end
local cfg=settings.defaults();cfg.crew={{contact_id=1,ic_name='a',role='b'},{contact_id=1,ic_name='c',role='d'}};check(not settings.validate(cfg))
cfg=settings.defaults();cfg.interval_ms=0/0;check(not settings.validate(cfg))
cfg=settings.defaults();cfg.enabled=true;cfg.interval_ms=60000;old.patrol_session=cfg;old.radio_guard.lead_ms=60000;check(model.validate(old,core.defaults()))
eq(settings.duration(3601000),'01:00:01')
local c,s=fixture();local p=s.offer('start');eq(#s.plans,0);check(not c.data.active)
check(p.line:find('Victor Auditore',1,true));check(p.line:find('/r [EPD]',1,true))
check(c:accept(p));check(not c:accept(p));eq(#s.plans,0,'Confirmation itself never sends')
s.tick(0);eq(#s.plans,1);eq(c.data.active.status,'active');check(not c:effectivePatrol(s.cfg).enabled,'Await start delivery')
local plan=s.plans[1];check(c:validPlan(plan));s.sent();eq(c.data.active.report_status,'Передан клиенту');check(c:effectivePatrol(s.cfg).enabled)
check(not c:accept(p),'Old confirmation cannot execute twice');s.tick(1000);eq(c.data.active.elapsed_ms,1000)
local hud=c:view({visible=true,status='До доклада: 00:59',progress=.1,remaining=59000,interval=60000}).hud
check(hud.visible);eq(hud.status,'До доклада: 00:59');check(hud.crew:find('Экипаж: 1',1,true))
check(c:pause());local before=c.data.active.elapsed_ms;s.tick(1000);eq(c.data.active.elapsed_ms,before)
check(not c:effectivePatrol(s.cfg).enabled);s.commit('resume');s.sent();eq(c.data.active.status,'active')
-- Cancel/report failures do not claim radio delivery or silently retry.
c,s=fixture();s.startError='Busy';s.commit('start');eq(#s.plans,0);check(not c.data.active);s.tick();eq(#s.plans,0)
c,s=fixture();s.commit('start');c:onExecution('cancelled',{plan=s.plans[1]});eq(c.data.active.status,'paused');eq(#s.plans,1)
s.tick();eq(#s.plans,1)
c,s=fixture();s.state.busy='binder';p=s.offer('start');check(c:accept(p));s.tick();check(not c.data.active);eq(#s.plans,0)
s.state.busy=nil;s.tick();eq(#s.plans,1)
-- Typing/captured input/pause cannot consume a pending action.
for _,flag in ipairs({'typing','modal','blocked','recording','paused','editingHud','draggingHud'})do
    c,s=fixture();p=s.offer('start');check(c:accept(p));s.state[flag]=true;s.tick();eq(#s.plans,0,flag)
    s.state[flag]=false;s.tick();eq(#s.plans,(flag=='typing'or flag=='modal')and 1 or 0)
end
-- Profile/config edits and stale confirmations require an entirely fresh preview.
c,s=fixture();p=s.offer('start');s.cfg.start_template='Changed';check(not c:accept(p));eq(#s.plans,0)
c,s=fixture();p=s.offer('start');s.profile.name='Another';check(not c:accept(p))
c,s=fixture();p=s.offer('start');s.tick(61000);check(not c:accept(p))
c,s=fixture();s.cfg.unit='';check(not c:propose('start'))
c,s=fixture();s.profile.name='';check(not c:propose('start'),'Nickname is not IC identity')
c,s=fixture();s.cfg.start_template=string.rep('д',250);check(not c:propose('start'),'CP1251 wire bound')
-- Frozen crew vs permanent contacts, unknown/offline ID, identity reuse.
c,s=fixture();s.crew();p=s.offer('start');eq(p.record.crew[1].player_id,4);eq(p.record.crew[1].generation,0)
check(p.line:find('John Smith',1,true));s.players[4].name='Impostor_Name';check(not c:accept(p))
c,s=fixture();s.crew();s.commit('start');s.sent();eq(c.data.active.crew[1].ic_name,'John Smith')
s.cfg.crew={};eq(#c.data.active.crew,1,'Changing future roster cannot rewrite current crew')
c:playerChanged(4);eq(c.data.active.status,'paused');check(not c.data.active.crew[1].available)
local n=#s.cancels;c:playerChanged(4);check(#s.cancels<=n+1,'No recursive cancel')
s.cfg.crew={{contact_id=1,ic_name='John Smith',role='Водитель'}};s.players[4].connected=true
p=s.offer('resume');eq(p.record.crew[1].generation,2);check(c:accept(p));s.tick(0);s.sent()
eq(c.data.active.status,'active');check(c.data.active.crew[1].available)
s.players[4].connected=false;s.tick();eq(c.data.active.status,'paused')
c,s=fixture();s.crew();s.players[4].near=false;check(not c:propose('start'))
c,s=fixture();s.crew();s.cfg.crew[1].ic_name='';check(not c:propose('start'))
c,s=fixture();s.crew();s.contacts={};check(not c:propose('start'))
c,s=fixture();s.crew();plan=s.commit('start');c:playerChanged(4);eq(c.data.active.status,'paused');eq(#s.cancels,1);check(not c:validPlan(plan))
-- Session discontinuities archive a scene, never announce death or send by themselves.
for _,change in ipairs({'session','local_nick','ped','alive','demo'})do
    c,s=fixture();s.commit('start');s.sent()
    if change=='alive'then s.state.alive=false elseif change=='demo'then s.state.demo=true else s.state[change]='other'end;s.tick()
    check(not c.data.active,change);eq(#c.data.history,1);eq(c.data.history[1].status,'interrupted');eq(#s.plans,1)
end
c,s=fixture();s.commit('start');s.sent();s.tick(30000);eq(c.data.active.elapsed_ms,0,'Stalled client does not invent service time')
s.state.focused=false;s.tick();s.tick();eq(c.data.active.elapsed_ms,0);s.state.focused=true;s.tick();s.tick();eq(c.data.active.elapsed_ms,1000)
c,s=fixture();s.now=4294967280;c:tick(s.state,s.now);s.commit('start');s.sent();s.now=16;c:tick(s.state,s.now);eq(c.data.active.elapsed_ms,32)
-- End report delivery vs explicit local end; cancellation keeps the session.
c,s=fixture();s.commit('start');s.sent();p=s.offer('finish');eq(#c.data.history,0);check(c.data.active)
check(c:accept(p));s.tick(0);plan=s.plans[#s.plans];check(c.data.active);s.sent(plan)
check(not c.data.active);eq(#c.data.history,1);eq(c.data.history[1].status,'finished');eq(#s.cancels,0)
c,s=fixture();s.commit('start');s.sent();s.commit('discard');check(not c.data.active);eq(#s.plans,1);eq(#c.data.history,1)
c,s=fixture();s.commit('start');s.sent();s.cfg.enabled=false;s.tick();p=s.offer('discard');check(c:accept(p));s.tick();check(not c.data.active);eq(#s.plans,1)
c,s=fixture();s.commit('start');check(c:pause());eq(c.data.active.report_status,'Доклад отменён · без повтора');eq(#s.cancels,1)
-- Persistent records never revive native IDs or resume sending on load.
c,s=fixture();s.crew();s.commit('start');s.sent();s.tick()
local clean=assert(module.validate(c.data));eq(clean.active.crew[1].player_id,nil)
local files={['patrol.json']=TEST_JSON_ENCODE(clean)}
local fs={exists=function(p)return files[p]~=nil end,read=function(p)return files[p]end,
    write=function(p,v)files[p]=v;return true end,rename=function(a,b)files[b]=files[a];files[a]=nil;return true end,remove=function(p)files[p]=nil;return true end}
s.env.path='patrol.json';s.env.fs=fs;s.env.json={encode=function(v)return TEST_JSON_ENCODE(v)end,decode=function(v)return TEST_JSON_DECODE(v)end}
s.env.start=function(plan)s.plans[#s.plans+1]=plan;return true end
c=module.new(s.env);check(not c.data.active);check(c.recoverable);s.tick=function(ms)s.now=s.now+(ms or 0);c:tick(s.state,s.now)end;s.tick(0)
eq(#s.plans,1);p=assert(c:propose('restore'));check(c:accept(p));s.tick(0);check(c.data.active);check(not c.recoverable)
check(module.validate(TEST_JSON_DECODE(files['patrol.json'])))
local bad=model.copy(clean);bad.history={model.copy(bad.active)};check(not module.validate(bad))
bad=model.copy(clean);bad.active.elapsed_ms=-1;check(not module.validate(bad))
bad=model.copy(clean);bad.active.crew[1].ic_name='';check(not module.validate(bad))
-- An unused large roster must not break SOS or a short scheduled report.
c,s=fixture();s.crew();local a=assert(c:makeRecord(s.cfg,s.state));local values=c:values(s.state,a)
check(values.crew_roles:find('Водитель',1,true));eq(values.crew_callsigns,'A-1, A-2')
values.crew=string.rep('x',2000);values.crew_roles=string.rep('y',3000)
local alerts=model.alertDefaults();alerts.on_duty=true;alerts.enabled=true
check(require('pa26_alerts').prepare('sos',values,alerts,codec,s.now,1))
check(require('pa26_radio_guard').prepare({template='10-20: {area}.',channel='/r',name='Short'},values,codec,s.now,1))
values.local_tag='bad\n/r';check(not require('pa26_alerts').prepare('sos',values,alerts,codec,s.now,1))
