local fixture=require 'support.fixture'
local model=require 'pa26_bindings'
local studio=require 'pa26_studio'
local core=require 'pa26_core'
local path='moonloader\\config\\police_assistant_2026_library.json'
local function text(s,needle) return table.concat(s.drawnText,'\n'):find(needle,1,true)~=nil end
local function fresh(s)
    s.drawnText={}; s.drawnLabels={}; s.buttonCalls={}; s.render()
    check(not s.hasLog('Ошибка интерфейса')); eq(#s.scopes,0)
end
local function press(s,key)
    check(not s.keyMessage(key,true)) -- library consumes before this script
    s.step(); fresh(s)
    check(not wasKeyPressed(key)); check(not isKeyDown(key))
end
local function release(s,key)
    check(not s.keyMessage(key,true,0x0101)); s.step(); fresh(s)
end
local function record(s)
    s.ackInfo()
    s.click='Записать сочетание##bindkey'; fresh(s); fresh(s)
    check(s.modalOpen); check(text(s,'Нажмите клавишу'))
end
local function apply(s)
    s.click='Назначить##capture-apply'; fresh(s); check(not s.modalOpen)
    fresh(s);s.ackInfo(); s.click='Сохранить сценарий'; fresh(s);s.ackInfo()
    return s.savedLibrary().bindings[1].shortcut
end
local function cancel(s)
    s.click='Отмена##capture-cancel'; fresh(s); check(not s.modalOpen); s.step()
end
local function caps(s,expected)
    local found={}
    for _,label in ipairs(s.drawnLabels) do
        if label.y and label.text~='+' and label.size>=18 and not label.text:find('##',1,true) then found[label.text]=true end
    end
    for _,key in ipairs(expected) do check(found[key],'keycap missing: '..key) end
end
local s=fixture({consumeKeyboard=true}); s.step(); s.page('binds'); s.click='Общее##editor-tab'; fresh(s)
record(s); local before=s.savedBytes()
press(s,0x77); caps(s,{'F8'}); check(text(s,'Отпустите клавиши')); check(not text(s,'Выбрано:'))
s.click='Назначить##capture-apply'; fresh(s); check(s.modalOpen); eq(s.savedBytes(),before)
release(s,0x77); check(text(s,'Выбрано: F8')); eq(s.savedBytes(),before)
local shortcut=apply(s); eq(shortcut.key,0x77); check(not shortcut.ctrl)

-- Modifiers added after the primary key join the same chord. No game polling.
record(s); press(s,0x77); press(s,0x11); caps(s,{'Ctrl','F8'})
release(s,0x77); check(text(s,'Отпустите клавиши'))
release(s,0x11); check(text(s,'Выбрано: Ctrl+F8'))
shortcut=apply(s); eq(shortcut.key,0x77); check(shortcut.ctrl and not shortcut.shift)

record(s); press(s,0x11); press(s,0x10); caps(s,{'Ctrl','Shift'})
check(text(s,'Добавьте основную клавишу')); press(s,0x77); caps(s,{'Ctrl','Shift','F8'})
release(s,0x11); release(s,0x10); release(s,0x77)
check(text(s,'Выбрано: Ctrl+Shift+F8'))
shortcut=apply(s); check(shortcut.ctrl and shortcut.shift and not shortcut.alt)

-- Too many modifiers / two primary keys are explained and cannot be applied.
record(s); before=s.savedBytes()
press(s,0x11); press(s,0x12); press(s,0x10); press(s,0x77)
check(text(s,'Слишком много клавиш')); check(text(s,'Максимум 3 клавиши'))
release(s,0x11); release(s,0x12); release(s,0x10); release(s,0x77)
s.click='Назначить##capture-apply'; fresh(s); check(s.modalOpen); eq(s.savedBytes(),before)
s.click='##capture-surface'; fresh(s); fresh(s); check(text(s,'Нажмите клавишу'))
press(s,0x77); press(s,0x75); release(s,0x77); release(s,0x75)
check(text(s,'одну основную клавишу')); eq(s.savedBytes(),before)
press(s,0x75); release(s,0x75); check(text(s,'Выбрано: F6')); cancel(s)

-- Escape must work through ImGuiIO too; the library suppresses script messages.
record(s); press(s,0x1B); check(not s.modalOpen); check(s.frames[1].condition())
s.step(); check(s.frames[1].condition(),'held Escape must not close the underlying workspace')
s.keyMessage(0x1B,true,0x0101); s.step(); record(s); cancel(s)

-- Left/right modifiers are normalized to one cap rather than treated as keys.
record(s); press(s,0xA3); press(s,0xA1); press(s,0x75)
caps(s,{'Ctrl','Shift','F6'}); check(not text(s,'VK 163'))
release(s,0xA3); release(s,0xA1); release(s,0x75)
shortcut=apply(s); eq(shortcut.key,0x75); check(shortcut.ctrl and shortcut.shift)

-- Safe error recovery for reserved keys and Windows; no server action is sent.
record(s); press(s,0x78); release(s,0x78); check(text(s,'Главное меню'))
press(s,0x5B); press(s,0x75); release(s,0x5B); release(s,0x75)
check(text(s,'Windows оставлена системе')); cancel(s); eq(#s.sent,0)
for _,key in ipairs(s.serverKeys) do eq(key,0x1B,'recorded keys must not reach server input') end
fresh(s); local deletion
for _,button in ipairs(s.buttonCalls) do if button.label=='Удалить##bind' then deletion=button end end
check(deletion); check(not text(s,'Удалить выбранный'))
onScriptTerminate(s.script)

-- Central recording surface and key labels stay inside the modal at supported sizes.
for _,viewport in ipairs({{640,480},{1280,720},{2560,1440}}) do
    s=fixture({consumeKeyboard=true}); s.io.DisplaySize.x,s.io.DisplaySize.y=viewport[1],viewport[2]
    s.step(); s.page('binds'); s.click='001  Представиться##bind1'; fresh(s)
    s.click='Общее##editor-tab'; fresh(s); record(s)
    press(s,0x11); press(s,0x10); press(s,0x22)
    local surface
    for _,button in ipairs(s.buttonCalls) do if button.label=='##capture-surface' then surface=button end end
    check(surface and surface.height==126)
    for _,label in ipairs(s.drawnLabels) do if label.text=='Ctrl' or label.text=='Shift' or label.text=='PageDown' or label.text=='+' then
        check(label.x>=surface.x); check(label.x+label.measure.x<=surface.x+surface.width+.1)
        check(label.y>=surface.y); check(label.y+label.measure.y<=surface.y+surface.height+.1)
    end end
    release(s,0x11); release(s,0x10); release(s,0x22); cancel(s); onScriptTerminate(s.script)
end

-- New limit is enforced on Apply; legacy records remain valid and unchanged.
local cfg=core.defaults(); local lib=model.defaults(cfg); local raw={key=0x75,ctrl=true,alt=true,shift=true}
check(model.shortcut(raw)); lib.bindings[1].shortcut=raw; check(model.validate(lib))
local checked,err=model.checkKeyAssignment(lib,cfg,lib.bindings[1],{kind='binding',id=lib.bindings[1].id},raw)
check(not checked and err:find('Максимум 3',1,true)); check(lib.bindings[1].shortcut.alt)

-- Independent pure state reader covers keys held when a capture starts.
local state={}; local keys={[0x75]=true}; local mods={ctrl=false,alt=false,shift=false,super=false}
eq(studio.captureInput(state,keys,mods),nil)
eq(studio.captureInput(state,keys,mods),nil)
keys[0x75]=false; studio.captureInput(state,keys,mods)
keys[0x75]=true; local input=studio.captureInput(state,keys,mods); eq(input.proposal.key,0x75); check(not input.finished)
keys[0x75]=false; input=studio.captureInput(state,keys,mods); check(input.finished)
