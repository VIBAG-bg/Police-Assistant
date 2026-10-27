local fixture=require 'support.fixture'
local model=require 'pa26_bindings';local core=require 'pa26_core'
local function healthy(s)check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0);eq(s.invalidIOReads,0)end
local function ack(s)
    for _=1,35 do
        if not s.workspace.studio:hasWarning()then break end
        s.render();s.click='ОК##warning-ok';s.render()
    end
end
-- Saved documents predating aliases still validate. Short names round-trip
-- through separate bind files, while imports/duplicates clear both launch names.
local lib=model.defaults(core.defaults());lib.bindings[1].command='pa26_passport';lib.bindings[1].command_alias='/passport_rp'
lib=assert(model.validate(lib,core.defaults()));eq(lib.bindings[1].command_alias,'passport_rp')
local users=require 'pa26_user_files';local parts=users.partition(lib)
eq(assert(users.combine(parts,core.defaults())).bindings[1].command_alias,'passport_rp')
local ex=assert(users.exchange(lib,'binds',1));eq(ex.bindings[1].command_alias,'passport_rp')
for _,name in ipairs({'su','wanted','pt','setmark','me','do','try','todo','pa26','pa26quit','giverank','bad name','русский','/a/b'})do
    local b=model.copy(lib.bindings[1]);b.command_alias=name;check(not model.validateBinding(b),name)
end
local collision=model.copy(lib);collision.bindings[2].command_alias='passport_rp';check(not model.validate(collision,core.defaults()))
local s=fixture({demo=true,library=lib});s.step();check(s.commands.pa26_passport and s.commands.passport_rp)
s.page('binds');local studio=s.workspace.studio
studio:select(1);s.render()
local save,bodySave
for _,b in ipairs(s.buttonCalls)do if b.label=='Сохранить сценарий'then save=b;if b.parent=='bind-editor-body##studio'then bodySave=true end end end
check(save);check(not bodySave,'save belongs to the fixed header')
s.click='Общее##editor-tab';s.render();s.edits={['Короткая команда (название)##bind']='my_pass'};s.render()
s.click='Сохранить сценарий';s.render();check(studio:hasWarning());eq(studio:modalIntent({}).title,'Уведомление')
check(studio.feedback:peek().message:find('сохранён',1,true));s.step(10000);check(studio:hasWarning(),'success needs acknowledgement')
local all={};studio:drawNotice({text=function(v)all[#all+1]=v end});eq(#all,0,'no notification footer')
ack(s);s.step();check(s.commands.my_pass);eq(s.commands.passport_rp,nil)
s.click='Действия с биндами##bind-tools';s.render();s.click='Файлы обмена##bind-files';s.render();check(studio:hasWarning());check(studio.feedback:peek().message:find('binds_exchange.json',1,true));ack(s)
s.click='Текст##editor-tab';s.render();s.click='Шаги##mode';s.render();s.render();eq(studio.editor,'steps')
local modes={}
for _,b in ipairs(s.buttonCalls)do
    check(not b.label:match('^> '),'selection uses fill, not a prefix')
    if b.label=='Текст##mode'or b.label=='Шаги##mode'then modes[b.label]=b.color end
end
check(modes['Текст##mode']and modes['Шаги##mode']);check(modes['Шаги##mode'].a>modes['Текст##mode'].a)
studio:duplicateBinding();eq(studio.draft.command,'');eq(studio.draft.command_alias,'')
healthy(s);onScriptTerminate(s.script)
-- A native lock on a stale/self/non-player handle must not hide a nearby
-- officer from the visible gaze fallback. No faction/skin filtering is used.
for _,nativePed in ipairs({1,31415})do
    s=fixture({demo=false});s.name='Officer_Friendly';s.aimed=true;s.aimedPed=nativePed
    s.step();s.commands.pa26();s.down[2]=false;s.step(160)
    s.down[2]=true;s.step(160);s.step(170)
    check(s.workspace.selectedTarget,'RMB selection fallback failed')
    eq(s.workspace.selectedTarget.name,'Officer_Friendly');eq(s.workspace.selectedTarget.id,37);eq(#s.sent,0)
    healthy(s);onScriptTerminate(s.script)
end
-- A number in the nearby UI chooses the same visible officer without needing
-- the exact camera center. Walls, disconnects and stale clicks still fail.
s=fixture({demo=false});s.name='Officer_Friendly';s.sx=100;s.step();s.page('binds');s.click='Выбрать игрока для проверки бинда##bind-target';s.render();s.step(550)
s.edits={['Выбрать игрока по ID##nearby-id']='37'};s.render();s.click='Выбрать по ID##nearby-select-id';s.render()
check(not s.workspace.selectedTarget);s.step(16);check(s.workspace.selectedTarget);eq(s.workspace.selectedTarget.name,'Officer_Friendly');eq(#s.sent,0)
s.workspace:clearTarget('manual');s.clear=false;s.click='Выбрать по ID##nearby-select-id';s.render();s.step(16);check(not s.workspace.selectedTarget)
s.clear=true;s.step(550);s.click='Выбрать по ID##nearby-select-id';s.render();s.events.onPlayerQuit(37);s.step(16);check(not s.workspace.selectedTarget)
healthy(s);onScriptTerminate(s.script)
-- Viewport math keeps the tail visible and never splits UTF-8 byte offsets.
local edit=require 'pa26_text_editor'
local font={CalcTextSizeA=function(_,size,_,wrap,text)return{x=select(2,text:gsub('[^\128-\191]',''))*8,y=size}end}
eq(edit.caretX('начало\nконец',#'начало\nконец',font,16),52)
check(edit.follow(800,950,300,1200)>=800)
eq(edit.follow(0,2000,300,1200),1200)
eq(edit.follow(1000,20,300,1200),8)

