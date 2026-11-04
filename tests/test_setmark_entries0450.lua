local fixture=require 'support.fixture';local model=require 'pa26_bindings';local core=require 'pa26_core'
local function setup()
 local lib=model.defaults(core.defaults());lib.profile.name='Тест Офицер';lib.profile.gender='female'
 lib.settings.manual_actions.enabled=false;lib.settings.manual_actions.rules.setmark.enabled=false
 lib.settings.manual_actions.rules.setmark.rp='/me {gender:открыл|открыла} терминал.\n/do Запрос подготовлен.'
 local b=model.newBinding(7);b.name='Tracking';b.script='/setmark 37';b.target_required=false;b.skip_confirmation=true;b.quick=true;b.favorite=true
 b.command_alias='tracktest';b.shortcut={key=0x74,ctrl=false,alt=false,shift=false};b.enabled=true
 lib.bindings[#lib.bindings+1]=b;lib.next_id=8
 local s=fixture({productionWindows=true,demo=false,library=lib,alerts=true,categoryWheel=true});s.step()
 if s.frames[1].condition()then s.commands.pa26();s.step()end
 return s,b
end
local function done(s,name)
 for _=1,20 do s.step(1600)end
 local commands=0;local me,statement=false,false
 for _,r in ipairs(s.sent)do
  if r.line:match('^/me ')then me=true end;if r.line:match('^/do ')then statement=true end
  if r.line:match('^/setmark ')then commands=commands+1;check(me and statement,name..' sent command before RP');eq(r.line,'/setmark 37')end
 end
 eq(commands,1,name..' must send once: '..table.concat(s.logs,'\n'));check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0);onScriptTerminate(s.script)
end
-- Actual main handlers and Workspace executor, not entry labels on a fake plan.
local s,b=setup();s.streamed=false;s.distance=5000;s.commands.setmark('37');done(s,'manual distant connected ID')
s,b=setup();s.commands.tracktest('');done(s,'registered short command')
s,b=setup();s.commands.pa26run('7');done(s,'default PA command alias')
s,b=setup();s.workspace:request({kind='prepare',id=7,args={},start=true,returnTo='binds'});done(s,'F9 binding request')
s,b=setup();s.workspace:request({kind='prepare',id=7,args={},start=true,returnTo='quick'});done(s,'quick/favorite request')
s,b=setup();check(s.runtime.env.startWheelBinding({binding=b,category='other'},nil));done(s,'radial binding callback')
s,b=setup();s.step(20,{[0x74]=true});s.step(20,{});done(s,'custom keyboard shortcut')
s,b=setup();local bridge=s.chatBridge
local event={id=1,kind='local',text='/setmark 37',session=bridge.env.session()}
local payload=encodeJson({schema=1,page='setmark-test',chat=false,dialog=false,busy=false,events={event}})
check(bridge:exchange(payload,s.now));s.step();check(bridge:exchange(payload,s.now));done(s,'existing CEF manual command + duplicate event')
s,b=setup();s.commands.setmark('37');s.step();s.commands.pa26cancel();for _=1,10 do s.step(1600)end
for _,r in ipairs(s.sent)do check(not r.line:match('^/setmark '),'Cancellation stops command')end;onScriptTerminate(s.script)
-- Imported library does not trust persisted execution metadata. Validation rebuilds the plan.
s,b=setup();local raw=model.copy(s.workspace.library);raw.bindings[7].script='/setmark 37'
raw.bindings[7].commandPolicy={verified=true};local imported=assert(model.validate(raw,core.defaults()))
s.workspace.library=imported;s.workspace.commandDirty=true;s.step();s.commands.pa26run('7');done(s,'validated imported profile')
-- Real ordinary F9 button, with no prior interaction/identity/phone wizard.
s,b=setup();s.commands.pa26();s.step();s.page('addons')
s.click='Розыск, штрафы, /setmark##toolprocedures';s.render();eq(s.click,nil)
s.click='Пеленгация##Действие##case-kindmark';s.render();eq(s.click,nil)
s.edits={['##ID подключённого игрока · любая дистанция##tracking-id']='37'};s.render();s.edits={}
s.click='Отыграть RP и выполнить /setmark##tracking-send';s.render();eq(s.click,nil);done(s,'actual F9 setmark button')
-- The built-in procedural wheel route opens the same ordinary action pane.
s,b=setup();s.workspace.library.procedures.enabled=true
check(s.runtime.env.wheelNavigate({kind='procedure',id='procedure-mark',category='wanted'}))
s.render();s.edits={['##ID подключённого игрока · любая дистанция##tracking-id']='37'};s.render();s.edits={}
s.click='Отыграть RP и выполнить /setmark##tracking-send';s.render();eq(s.click,nil);done(s,'built-in procedure wheel + action button')
s,b=setup();check(not s.runtime.env.send(codec.encode('/setmark 37')),'Raw legacy PA sender cannot bypass the prepared executor');eq(#s.sent,0);onScriptTerminate(s.script)
-- Author RP in a bound identity-checked plan is kept, including explicit waits.
s,b=setup();s.commands.pa26select('37');s.step();b=model.find(s.workspace.library,7);b.target_required=true
b.script='/me ввёл ориентировку подозреваемого в навигационный комплекс крузера и запросил пеленг сигнала со спутника.\n@wait(1200)\n/do На тактической карте бортового компьютера отмечен последний сектор нахождения {select_name}.\n@wait(800)\n/setmark {select_id}'
s.workspace:request({kind='prepare',id=7,args={},start=true,returnTo='quick'})
for _=1,25 do s.step(1600)end
local found=0;for _,r in ipairs(s.sent)do check(r.line~='/me открыла терминал.','Never duplicate valid author RP');if r.line=='/setmark 37'then found=found+1 end end
eq(found,1);onScriptTerminate(s.script)
