-- Tester regression: a painted 30-second warning must lead to durable Y/N,
-- while driving, crossing city boundaries, or temporarily using chat/windows.
local core=require 'pa26_core';local model=require 'pa26_bindings';local prefs=require 'pa26_preferences'
local Guard=require 'pa26_radio_guard';local Patrol=require 'pa26_patrol'
local function setup()
 local s={now=1000,cfg=prefs.radioGuardDefaults(),plans={},logs={},state={session='server',ped=1,local_nick='Maximus_Walker',demo=false,alive=true,onDuty=true,radioEnabled=true,focused=true,paused=false,blocked=false,
  typing=false,recording=false,unit='1-L-1',crew='Maximus Walker',city='Лос-Сантос',area='Ganton',map_square='S-19',direction='Север',directionKnown=true,my_name='Maximus Walker',patrol_resume='продолжаю патруль'}}
 s.patrol={enabled=true,hud=true,mode='police',confirmation=true,post='',police_interval_ms=600000,police_channel='/f',police_template='{unit}, {patrol_resume} в {city}, {area} ({map_square}), курс {direction}.'}
 local guard
 guard=Guard.new({settings=function()return s.cfg end,patrol=function()return s.patrol end,codec=codec,
  log=function(text)s.logs[#s.logs+1]=text end,start=function(plan)s.plans[#s.plans+1]=plan;return true end,
  cancel=function(token)for _,plan in ipairs(s.plans)do if plan.radioGuard.token==token then guard:onExecution('cancelled',{plan=plan})end end end})
 local timer=Patrol.new({settings=function()return s.patrol end,clockPolicy=function()return s.cfg.count_during_input end,
  lead=function()return s.cfg.lead_ms end,preview=function(key,cfg,remaining)return guard:track(key,Guard.patrolSpec(cfg),remaining)end,
  ready=function(key)return guard:ready(key)end,dispatch=function(_,_,key)return guard:dispatch(key)end,
  retire=function(key)guard:retire(key)end,drop=function(key)local t=guard.tickets[key];if t then guard:cancel(t.token)end end})
 function s.tick(ms,paint)
  s.now=s.now+(ms or 1000);guard:tick(model.copy(s.state),s.now);timer:tick(model.copy(s.state),s.now)
  if paint~=false then for _,c in ipairs(guard:candidates())do guard:shown(c.token)end end
 end
 function s.advance(ms,paint)for _=1,ms/1000 do s.tick(1000,paint)end end
 function s.ticket()return guard.tickets[timer.currentKey]end
 function s.complete(plan)for i=1,#plan.steps do guard:onExecution('sent_line',{plan=plan,index=i})end;s.tick()end
 s.tick(0);return s,guard,timer
end
-- Reproduce expiration without any motion first: it previously auto-cancelled
-- a patrol confirmation fifteen seconds after painting it.
local s,g,p=setup();s.advance(602000);local t=s.ticket();check(t and t.phase=='confirm');local token=t.token
s.advance(20000);check(s.ticket(),'Patrol Y/N must not silently disappear after 15 seconds');eq(s.ticket().phase,'confirm');eq(s.ticket().token,token);eq(#s.plans,0)
-- Travel during every rendered frame cannot cancel or restart the occurrence.
s,g,p=setup();s.advance(570000);t=s.ticket();check(t);token=t.token;local cycle=p.cycle
for i=1,700 do
 s.state.city=i%2==0 and'Лос-Сантос'or'Ред-Каунти';s.state.area='Район '..i;s.state.map_square='S-'..(i%24+1);s.state.direction=i%2==0 and'Север'or'Юг'
 s.state.model=i%2==0 and'Police LS'or'Sultan';s.state.vehicle_id=i;s.tick(50)
end
t=s.ticket();check(t);eq(p.cycle,cycle);eq(t.token,token);eq(t.phase,'confirm');eq(#s.plans,0)
-- Y approves the exact most recently PAINTED report, even if a new live
-- location is observed just before the key is processed.
local painted=model.copy(t.plan);s.state.area='Следующий район';s.tick(50,false)
check(g:decide(token,true));s.tick(50);eq(#s.plans,1);local plan=s.plans[1];eq(table.concat(plan.lines,'\n'),table.concat(painted.lines,'\n'))
for i=1,25 do s.state.city='Город '..i;s.state.area='Район '..i;s.tick(50);check(g:validPlan(plan),'Approved snapshot survives normal travel in the queue')end
s.complete(plan);local count=#s.plans;s.advance(30000);eq(#s.plans,count);eq(p.cycle,cycle+1)
-- Hidden input/modal and higher-priority notices delay; they never approve or
-- discard an outstanding patrol report. A later N skips this occurrence only.
s,g,p=setup();s.advance(602000);t=s.ticket();token=t.token
for _,key in ipairs({'typing','modal','alertPending'})do s.state[key]=true;s.advance(25000,false);eq(#s.plans,0);eq(s.ticket().phase,'confirm');check(not g:decide(token,true));s.state[key]=false;s.tick()end
check(g:decide(token,false));s.tick();eq(#s.plans,0);check(p.remaining>590000)
-- A stale/unpainted preview, changed profile/settings, or a new session must
-- not inherit consent. These remain genuine cancellations.
s,g,p=setup();s.advance(600000,false);t=s.ticket();check(t and t.phase=='pending');check(not g:decide(t.token,true));eq(#s.plans,0)
s,g,p=setup();s.advance(602000);t=s.ticket();s.state.my_name='Other Officer';s.tick();eq(#s.plans,0);check(not g:decide(t.token,true))
s,g,p=setup();s.advance(602000);t=s.ticket();s.patrol.police_channel='/r';s.tick();check(not g:decide(t.token,true));eq(#s.plans,0)
s,g,p=setup();s.advance(602000);t=s.ticket();s.state.session='other';s.tick();check(not g:decide(t.token,true));eq(#s.plans,0)
-- Losing focus or a long clock gap before dispatch revokes the old Y, then
-- paints a fresh warning/preview. It never silently reuses stale consent.
for _,gap in ipairs({false,true})do
 s,g,p=setup();s.advance(602000);t=s.ticket();s.state.busy=true;check(g:decide(t.token,true));check(t.acceptedPlan)
 if gap then s.tick(10000,false)else s.state.focused=false;s.tick();s.state.focused=true;s.tick()end
 check(not t.acceptedPlan);check(not t.accepted);s.state.busy=false;s.state.area='Новое место';s.advance(32000)
 eq(#s.plans,0);eq(t.phase,'confirm');check(g:decide(t.token,false));s.tick()
end
-- Six complete ten-minute occurrences, solo / team grammar, one queued plan
-- per explicit Y, no silent retries or duplicate reports.
s,g,p=setup()
for n=1,6 do
 s.state.unit=n%2==0 and'1-A-1'or'1-L-1';s.state.crew=n%2==0 and'Maximus Walker, Partner Name'or'Maximus Walker'
 s.state.patrol_resume=n%2==0 and'продолжаем патруль'or'продолжаю патруль'
 s.advance(602000);t=s.ticket();eq(t.phase,'confirm');s.advance(20000);eq(t.phase,'confirm');check(g:decide(t.token,true));s.tick()
 eq(#s.plans,n);check(table.concat(s.plans[n].lines,' '):find(s.state.patrol_resume,1,true));s.complete(s.plans[n])
end
-- Real main, ImGui notification paint and physical Y while crossing regions.
local fixture=require 'support.fixture';local lib=model.defaults(core.defaults())
lib.alerts.enabled=true;lib.alerts.on_duty=true;lib.profile.name='Maximus Walker';lib.patrol_session.enabled=true
lib.patrol_session.confirmation=true;lib.patrol_session.interval_ms=600000;lib.patrol_session.channel='/f'
local f=fixture({library=lib,demo=false,alerts=true,notifications=true,categoryWheel=true});f.step();f.page('partners')
local function click(label)f.click=label;f.render();eq(f.click,nil,label);check(not f.hasLog('Ошибка интерфейса'))end
click('Патруль##Напарники и служба##partners-pagepatrol');click('Начать патруль##patrol-start');click('ДА##confirm-yes')
for _=1,5 do f.step(1500)end
if f.frames[1].condition()then f.commands.pa26();f.step()end
local initial=#f.sent;f.patrol.remaining=31000
local x=1500;getCharCoordinates=function()return x,-1500,13 end
for i=1,65 do x=i%2==0 and 1500 or -1500;f.step(1000)end
local live=f.radioGuard:view();check(live.visible);eq(live.phase,'confirm');eq(#f.sent,initial)
f.physicalDown={[0x59]=true};f.step(50);f.physicalDown={};for _=1,8 do f.step(500)end
check(#f.sent>initial,'A physical Y transmits the continuation');for i=initial+1,#f.sent do check(f.sent[i].line:match('^/f '))end
local last=#f.sent;for _=1,20 do f.step(1000)end;eq(#f.sent,last);check(not f.hasLog('Ошибка интерфейса'));eq(f.invalidIOReads,0);onScriptTerminate(f.script)
