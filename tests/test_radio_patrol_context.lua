local fixture=require 'support.fixture'
local core=require 'pa26_core'
local model=require 'pa26_bindings'
local function click(s,label)s.click=label;s.render();eq(s.click,nil,label);check(not s.hasLog('Ошибка интерфейса'))end
local seed=model.defaults(core.defaults());seed.patrol_session.enabled=true;seed.patrol_session.unit='A-1'
seed.profile.name='Victor Auditore';seed.profile.callsign='A-1'
seed.patrol_session.post='Пост А';seed.alerts.patrol.post='Другой пост'
seed.alerts.sos_template='{unit}: {officer}. Помощь! {post}, {area}.'
local s=fixture({library=seed,demo=false,alerts=true,categoryWheel=true});s.step()
s.page('partners');click(s,'Патруль##Напарники и служба##partners-pagepatrol')
click(s,'Начать патруль##patrol-start');click(s,'ДА##confirm-yes');s.step();s.step(1500);s.step()
local baseline=#s.sent;check(s.patrolSession.data.active)
if s.frames[1].condition()then s.commands.pa26();s.step()end
s.commands.pa26sos();s.step();check(s.alerts.pending)
check(s.alerts.pending.plan.lines[1]:find('A-1: Victor Auditore.',1,true),'Emergency radio receives the active patrol context')
check(s.alerts.pending.plan.lines[1]:find('Пост А',1,true))
s.commands.pa26();s.step();s.page('settings');click(s,'4. Рация и тревоги##settings-tab-radio')
s.drawnText={};s.render();check(table.concat(s.drawnText,'\n'):find('/r A-1: Victor Auditore. Помощь! Пост А,',1,true),'Preview uses the active patrol post, matching dispatch')
local plan=model.copy(s.alerts.pending.plan);check(s.alerts:validPlan(plan))
local refreshed=model.copy(s.alerts.state);refreshed.unit='B-2'
check(s.alerts:updateContext(refreshed));check(not s.alerts:validPlan(plan),'A changed unit invalidates the frozen preview before sending')
local previousLife=s.alerts.life;refreshed.session='another:7777';check(not s.alerts:updateContext(refreshed))
check(s.alerts.life>previousLife);check(not s.alerts.pending);eq(#s.sent,baseline)
eq(#s.scopes,0);eq(s.invalidIOReads,0);onScriptTerminate(s.script)
return TEST_CHECKS
