local support=require 'support.fixture'
local function fixture(options)
    options=options or{};options.legacyWanted=true
    local m=require 'pa26_bindings';options.library=m.copy(options.library or m.defaults(require('pa26_core').defaults()))
    -- This group exercises ordinary custom binds; the new assistant routes have
    -- their own production-default tests in case_ui and procedure_access.
    options.library.procedures.wanted_assistant_enabled=false
    options.library.vehicle.copilot.enabled=false -- Separate normative0420 group covers context actions.
    return support(options)
end
local wheel=require 'pa26_wheel'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local path='moonloader\\config\\police_assistant_2026_library.json'
local function library(s)return s.savedLibrary()end
local function visible(s,text)return table.concat(s.drawnText,'\n'):find(text,1,true)~=nil end
local function healthy(s)
    check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0);eq(s.invalidIOReads,0);eq(s.drawList.Flags,3)
end
local function open(s,index)
    s.step();if s.frames[1].condition()then s.commands.pa26()end
    local catalogue=wheel.build(library(s));local layout=wheel.layout(s.io.DisplaySize.x,s.io.DisplaySize.y,#catalogue.categories)
    local angle=-math.pi/2+(index-.5)*layout.step;local radius=(layout.inner+layout.rootOuter)/2
    s.io.MousePos.x,s.io.MousePos.y=layout.cx+math.cos(angle)*radius,layout.cy+math.sin(angle)*radius
    s.down[0x58]=true;s.step(16,{[0x58]=true});healthy(s);check(s.frames[2].condition())
    s.step(115);healthy(s)
    return layout,catalogue
end
local function child(s,layout,catalogue,index,entry)
    local entries=wheel.entries(catalogue.categories[index]);local arc=wheel.arc(layout,index,#entries)
    local angle=arc.first+(entry-.5)*arc.step;local radius=(layout.childInner+layout.outer)/2
    s.io.MousePos.x,s.io.MousePos.y=layout.cx+math.cos(angle)*radius,layout.cy+math.sin(angle)*radius
    s.drawnText={};s.step();healthy(s)
end
local function release(s)
    s.down[0x58]=false;s.step();healthy(s)
end
-- Category-only release, center, outside and quick taps send/prepare nothing.
for _,position in ipairs({'root','center','outside','tap'})do
    local s=fixture({categoryWheel=true});local layout,catalogue=open(s,1)
    if position=='center'then s.io.MousePos.x,s.io.MousePos.y=layout.cx,layout.cy
    elseif position=='outside'then s.io.MousePos.x,s.io.MousePos.y=layout.cx+layout.outer+20,layout.cy end
    s.step();release(s);s.step(5000);eq(#s.sent,0);check(not s.hasLog('[ДЕМО БИНД]'))
    onScriptTerminate(s.script)
end
-- Production modes, labels and common binder execution in every root-count profile.
for _,profile in ipairs({'compact','extended','full'})do
    local seed=model.defaults(core.defaults());seed.settings.wheel_profile=profile
    local s=fixture({categoryWheel=true,library=seed})
    local layout,catalogue=open(s,1);check(visible(s,'ID 42'));check(visible(s,'Гражданин'))
    child(s,layout,catalogue,1,1);release(s);s.step(100);s.step(1600);s.step(1600)
    eq(#s.sent,0);check(s.hasLog('[ДЕМО БИНД]'));healthy(s);onScriptTerminate(s.script)
end
-- Live command dispatch preserves the captured player and the existing confirmation.
local s=fixture({categoryWheel=true,demo=false})
local layout,catalogue=open(s,3);child(s,layout,catalogue,3,1)
check(visible(s,'ID 37'));check(visible(s,'Player_Name'))
check(s.runtime.wheel.choice,'live route missing')
release(s);s.step(100);check(s.modalOpen,'existing preparation delay must end in confirmation');eq(#s.sent,0)
s.click='НЕТ##confirm-no';s.render();s.step(5000);eq(#s.sent,0);onScriptTerminate(s.script)

s=fixture({categoryWheel=true,demo=false});layout,catalogue=open(s,3);child(s,layout,catalogue,3,1)
-- Click then release in the next game tick must not execute twice.
s.mouseClicks={[0]=true};s.render();s.mouseClicks=nil;release(s);s.step(100)
check(s.modalOpen);s.click='ДА##confirm-yes';s.render();s.step();s.step(100);s.step(1600);s.step(1600)
eq(#s.sent,3);eq(s.sent[3].line,'/wanted 37');s.step(5000);eq(#s.sent,3);onScriptTerminate(s.script)

-- Identity/focus/context changes stop the cached route before dispatch.
for _,change in ipairs({'quit','focus','chat','pause'})do
    s=fixture({categoryWheel=true,demo=false});layout,catalogue=open(s,3);child(s,layout,catalogue,3,1)
    if change=='quit'then s.connected=false
    elseif change=='focus'then onWindowMessage(0x0008,0)
    elseif change=='chat'then s.chat=true
    else s.paused=true end
    s.down[0x58]=false;s.step();s.step(5000);eq(#s.sent,0);check(not s.frames[2].condition());onScriptTerminate(s.script)
end
-- No target: targeted action explains itself, own text is still usable.
local seed=model.defaults(core.defaults());local own=model.newBinding(7);own.script='Тест без человека.';own.wheel_visible=true;own.wheel_group='citizen'
seed.bindings[#seed.bindings+1]=own;seed.next_id=8
s=fixture({categoryWheel=true,demo=false,library=seed});s.aimed=false;s.pool={1};s.targetExists=false
layout,catalogue=open(s,1);child(s,layout,catalogue,1,1);check(visible(s,'Выберите человека'));release(s);eq(#s.sent,0)
layout,catalogue=open(s,1);child(s,layout,catalogue,1,3);release(s);s.step(100);eq(#s.sent,1);eq(s.sent[1].line,'Тест без человека.');onScriptTerminate(s.script)

-- More opens a searchable wheel category, including rows not marked for F11.
seed=model.defaults(core.defaults())
for id=7,14 do local b=model.newBinding(id);b.wheel_visible=true;b.wheel_group='citizen';b.name='Личный '..id
    seed.bindings[#seed.bindings+1]=b;seed.next_id=id+1 end
s=fixture({categoryWheel=true,library=seed});layout,catalogue=open(s,1);child(s,layout,catalogue,1,6);release(s)
check(visible(s,'Колесо → Гражданин'));check(visible(s,'Личный 14'));eq(#s.sent,0)
s.edits={['Найти сценарий##quick']='Личный 14'};s.drawnText={};s.render();check(visible(s,'Личный 14'));check(not visible(s,'Личный 13'))
s.click='Все бинды быстрого меню##quick-wheel-clear';s.render();s.drawnText={};s.render();check(not visible(s,'Колесо →'));onScriptTerminate(s.script)

-- Parameter action opens its existing argument form, with zero sends until Run.
seed=model.defaults(core.defaults());seed.bindings[1].script='Проверка параметра: {param1}.'
s=fixture({categoryWheel=true,demo=false,library=seed});layout,catalogue=open(s,1);child(s,layout,catalogue,1,1);release(s)
check(visible(s,'Аргумент 1'));eq(#s.sent,0)
s.edits={['Аргумент 1##quick1']='Готово'};s.render();s.click='Запустить##run1';s.render();s.step();s.step(100)
eq(#s.sent,1);eq(s.sent[1].line,'Проверка параметра: Готово.');onScriptTerminate(s.script)

-- Empty root opens configuration; editor wheel flags are independent of F11.
seed=model.defaults(core.defaults());seed.vehicle.megaphone_wheel=false
s=fixture({categoryWheel=true,library=seed});layout,catalogue=open(s,4);child(s,layout,catalogue,4,1);release(s)
check(s.frames[1].condition());check(visible(s,'В бинде откройте'));eq(#s.sent,0)
s.ackInfo();s.click='Общее##editor-tab';s.render();s.toggle='В радиальном меню (пешком)##bind';s.render();s.click='Сохранить сценарий';s.render();s.ackInfo()
check(not library(s).bindings[1].wheel_visible);check(library(s).bindings[1].quick);onScriptTerminate(s.script)

-- Native controls persist profile/mode and keep old direct slots available.
s=fixture({categoryWheel=true});s.step();s.page('settings');s.click='3. Управление и колесо##settings-tab-options';s.render()
local originalSlots=model.copy(library(s).wheel)
s.combo='##Количество категорий##wheel-profile';s.click='6##Количество категорий##wheel-profileextended';s.render();s.combo=nil
s.step()
eq(library(s).settings.wheel_profile,'extended')
s.combo='##Способ выбора##wheel-mode';s.click='Прямые действия##Способ выбора##wheel-modeclassic';s.render();s.combo=nil
s.step()
eq(library(s).settings.wheel_mode,'classic');for i,id in ipairs(originalSlots)do eq(library(s).wheel[i],id)end
check(visible(s,'Места прямого меню'));healthy(s);onScriptTerminate(s.script)

-- Viewport fit and actual drawing at required sizes; safe flag restoration on errors.
for _,viewport in ipairs({{1280,720},{1920,1080},{2560,1440}})do
    s=fixture({categoryWheel=true});s.io.DisplaySize.x,s.io.DisplaySize.y=viewport[1],viewport[2]
    layout,catalogue=open(s,2);child(s,layout,catalogue,2,1);check(visible(s,'Наручники'));release(s);onScriptTerminate(s.script)
end
s=fixture({categoryWheel=true});layout,catalogue=open(s,1);s.pathDrawError=true;s.render()
check(s.hasLog('Ошибка интерфейса'));eq(s.drawList.Flags,3);eq(#s.scopes,0);eq(#s.sent,0);onScriptTerminate(s.script)
