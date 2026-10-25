local events=require 'pa26_patrol_events'
local settings=require 'pa26_patrol_event_settings'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local function same(a,b)
    if type(a)~=type(b)then return false end
    if type(a)~='table'then return a==b end
    for k,v in pairs(a)do if not same(v,b[k])then return false end end
    for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local function setup()
    local s={now=1000,stamp=1,cfg=settings.defaults(),target={id=4,ped=5,name='Player_Name'},sent=0}
    s.cfg.enabled=true;s.cfg.require_patrol=false
    s.state={session='erp:7777',ped=1,alive=true,demo=false,focused=true,paused=false,blocked=false,typing=false,
        modal=false,recording=false,editingHud=false,draggingHud=false,local_nick='Officer_One',patrol_id='1',onDuty=true,radioEnabled=true,unit='A-1',area='Ganton'}
    local c=events.new({settings=function()return s.cfg end,patrol=function()return{id=1}end,
        target=function()return model.copy(s.target)end,targetStamp=function()return s.stamp end,
        validTarget=function(t)return t and s.target and t.id==s.target.id and t.ped==s.target.ped and t.name==s.target.name end,
        equal=same,codec=codec,start=function()s.sent=s.sent+1;return true end})
    function s.tick(ms)s.now=s.now+(ms or 16);c:tick(s.state,s.now)end
    function s.form()
        local f,why=c:form('force_used');check(f,why);f.subject='Человек в куртке';f.basis='Подтверждённые обстоятельства';f.details='Специальное средство';return f
    end
    s.tick();return c,s
end
local cfg=settings.defaults();check(not cfg.enabled);eq(cfg.events.force_used.command,'');check(not cfg.events.force_used.suggest)
local legacy=model.copy(cfg);legacy.force_reminder=nil;legacy.force_reminder_enabled=nil;legacy.events.force_used=nil
local normalized=assert(settings.validate(legacy));check(normalized.force_reminder_enabled);eq(normalized.force_reminder,cfg.force_reminder)
eq(normalized.events.detention.template,legacy.events.detention.template);eq(normalized.events.force_used.command,'')
for _,v in ipairs({'',string.rep('x',1025),'\255'})do local raw=model.copy(cfg);raw.force_reminder=v;eq(settings.validate(raw),nil)end
local c,s=setup();local f=s.form();eq(c:propose(f,false),nil);eq(c.data.facts.force_used,nil);eq(#c.followups,0)
f.acknowledged=true;local p,why=c:propose(f,false);check(p,why);eq(#c.followups,0)
check(c:accept(p));eq(#c.followups,0);s.tick();eq(c.data.facts.force_used,1);eq(c.data.reports.force_used,nil);eq(s.sent,0)
local r=c.followups[1];check(r);eq(r.kind,'force');eq(r.body,s.cfg.force_reminder)
local candidate=c:candidates()[1];check(candidate.body:find('Человек в куртке',1,true));check(not candidate.body:find('Player_Name',1,true))
check(not c:decideNotice(r.token,true));c:shown(r.token);check(c:decideNotice(r.token,false));eq(#c:candidates(),0)
s.tick(s.cfg.followup_snooze_ms);eq(#c:candidates(),1);c:shown(r.token);check(c:decideNotice(r.token,true));eq(#c.followups,0)
eq(c.data.facts.force_used,1);eq(s.sent,0);check(events.validate(c.data),'new manual event must roundtrip through the event journal')
for _,change in ipairs({'text','off','stamp','target','life','session','ttl','reset'})do
    c,s=setup();f=s.form();f.acknowledged=true;check(c:accept(assert(c:propose(f,false))));s.tick();r=c.followups[1];check(r)
    if change=='text'then s.cfg.force_reminder='Другой текст.'
    elseif change=='off'then s.cfg.force_reminder_enabled=false
    elseif change=='stamp'then s.stamp=s.stamp+1
    elseif change=='target'then s.target.name='Other_Player'
    elseif change=='life'then s.state.alive=false
    elseif change=='session'then s.state.session='other'
    elseif change=='reset'then c:reset('repair')end
    s.tick(change=='ttl'and s.cfg.followup_ttl_ms or 16);eq(#c.followups,0,change);eq(s.sent,0)
end
c,s=setup();s.cfg.force_reminder_enabled=false;s.tick();f=s.form();f.acknowledged=true;check(c:accept(assert(c:propose(f,false))));s.tick();eq(#c.followups,0);eq(c.data.facts.force_used,1)
c,s=setup();s.state.demo=true;s.tick();f=s.form();f.acknowledged=true;check(c:accept(assert(c:propose(f,false))));s.tick();eq(#c.followups,0);eq(c.data.facts.force_used,nil)
-- Configuration, fact and note are integrated through the real GUI fixture.
local fixture=require 'support.fixture';local library=model.defaults(core.defaults())
library.patrol_events.enabled=true;library.patrol_events.require_patrol=false
local g=fixture({demo=false,library=library,notifications=true,alerts=true});g.step()
check(g.workspace:selectTarget({id=g.id,ped=g.mappedPed,name=g.name}));g.step()
g.weapon=23;g.step();g.events.onSendBulletSync({weaponId=23,hitType=0,targetId=65535});g.step()
eq(g.patrolEvents.data.facts.force_used,nil);eq(#g.patrolEvents.followups,0,'A packet cannot establish force or injury')
g.page('partners')
local function click(label)g.click=label;g.render();eq(g.click,nil,label);check(not g.hasLog('Ошибка интерфейса'));eq(#g.scopes,0)end
click('События##Напарники и служба##partners-pageevents')
local studio=g.workspace.studio;studio.patrolEventKind='force_used';g.render();click('Подготовить событие##patrol-event-new')
g.edits={['##Человек · IC-имя или известные приметы##patrol-event-subject']='Человек в куртке',
    ['##Основание / статья · вручную##patrol-event-basis']='Непосредственная угроза',
    ['##Дополнительные сведения##patrol-event-details']='Применено специальное средство'};g.render();g.edits={}
local before=#g.sent;click('Записать без доклада##patrol-event-local');check(studio:hasWarning() and not studio.patrolEventConfirm)
click('ОК##warning-ok');g.render()
g.toggle='Подтверждаю, что событие действительно произошло##patrol-event-ack';g.render();click('Записать без доклада##patrol-event-local')
check(studio:hasModal());click('НЕТ##confirm-no');g.step();eq(g.patrolEvents.data.facts.force_used,nil)
click('Записать без доклада##patrol-event-local');click('ДА##confirm-yes');g.step();eq(g.patrolEvents.data.facts.force_used,1);eq(#g.sent,before)
local saved=decodeJson(g.files['moonloader\\config\\police_assistant_2026_patrol_events.json']);eq(saved.events[#saved.events].kind,'force_used')
click('Настройки##События##patrol-event-pagesettings')
g.edits={['##После силы: помощь и оформление##patrol-followup-force']='Проверить помощь и необходимое оформление.',
    ['##Текст доклада##patrol-event-template-force_used']='{unit}: применено спецсредство. {details}.'};g.render();g.edits={};g.step(700)
saved=g.savedLibrary()
eq(saved.patrol_events.force_reminder,'Проверить помощь и необходимое оформление.')
eq(saved.patrol_events.events.force_used.template,'{unit}: применено спецсредство. {details}.')
g.toggle='После применения силы напоминать о помощи и оформлении##patrol-event-setting-force_reminder_enabled';g.render();g.step(700)
saved=g.savedLibrary();eq(saved.patrol_events.force_reminder_enabled,false)
eq(#g.sent,before);eq(#g.scopes,0);eq(g.invalidIOReads,0)
