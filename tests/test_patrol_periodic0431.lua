-- The live regression: session preview accepts a template that the automatic
-- radio producer must also accept, including singular and plural grammar.
local prefs=require 'pa26_preferences'
local settings=require 'pa26_patrol_settings'
local guard=require 'pa26_radio_guard'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
for key in pairs(settings.variables)do check(prefs.radioVariables[key],'Automatic radio rejects patrol variable {'..key..'}')end
for _,key in ipairs({'start','resume','finish','crew','periodic'})do
 local template=settings.defaults()[key..'_template']
 local checked,err=prefs.template(template,prefs.radioVariables);check(checked,err)
end

local fixture=require 'support.fixture'
local function click(s,label)s.click=label;s.render();eq(s.click,nil,label);check(not s.hasLog('Ошибка интерфейса'))end
local function textSince(s,first)
 local out={}for i=first,#s.sent do out[#out+1]=s.sent[i].line end;return table.concat(out,'\n')
end
local function setup(occupants,gender,channel,confirm)
 local lib=model.defaults(core.defaults());lib.profile.name='Maximus Walker';lib.profile.callsign=''
 lib.profile.gender=gender;lib.alerts.on_duty=true;lib.patrol_session.enabled=true
 lib.patrol_session.unit='';lib.patrol_session.interval_ms=600000;lib.patrol_session.channel=channel
 lib.patrol_session.confirmation=confirm==true
 local s=fixture({library=lib,demo=false,alerts=true,notifications=true,categoryWheel=true})
 -- Pin only the observed same-car colleague count. All report preparation,
 -- timer, consent, preview, queue and chat encoding are the production path.
 s.occupants=occupants;local radar=s.colleagues;check(radar)
 local observed=radar.view
 radar.view=function(self)
  local state=observed(self);state.patrolOccupants=s.occupants;return state
 end
 s.vehicle=true;s.step();s.page('partners');click(s,'Патруль##Напарники и служба##partners-pagepatrol')
 click(s,'Начать патруль##patrol-start');click(s,'ДА##confirm-yes');s.step()
 for _=1,4 do s.step(1500)end
 check(s.patrolSession.data.active);check(s.patrol.active);eq(s.patrol.env.settings().police_interval_ms,600000)
 check(s.patrolSession.data.active.unit:find(occupants==1 and'-L-'or'-A-',1,true),s.patrolSession.data.active.unit)
 if s.frames[1].condition()then s.commands.pa26();s.step()end
 return s
end

for _,case in ipairs({{1,'male','/f',false},{1,'female','/r',false},{2,'male','/f',false},{3,'female','/d',true}})do
 local occupants,gender,channel,confirm=unpack(case);local s=setup(occupants,gender,channel,confirm)
 local first=#s.sent+1
 for _=1,565 do s.step(1000)end
 eq(#s.sent,first-1,'No periodic report before the ten-minute deadline')
 for _=1,40 do s.step(1000)end
 if confirm then
  eq(#s.sent,first-1,'Confirmation cannot be bypassed')
  local candidate=s.radioGuard:view();check(candidate.visible)
  local decided=false
  for _,ticket in pairs(s.radioGuard.tickets)do if ticket.phase=='confirm'then check(s.radioGuard:decide(ticket.token,true));decided=true end end
  check(decided);for _=1,5 do s.step(1000)end
 end
 local report=textSince(s,first);check(report~='',tostring(s.patrol.error))
 check(report:find(channel..' ',1,true)==1,report)
 check(report:find(occupants==1 and'продолжаю патруль'or'продолжаем патруль',1,true),report)
 check(report:find(occupants==1 and'двигаюсь'or'двигаемся',1,true),report)
 check(report:find(occupants==1 and(gender=='female'and'доступна'or'доступен')or'доступны',1,true),report)
 check(not report:find('[{}]'),'No raw variables sent');eq(s.patrol.error,nil)
 for _=1,20 do s.step(1000)end
 local endOfReport=#s.sent;check(endOfReport>=first and endOfReport-first<3,'One occurrence has at most three parts')
 for _=1,40 do s.step(1000)end;eq(#s.sent,endOfReport,'No duplicate automatic report')
 if occupants==1 and gender=='male'then
  -- Crew changes during the next painted prewarning refresh the pending
  -- report, without restarting the ten-minute clock or sending the old form.
  while s.patrol.remaining>29000 do s.step(1000)end
  s.occupants=2;s.step(1000);s.chat=true
  for _=1,35 do s.step(1000)end;eq(#s.sent,endOfReport,'Chat input postpones delivery')
  s.chat=false;for _=1,8 do s.step(1000)end
  local updated=textSince(s,endOfReport+1);check(updated:find('продолжаем патруль',1,true),updated)
  check(updated:find('-A-',1,true),updated);eq(s.patrol.error,nil)
 end
 local finish,why=s.patrolSession:propose('finish');check(finish,why);check(s.patrolSession:accept(finish))
 for _=1,5 do s.step(1000)end;eq(s.patrolSession.data.active,nil)
 check(not s.hasLog('Периодический доклад: В тексте есть неизвестная переменная'))
 onScriptTerminate(s.script)
end

-- Invalid personal placeholders are not silently removed or sent. The
-- diagnostic identifies the actual typo; an absent known value also fails.
local _,err=prefs.template('Текст {patrol_typo}.',prefs.radioVariables)
check(err and err:find('{patrol_typo}',1,true),tostring(err))
local bad,why=guard.prepare({name='Test',channel='/f',template='{patrol_resume}'},{},codec,1000,1)
check(not bad);check(why:find('patrol_resume',1,true),why)
for _,bad in ipairs({'Текст {unit','Текст {{unit}}','Текст {unit!}'})do check(not prefs.template(bad,prefs.radioVariables))end
