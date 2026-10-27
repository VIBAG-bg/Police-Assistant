local core=require 'pa26_core'
local model=require 'pa26_bindings'
local binder=require 'pa26_binder'
local support=require 'support.fixture'
local function fixture(options)options=options or{};options.nearby=false;return support(options)end

local b=model.newBinding(8)
local ctx={values={my_weapon='MP5',D='12'},gender='male',session='test',now=10000,demo=false}
b.script='Здравствуйте.\n@wait(1500)\nНовая реплика. {D} {my_weapon}'
local plan,err=binder.compile(b,ctx,{},codec)
check(plan,err); check(not plan.requirements.target); check(not plan.requirements.closest)
eq(plan.target,nil); eq(plan.closest,nil); eq(plan.lines[2],'Новая реплика. 12 MP5')

b.script='Оружие: {closest_weapon}'
plan,err=binder.compile(b,ctx,{},codec)
check(not plan); check(err:find('{closest_weapon}',1,true),'missing person must explain the exact variable')
local req=binder.requirements(b)
check(not req.target); check(req.closest); eq(#req.closest_sources,1)
local hints=table.concat(binder.requirementHints(req),'\n')
check(hints:find('независимо от галочки',1,true)); check(hints:find('{my_weapon}',1,true))
b.script='Оружие: {closest_weapon}; снова {closest_weapon}'
eq(#binder.requirements(b).closest_sources,1,'repeated tokens have one explanation')

-- Non-executable comments must not acquire another person.
b.script='-- {closest_weapon} {select_id} @check(true) @select(37)\nЗдравствуйте.'
req=binder.requirements(b); check(not req.target); check(not req.closest); check(not req.nearby)
check(binder.compile(b,ctx,{},codec))
b.target_required=true
plan,err=binder.compile(b,ctx,{},codec); check(not plan); check(err:find('галочка',1,true))
b.target_required=false; b.script='@check(true)\nЗдравствуйте.'
req=binder.requirements(b); check(req.target); check(req.target_sources[1]:find('@check',1,true))
b.script='@check(false)\nЗдравствуйте.'; check(not binder.requirements(b).target)
b.script='/cuff {id}'; req=binder.requirements(b); check(req.target); eq(req.target_sources[1],'{id}')
check(not binder.compile(b,ctx,{},codec),'unchecked box does not invent an ID for a command')
b.script='-- {closest_id}\n{team_count} коллег рядом.'
req=binder.requirements(b); check(req.nearby); check(not req.closest); check(not req.target)

local path='moonloader\\config\\police_assistant_2026_library.json'
local function library(s) return s.savedLibrary() end
local function openLibrary(s)
    if not s.frames[1].condition() then s.commands.pa26() end
    s.page('binds')
end
local function drawn(s,needle)
    for _,line in ipairs(s.drawnText) do if line:find(needle,1,true) then return true end end
    return false
end
local function renderFresh(s)
    s.drawnText={}; s.labels={}; s.render()
end
local function watchRows(s)
    local button=s.imgui.Button
    s.imgui.Button=function(label,...)
        if label:find('##bind%d+$') then s.labels[#s.labels+1]=label end
        return button(label,...)
    end
    s.labels={}
end
local function contiguousRows(s,count)
    renderFresh(s); eq(#s.labels,count)
    for number,label in ipairs(s.labels) do eq(label:sub(1,3),string.format('%03d',number)) end
end
local function create(s,name,script)
    openLibrary(s); s.click='+ Новый сценарий ( Добавить бинд )'; s.render()
    s.edits={['Название##bind']=name,['##script']=script or 'Здравствуйте.'}; s.render()
    s.click='Сохранить сценарий'; s.render();s.ackInfo(); s.step()
end

-- Reproduce delete 007 -> next draft. Order is contiguous and identity remains stable.
local s=fixture(); s.step(); openLibrary(s); watchRows(s)
create(s,'Седьмой'); eq(library(s).bindings[7].id,7)
s.click='Действия с биндами##bind-tools';s.render();s.click='Удалить##bind'; s.render(); s.click='ДА##confirm-yes'; s.render(); s.step()
eq(#library(s).bindings,6); eq(library(s).next_id,8)
s.click='+ Новый сценарий ( Добавить бинд )'; renderFresh(s); check(drawn(s,'Сценарий 007'))
s.edits={['Название##bind']='Повторно седьмой'}; s.render(); s.click='Сохранить сценарий'; s.render();s.ackInfo(); s.step()
local lib=library(s); eq(#lib.bindings,7); eq(lib.bindings[7].id,8); contiguousRows(s,7)
s.click='Запуск##editor-tab'; renderFresh(s)
check(drawn(s,'Сценарий 007')); check(drawn(s,'/pa26run 8'),'stable invocation is shown separately from list order')
s.click='Действия с биндами##bind-tools';s.render();s.click='Дублировать##bind'; renderFresh(s); check(drawn(s,'Сценарий 008'))
s.click='Сохранить сценарий'; s.render();s.ackInfo(); s.step(); contiguousRows(s,8)
lib=library(s); eq(lib.bindings[8].id,9)

-- Delete in the middle, reorder and search: original row numbers and associations survive.
s.click='002  Документы##bind2'; s.render()
s.click='Действия с биндами##bind-tools';s.render();s.click='Удалить##bind'; s.render(); s.click='ДА##confirm-yes'; s.render(); s.step()
lib=library(s); eq(#lib.bindings,7); eq(lib.wheel[2],0)
for _,i in ipairs({1,3,4,5,6}) do eq(lib.wheel[i],i) end
contiguousRows(s,7); eq(model.bindingNumber(lib,8),6); eq(model.bindingNumber(lib,9),7)
s.click='006  Повторно седьмой##bind8'; s.render()
s.click='##bind-up8'; s.render(); s.step()
lib=library(s); eq(model.bindingNumber(lib,8),5); contiguousRows(s,7)
s.edits={['Поиск##library']='Повторно седьмой'}; renderFresh(s)
check(#s.labels>=2); for _,label in ipairs(s.labels) do check(label:sub(1,3)=='005' or label:sub(1,3)=='007') end
eq(lib.wheel[1],1); eq(lib.next_id,10); check(model.validate(lib,core.defaults()))
onScriptTerminate(s.script)

-- Full real-mode fixture: no aim, no visible remote player, own weapon only.
s=fixture({demo=false}); s.targetExists=false; s.aimed=false; s.pool={1}
local weaponReads=0
getCurrentCharWeapon=function(ped) eq(ped,1,'own weapon bind must not read another player'); weaponReads=weaponReads+1; return 29 end
s.step(); create(s,'Свое оружие','Здравствуйте.\n@wait(1500)\nНовая реплика.\n@wait(1500)\nНовая реплика. {D} {my_weapon}')
check(drawn(s,'Можно запускать без другого игрока.'))
s.commands.pa26run('7'); s.step(); s.step(100)
for _=1,12 do s.step(1500) end
eq(#s.sent,3); check(s.sent[3].line:find('MP5',1,true)); check(weaponReads>0)
eq(s.poolReads,0); eq(s.remoteIdentityReads,0); eq(s.charLookups,0)
onScriptTerminate(s.script)

-- UI updates the explanation as the actual script changes, including checkbox changes.
s=fixture(); s.step(); openLibrary(s)
s.click='+ Новый сценарий ( Добавить бинд )'; s.render()
s.edits={['##script']='{closest_weapon}'}; renderFresh(s)
check(drawn(s,'Ближайший игрок нужен: {closest_weapon}.')); check(drawn(s,'{my_weapon}'))
s.edits={['##script']='{my_weapon}'}; renderFresh(s)
check(drawn(s,'Можно запускать без другого игрока.')); check(not drawn(s,'Ближайший игрок нужен'))
s.click='Общее##editor-tab'; s.render(); s.toggle='Требовать выбранного игрока##bind'; renderFresh(s)
check(drawn(s,'Выбранный игрок нужен: включена галочка'))
onScriptTerminate(s.script)
