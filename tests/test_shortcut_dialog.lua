local fixture=require 'support.fixture'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local path='moonloader\\config\\police_assistant_2026_library.json'
local function lib(s) return s.savedLibrary() end
local function fresh(s)
    s.drawnText={}; s.buttonCalls={}; s.render(); check(not s.hasLog('Ошибка интерфейса')); eq(#s.scopes,0)
end
local function text(s,needle) return table.concat(s.drawnText,'\n'):find(needle,1,true)~=nil end
local function record(s)
    s.ackInfo()
    s.click='Записать сочетание##bindkey'; fresh(s); check(s.modalOpen)
    check(text(s,'Назначение клавиши')); check(text(s,'Текущее назначение:'))
end
local function press(s,key,mods)
    s.down[0x11]=mods and mods.ctrl or false; s.down[0x12]=mods and mods.alt or false; s.down[0x10]=mods and mods.shift or false
    s.down[key]=true; s.step(16,{[key]=true}); fresh(s)
    s.down[key]=false; s.down[0x11]=false; s.down[0x12]=false; s.down[0x10]=false
    s.step(16); fresh(s)
end
local function cancel(s) s.click='Отмена##capture-cancel'; fresh(s); check(not s.modalOpen); s.step() end
local cfg=core.defaults(); local seed=model.defaults(cfg)
seed.bindings[2].shortcut={key=0x76,ctrl=false,alt=false,shift=false}
local s=fixture({library=seed}); s.step(); s.page('binds'); s.click='Общее##editor-tab'; fresh(s)
local before=s.savedBytes(); record(s)
press(s,0x76); check(text(s,'Сочетание занято биндом «Документы»')); eq(s.savedBytes(),before)
s.click='Назначить##capture-apply'; fresh(s); check(s.modalOpen); eq(s.savedBytes(),before)
press(s,0x78); check(text(s,'Главное меню')); check(s.frames[1].condition()); eq(#s.sent,0)
-- Server keys are kept in the dialog, rejected, and never activate a server window.
check(not s.keyMessage(0x49,false)); press(s,0x49); check(text(s,'I/J/K/Z')); check(s.modalOpen)
press(s,0x77,{ctrl=true}); check(text(s,'Выбрано: Ctrl+F8')); eq(s.savedBytes(),before)
s.click='Назначить##capture-apply'; fresh(s); check(not s.modalOpen); fresh(s)
check(text(s,'Клавиша: Ctrl+F8')); eq(s.savedBytes(),before,'assigning a bind edits its draft only')
s.click='Сохранить сценарий'; fresh(s);s.ackInfo(); eq(lib(s).bindings[1].shortcut.key,0x77); check(lib(s).bindings[1].shortcut.ctrl)
s.down[0x11]=false
record(s); press(s,0x75); cancel(s); fresh(s); check(text(s,'Клавиша: Ctrl+F8'))
record(s); s.step(16,{[0x1B]=true}); check(not s.modalOpen); check(s.frames[1].condition())
s.step(); record(s); s.step(16); s.step(10001); fresh(s); check(s.modalOpen); check(text(s,'Время ожидания истекло'))
s.click='##capture-surface'; fresh(s); s.step(); press(s,0x75)
check(text(s,'Выбрано: F6')); cancel(s); eq(lib(s).bindings[1].shortcut.key,0x77)
onScriptTerminate(s.script)

-- A held key from before capture is ignored until released and pressed again.
s=fixture(); s.step(); s.page('binds'); s.click='Общее##editor-tab'; fresh(s)
s.down[0x75]=true; record(s); s.step(); fresh(s); check(not text(s,'Выбрано:'))
s.step(16,{[0x75]=true}); fresh(s); check(not text(s,'Выбрано:'))
s.down[0x75]=false; s.step(); press(s,0x75); check(text(s,'Выбрано: F6')); cancel(s)
onScriptTerminate(s.script)

-- Window assignment rejects modifiers and conflicts, previews, then saves on Apply.
s=fixture({library=seed}); s.step(); s.page('settings'); s.click='Доступ##settings-tab-options'; fresh(s)
s.click='Назначить##quick_key'; fresh(s); check(s.modalOpen); before=s.savedBytes()
press(s,0x77,{ctrl=true}); check(text(s,'одну клавишу без Ctrl')); eq(s.savedBytes(),before)
press(s,0x76); check(text(s,'Документы')); press(s,0x7B); check(text(s,'Памятки'))
press(s,0x79); check(text(s,'Выбрано: F10')); eq(s.savedBytes(),before)
s.page('hints'); fresh(s); check(s.modalOpen)
s.libraryWriteFail=true; s.click='Назначить##capture-apply'; fresh(s); check(s.modalOpen); eq(s.savedBytes(),before)
fresh(s); check(s.workspace.studio:hasWarning());check(text(s,'Запись не прошла проверку'))
s.click='ОК##warning-ok';fresh(s);fresh(s)
s.libraryWriteFail=false; s.click='Назначить##capture-apply'; fresh(s); check(not s.modalOpen)
eq(lib(s).settings.quick_key,0x79); eq(lib(s).settings.tips_key,0x7B); eq(#s.sent,0)
s.click='Назначить##tips_key'; fresh(s); press(s,0x74)
onWindowMessage(0x0008,0); s.step(); check(not s.frames[1].condition()); check(s.inputDisabled()); eq(lib(s).settings.tips_key,0x7B)
onWindowMessage(0x0007,0); s.step(); check(s.inputDisabled())
s.commands.pa26(); s.step(); check(not s.modalOpen); eq(lib(s).settings.tips_key,0x7B); onScriptTerminate(s.script)

-- Choosing a key cannot continue an @sleep step or launch a bound action.
s=fixture({demo=false}); s.step(); s.page('binds')
s.edits={['##script']='@sleep(F10)\nПродолжение после нового нажатия.'}; fresh(s)
s.click='Сохранить сценарий'; fresh(s);s.ackInfo(); s.commands.pa26run('1'); s.step(); s.step(100)
eq(#s.sent,0); s.commands.pa26(); s.page('binds'); s.click='Общее##editor-tab'; fresh(s); record(s)
s.step(); press(s,0x79); eq(#s.sent,0); s.step(16,{[0x23]=true}); check(s.modalOpen); eq(#s.sent,0)
cancel(s); s.down[0x79]=true; s.step(16,{[0x79]=true}); eq(#s.sent,0)
s.down[0x79]=false; s.step(); s.down[0x79]=true; s.step(16,{[0x79]=true}); s.step()
eq(#s.sent,1); eq(s.sent[1].line,'Продолжение после нового нажатия.'); onScriptTerminate(s.script)

-- Validate current assignments afresh, including an unsaved draft and reserved fields.
local draft=model.copy(seed.bindings[1]); draft.shortcut={key=0x77,ctrl=true,alt=false,shift=false}
local value,err=model.checkKeyAssignment(seed,cfg,draft,{kind='setting',field='quick_key'},{key=0x77,ctrl=false,alt=false,shift=false})
check(not value and err:find('черновиком',1,true))
value,err=model.checkKeyAssignment(seed,cfg,draft,{kind='binding',id=999},{key=0x74,ctrl=false,alt=false,shift=false})
check(not value and err:find('изменился',1,true))
value,err=model.checkKeyAssignment(seed,cfg,draft,{kind='setting',field='unknown'},{key=0x74,ctrl=false,alt=false,shift=false})
check(not value); eq(#s.sent,1)
