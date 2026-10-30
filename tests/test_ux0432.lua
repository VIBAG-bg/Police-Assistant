-- Production main callbacks, independent F4 confirmations, editor and /pt emission.
local fixture=require 'support.fixture';local model=require 'pa26_bindings';local core=require 'pa26_core'
local lib=model.defaults(core.defaults());lib.alerts.enabled=true;lib.alerts.on_duty=true;lib.vehicle.require_patrol=true;lib.patrol_session.enabled=false;lib.profile.name='Иван Петров'
local s=fixture({demo=false,library=lib,alerts=true,notifications=true,copilot=true,productionWindows=true});s.step();s.commands.pa26();s.step();if s.frames[1].condition()then s.commands.pa26();s.step()end
local function click(label)s.click=label;s.render();eq(s.click,nil,label);check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0)end
s.physicalDown={[0x73]=true};s.step();s.physicalDown={};s.step();s.workspace.studio.assistPage='traffic';s.render()
click('Продолжаю патрулирование · Код 4##copilot-quick-patrol_continue');local original=s.workspace.studio.vehicleConfirm;check(original);check(original.report);eq(#s.sent,0)
click('НЕТ##confirm-no');check(s.workspace.studio.reportEdit);check(not s.workspace.studio.vehicleConfirm);eq(#s.sent,0)
s.edits={['##Юнит##report-edit-unit']='2-L-99'};s.render();check(next(s.edits)==nil)
click('Вернуться к предпросмотру##report-edit-preview');local edited=s.workspace.studio.vehicleConfirm;check(edited);check(table.concat(edited.prepared.lines,' '):find('2-L-99',1,true));check(not s.workspace.studio.reportEdit)
click('ДА##confirm-yes');for _=1,12 do s.step(1600)end;check(#s.sent>0);for _,r in ipairs(s.sent)do check(r.line:match('^/r '))end
eq(s.workspace.library.patrol_session.unit,lib.patrol_session.unit);check(not s.patrolSession or not s.patrolSession.data.active)
local before=#s.sent;check(s.workspace:selectTarget({id=37,ped=s.mappedPed,name=s.name}));s.step()
click('Быстрый /pt рядом · ДА/НЕТ##copilot-fast-pt');s.step();s.step();local pt
for _,p in ipairs(s.copilot.offers)do if p.action=='fast_pt'then pt=p end end
check(pt,table.concat(s.logs,' | '));eq(pt.ptTarget.id,37);check(pt.label:find(s.name,1,true));eq(#pt.prepared.lines,1);eq(pt.prepared.lines[1],'/pt 37')
pt.seen=true;check(s.copilot:decide(pt.token,true));for _=1,8 do s.step(1000)end
eq(#s.sent,before+1);eq(s.sent[#s.sent].line,'/pt 37');check(not s.hasLog('Ошибка интерфейса'));eq(s.invalidIOReads,0);onScriptTerminate(s.script)
