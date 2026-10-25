local fixture=require 'support.fixture'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local wheel=require 'pa26_wheel'
local path='moonloader\\config\\police_assistant_2026_library.json'
local function healthy(s)check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(s.invalidIOReads,0)end
local function click(s,label)s.click=label;s.render();eq(s.click,nil,'Missing control: '..label);healthy(s)end
local lib=model.defaults(core.defaults());lib.vehicle.megaphone_enabled=true;lib.vehicle.enabled=false
lib.alerts.on_duty=true;lib.alerts.enabled=false;lib.patrol_session.station='SFPS'
local s=fixture({demo=false,library=lib,alerts=false,notifications=true,categoryWheel=true});s.aimed=false;s.step()
eq(s.vehicleController.state.radioEnabled,false,'The integration must actually run without the radio')
if s.frames[1].condition()then s.commands.pa26()end;s.step()
-- The radial route opens a selector without a car, player, patrol or radio.
local cat=wheel.build(s.workspace.library,1,true);local index
for i,c in ipairs(cat.categories)do if c.id=='service'then index=i end end
local item=cat.byCategory.service.items[1];eq(item.id,'assist-megaphone');check(wheel.available(cat,{kind='assist',id=item.id,category='service'},false,nil))
local layout=wheel.layout(s.io.DisplaySize.x,s.io.DisplaySize.y,#cat.categories)
local angle=-math.pi/2+(index-.5)*layout.step;local radius=(layout.inner+layout.rootOuter)/2
s.io.MousePos.x,s.io.MousePos.y=layout.cx+math.cos(angle)*radius,layout.cy+math.sin(angle)*radius
s.down[0x58]=true;s.step(16,{[0x58]=true});s.step(115)
local entries=wheel.entries(cat.byCategory.service);local arc=wheel.arc(layout,index,#entries)
angle=arc.first+.5*arc.step;radius=(layout.childInner+layout.outer)/2
s.io.MousePos.x,s.io.MousePos.y=layout.cx+math.cos(angle)*radius,layout.cy+math.sin(angle)*radius
s.step();s.down[0x58]=false;s.step();healthy(s)
eq(s.workspace.studio.assistPage,'megaphone');check(s.frames[4].condition());check(not s.workspace.studio.vehicleConfirm);eq(#s.sent,0)
check(not s.vehicleController.selected);check(not s.patrolSession.data.active)
click(s,'Уступите дорогу##assist-say-4');local p=s.workspace.studio.vehicleConfirm
check(p and not p.target);eq(#s.sent,0);click(s,'НЕТ##confirm-no');s.step(2000);eq(#s.sent,0)
click(s,'Уступите дорогу##assist-say-4');local expected=model.copy(s.workspace.studio.vehicleConfirm.prepared.lines)
click(s,'ДА##confirm-yes');eq(#s.sent,0)
for _=1,30 do s.step(150)end
eq(#s.sent,#expected);for i,line in ipairs(expected)do eq(s.sent[i].line,line)end
local sent=#s.sent;s.step(10000);eq(#s.sent,sent);check(not s.vehicleController.phase);check(not s.patrolSession.data.active)
-- The dedicated default key opens this window even when transport is off.
s.commands.pa26();s.commands.pa26();s.step();s.physicalDown={};s.step()
s.physicalDown={[0x12]=true,[0x39]=true};s.step();s.physicalDown={};s.step()
check(s.frames[4].condition());eq(s.workspace.studio.assistPage,'megaphone');check(not s.workspace.studio.vehicleConfirm);eq(#s.sent,sent)
click(s,'Настройки##megaphone-pagesettings')
s.workspace.studio.phraseSlot=4;s.render()
s.edits={['##Текст без /команды##assist-phrase-text']='Говорит {station}. Уступите дорогу.'};s.render();s.edits={};s.step(700)
local saved=s.savedLibrary();eq(saved.vehicle.phrases[4].template,'Говорит {station}. Уступите дорогу.');eq(saved.vehicle.phrases[4].target,'none')
s.drawnText={};s.render();check(table.concat(s.drawnText,'\n'):find('/m Говорит SFPS. Уступите дорогу.',1,true),'General preview must work without a car')
s.toggle='Показывать мегафон в радиальном меню##megaphone-megaphone_wheel';s.render();s.step(700)
saved=s.savedLibrary();eq(saved.vehicle.megaphone_wheel,false);check(not wheel.build(s.workspace.library,2,true).bySystem['assist-megaphone'])
click(s,'Реплики##megaphone-pagephrases');click(s,'Остановиться##assist-say-1')
check(s.workspace.studio:hasWarning());check(not s.workspace.studio.vehicleConfirm);eq(#s.sent,sent)
click(s,'ОК##warning-ok');s.render()
-- The alternate key can be reassigned through the existing capture UI.
click(s,'Настройки##megaphone-pagesettings');click(s,'Назначить##assist-key-vehicle-megaphone_shortcut')
check(s.workspace.studio.keyCapture);eq(s.workspace.studio.keyCapture.request.field,'megaphone_shortcut')
click(s,'Отмена##capture-cancel');healthy(s);eq(#s.sent,sent);onScriptTerminate(s.script)
