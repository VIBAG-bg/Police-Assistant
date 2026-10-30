local setup=require 'support.copilot_fixture';local copy=require('pa26_bindings').copy
local D=require 'pa26_dispatch';local prefs=require 'pa26_copilot_settings'
local cp,v,s=setup();s.cfg.require_patrol=true;s.cfg.megaphone_require_patrol=true;s.tick()
eq(#D.primaryActions,6);eq(#D.actions,21)
for root,rows in pairs(D.followups)do
 eq(#rows,3)
 for _,row in ipairs(rows)do
  local p,why=cp:propose(row[1]);check(p,why);check(p.report);check(not p.needsPatrol);check(p.carFree);check(not p.dispatchRp)
  for _,line in ipairs(p.prepared.lines)do check(line:match('^/r '));check(not line:match('^/me '));check(not line:find('{',1,true))end
 end
end
for _,row in ipairs(D.primaryActions)do if row[1]~='gas_order'then local p=assert(cp:propose(row[1]));check(p.report);check(p.prepared.lines[1]:match('^/me '))end end
local p=assert(cp:propose('patrol_continue'));check(p.report);check(not p.needsPatrol);check(not cp.phase);check(not p.prepared.lines[1]:find('на неизвестно',1,true))
local fields=copy(p.reportValues);fields.unit='2-L-42';fields.crew='Иван Петров';fields.area='Garcia';fields.map_square='J-6'
local edited=assert(cp:editReport(p,fields));check(table.concat(edited.prepared.lines,' '):find('2-L-42',1,true));eq(s.cfg.copilot._report_values,nil)
local wires=table.concat(edited.prepared.lines,'\n');check(cp:accept(edited));s.tick();local plan=s.plans[#s.plans];eq(table.concat(plan.lines,'\n'),wires)
cp:onExecution('completed',{plan=plan});s.tick();check(not cp.phase)
for _,field in ipairs({'unit','crew','area'})do local bad=copy(fields);bad[field]='';check(not cp:editReport(p,bad));bad[field]='x\n/pt 42';check(not cp:editReport(p,bad))end
s.state.onDuty=false;s.tick();check(not cp:propose('patrol_continue'));s.state.onDuty=true;s.cfg.copilot.enabled=false;s.tick();check(not cp:propose('patrol_continue'))
local custom=prefs.defaults();custom.templates.explain_stop='Моя собственная фраза: {stop_ground}.';custom.templates.stolen_car='Мой поиск {area}.';custom.ground_speech.speed='Я хочу уточнить скорость.'
local validated=assert(prefs.validate(custom));eq(validated.templates.explain_stop,custom.templates.explain_stop);eq(validated.templates.stolen_car,custom.templates.stolen_car);eq(validated.ground_speech.speed,custom.ground_speech.speed)
custom.templates.explain_stop='Причина остановки: {stop_ground}. Основание: {ground_article}.';eq(assert(prefs.validate(custom)).templates.explain_stop,'{ground_speech}')
custom.ground_speech.speed='{ground_speech}';check(not prefs.validate(custom))
cp,v,s=setup();s.state.inVehicle=false;s.car.distance=2;s.person.distance=2;s.tick();cp.phase='10-55';cp:beginIncident()
local nav=assert(cp:propose('explain_stop'));local cfg=copy(s.cfg.copilot);cfg.stop_ground='wrong_way';cfg._ground_speech='Вы выехали на встречную полосу. Давайте уточним, что произошло.'
local g=assert(require('pa26_operational').ground('stop','wrong_way'));eq(g.article,'')
local speech=assert(cp:proposeGround(nav,cfg,g));local lines=table.concat(speech.prepared.lines,'\n');check(lines:find('/s '..cfg._ground_speech,1,true));check(not lines:find('Причина остановки:',1,true));check(not lines:find('Основание: .',1,true))
cp.manualUdDone=true;local noIntro=assert(cp:proposeGround(nav,cfg,g));check(not table.concat(noIntro.prepared.lines,' '):find('/ud ',1,true))
cfg._ground_speech='/su 42 8 1';check(not cp:proposeGround(nav,cfg,g),'A speech field cannot turn into a server command')
cfg.ground_channel='';cfg._ground_speech=nil;cfg.templates.explain_stop='/clear 42';check(not cp:proposeGround(nav,cfg,g))
