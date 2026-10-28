local copy=require('pa26_bindings').copy
local equal=require('pa26_author_presets').equal
local knowledge=require 'pa26_knowledge'
local raw=TEST_JSON_DECODE(TEST_KNOWLEDGE_JSON)
local data,err=knowledge.validate(raw);check(data,err)
local k=knowledge.new();k:activate(data)
local old,current=0,0
for _,a in ipairs(data.articles)do
 if a.code=='constitution'then old=old+1;check(k:isArchived(k.byKey['articles:'..a.id]))end
 if a.code=='constitution725'then current=current+1;check(a.text:find('Статья '..a.article,1,true))end
end
eq(old,87);eq(current,84)
check(k:isArchived(k.byKey['articles:constitution725:30']));check(k:isArchived(k.byKey['articles:constitution725:31']))
for _,id in ipairs({'police604:28.1','police604:28.2','constitution725:10','constitution725:61'})do check(k.byKey['articles:'..id].item.text~='')end
local radio=0;for _,r in ipairs(data.radio)do if r.id:match('^manual4:')then radio=radio+1 end end;eq(radio,54)
eq(k.byKey['radio:manual4:10-1'].item.meaning,'Встреча всех офицеров на дежурстве (включая локацию и код).')
check(k.byKey['radio:manual4:CLEARING CODE 5']);check(k.byKey['radio:manual4:CODE 100'].item.meaning:find('радиомолчания',1,true))
check(k.byKey['rules:manual-current:4:230:1']);check(k.byKey['rules:manual-current:4:230:2'])
for _,r in ipairs(k:search('',{mode='current'}))do check(not k:isArchived(r));check(r.group~='gaps')end
check(#k:search('',{mode='all'})>#k:search('',{mode='current'}))
k.personal.favorites={'articles:constitution:18'};k.personal.notes['articles:constitution:18']='Личная заметка к прежней редакции'
check(k:isFavorite('articles:constitution:18'));eq(k.personal.notes['articles:constitution:18'],'Личная заметка к прежней редакции')
local lib=require 'pa26_library';local json={encode=function(v)return TEST_JSON_ENCODE(v)end,decode=function(v)return TEST_JSON_DECODE(v)end}
check(not lib.decode(TEST_KNOWLEDGE_JSON,json,knowledge.validate),'Ordinary user JSON keeps its 1 MiB bound')
check(lib.decode(TEST_KNOWLEDGE_JSON,json,knowledge.validate,knowledge.MAX_BYTES))
check(not lib.decode(string.rep(' ',knowledge.MAX_BYTES+1),json,knowledge.validate,knowledge.MAX_BYTES))
local cp=require 'pa26_copilot_settings';local ground=require 'pa26_operational';local cfg=cp.defaults()
eq(cfg.stop_ground,'none');eq(cfg.detention_ground,'none');check(not ground.ground('stop','none'))
check(not ground.ground('stop','speed','none'));eq(ground.ground('stop','speed','20to40').part,'2')
eq(ground.find('detention','drugs_storage').game,'06.02');check(not ground.find('detention','drugs_storage').game:find('06.01',1,true))
check(ground.find('detention','disobey_admin').note:find('ПД/ФБР',1,true))
local vehicle=require 'pa26_vehicle'
eq(vehicle.plate({id=7},cfg),'SA-007');eq(vehicle.plate({id=1234},cfg),'SA-1234')
cfg.select_plate='CUSTOM-42';eq(vehicle.plate({id=7},cfg),'CUSTOM-42');cfg.select_plate='';cfg.plate_prefix='RP-';cfg.plate_digits=4
eq(vehicle.plate({id=7},cfg),'RP-0007');cfg.auto_plate=false;eq(vehicle.plate({id=7},cfg),'не указан')
check(not cp.validate({plate_digits=999}));check(not cp.validate({stop_ground='invented'}))
local customized=cp.defaults();customized.templates.wanted_rp='/me моя собственная отыгровка.';customized.templates.risk_single='Моё сохранённое требование.'
local preserved=assert(cp.validate(customized));eq(preserved.templates.wanted_rp,customized.templates.wanted_rp);eq(preserved.templates.risk_single,customized.templates.risk_single)
check(not cp.defaults().templates.risk_single:find('огонь на поражение',1,true))
local timers=require 'pa26_detention_timers';local now=1000;cfg=cp.defaults();local notices={}
local target={account=true,id=37,name='Known_Name',generation=1}
local state={session='one',ped=5,alive=true,demo=false,localId=9,local_nick='Officer_Name',focused=true,paused=false,blocked=false}
local t=timers.new({settings=function()return cfg end,target=function()return copy(target)end,
 valid=function(a)return a.id==target.id and a.name==target.name and a.generation==target.generation end,notice=function(v)notices[#notices+1]=v end})
local function tick(ms)now=now+(ms or 0);t:tick(state,now)end
tick();check(t:act('begin'));check(t:act('lawyer_request'));eq(t:view().remaining,300)
tick(300000);check(t:view().expired);eq(#notices,1);tick(1);eq(#notices,1);eq(t:view().stage,'lawyer_response')
check(t:act('lawyer_answered'));check(t:view().frozen);eq(t:view().remaining,600)
check(not t:act('lawyer_timeout_verified'));check(t:act('lawyer_arrived'));check(not t:view().frozen)
check(t:act('phone_start'));tick(20000);eq(t:view().remaining,160);check(t:act('phone_finished'));check(not t:view().expired)
check(t:act('finish'));check(t:act('begin'));check(t:act('lawyer_request'));check(t:act('lawyer_unavailable'));eq(t:view().stage,'lawyer_unavailable')
check(t:act('phone_start'));tick(180000);eq(t:view().stage,'phone_call');check(t:act('phone_timeout_verified'));eq(t:view().stage,'phone_done')
check(not t:act('phone_start'),'The same case must not grant another 3-minute call')
target.generation=2;tick();check(not t:view().id,'A reused ID cannot inherit a procedural timer')
check(t:act('begin'));state.alive=false;tick();check(not t:view().id);state.alive=true;tick();check(t:act('begin'))
state.session='two';tick();check(not t:view().id);check(t:act('begin'));cfg.detention_timers=false;tick();check(not t:view().id)
cfg.detention_timers=true;cfg.phone_call_seconds=1;check(t:act('begin'));check(t:act('phone_start'));check(t:view().official==false);tick(1000);check(t:view().expired)
local wheel=require 'pa26_wheel';local bindings=require 'pa26_bindings';local b=bindings.defaults()
b.vehicle=require('pa26_vehicle_settings').defaults();b.alerts.enabled=false
local s={onDuty=true,inVehicle=true,copilot={car={id=1},phase='Преследование',pinned='fast_wanted'}}
local w=wheel.build(b,1,false,s);check(w.bySystem['copilot-stop_order']);check(w.bySystem['copilot-pursuit_mark']);check(not w.bySystem.sos)
local stamp=wheel.contextRevision(s);s.inVehicle=false;s.copilot.phase='10-57 FOXTROT';w=wheel.build(b,2,false,s)
check(w.bySystem['copilot-rights']);check(not w.bySystem['copilot-stop_order']);check(wheel.contextRevision(s)~=stamp)
check(wheel.available(w,{kind='copilot',id='copilot-rights',category=w.bySystem['copilot-rights'].category}))
b.vehicle.copilot.enabled=false;check(not wheel.build(b,3,false,s).bySystem['copilot-rights'])
-- Remote mark and verified OOC result chain. Deliberately no streamed ped.
local forms=require 'pa26_case_forms';local prefs=require 'pa26_procedure_settings';local fcfg=prefs.defaults();fcfg.enabled=true
fcfg.mark_command='/setmark {id}';fcfg.mark_verified=true;fcfg.mark_source='OFFLINE CONTRACT'
fcfg.clear_command='/clear {id}';fcfg.clear_verified=true;fcfg.clear_source='OFFLINE CONTRACT'
local plans={};local fstate=copy(state);fstate.inVehicle=false;fstate.session='current';now=100
target={account=true,id=42,name='Remote_Name',generation=1}
local c=forms.new({settings=function()return fcfg end,codec=codec,equal=equal,identity=function()return{}end,
 target=function()return nil,1 end,wantedTarget=function()return copy(target)end,
 validWantedTarget=function(a)return a and equal(a,target)end,validTarget=function()return false end,
 start=function(p)plans[#plans+1]=p;return true end})
c:tick(fstate,now)
local f=assert(c:begin('mark'));eq(f.target.id,42);check(not f.target.ped)
f.phone_known='yes';f.phone_number='555100';f.phone_source='IC-разговор';f.basis='Законная RP-пеленгация';check(not c:branch(f))
f.phone_active='yes';eq(c:branch(f),'ic');local p=assert(c:offer(f));eq(#plans,0);check(c:accept(p));now=now+1;c:tick(fstate,now)
check(c:validPlan(plans[1]));check(plans[1].target==nil);check(plans[1].wantedSubject.account)
target.generation=2;check(not c:validPlan(plans[1]));target.generation=1;c:reset('test');c:tick(fstate,now)
c.reminders={{token='chain',player_id=42,player_name='Remote_Name',generation=1,session='current',reason='OOC',context='Только пеленгация',stars=1,created=0,status='check',phone_number='555100',phone_source='IC-разговор',prior_ic_stars='no'}}
c.reminders[1].actor_life=c.life;c.reminders[1].actor_run=c.runToken
check(not c:chainOffer('chain','mark',true));check(c:changeReminder('chain','issued'));check(not c:chainOffer('chain','mark',false))
p=assert(c:chainOffer('chain','mark',true));check(p.lines[1]:match('^/me '));eq(p.lines[#p.lines],'/setmark 42')
check(c:accept(p));now=now+1;c:tick(fstate,now);local plan=plans[#plans];c:onExecution('sent_line',{plan=plan},'/setmark 42');c:onExecution('completed',{plan=plan})
eq(c.reminders[1].status,'mark_sent');check(not c:chainOffer('chain','clear',true));check(c:changeReminder('chain','located'))
c.reminders[1].prior_ic_stars='yes';check(not c:chainOffer('chain','clear',true));c.reminders[1].prior_ic_stars='no'
p=assert(c:chainOffer('chain','clear',true));check(p.lines[1]:match('^/me '));eq(p.lines[#p.lines],'/clear 42')
check(c:accept(p));now=now+1;c:tick(fstate,now);plan=plans[#plans];c:onExecution('sent_line',{plan=plan},'/clear 42');c:onExecution('completed',{plan=plan})
eq(#c.reminders,1);eq(c.reminders[1].status,'clear_sent');check(prefs.validateReminders(c.reminders));check(c:changeReminder('chain','resolved'));eq(#c.reminders,0)
check(prefs.validate(fcfg))
