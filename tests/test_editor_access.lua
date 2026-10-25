local fixture=require 'support.fixture'
local studioModule=require 'pa26_studio'
local model=require 'pa26_bindings'
local path='moonloader\\config\\police_assistant_2026_library.json'

local function library(s) return s.savedLibrary() end
local function open(s)
    if not s.frames[1].condition() then s.commands.pa26() end
    s.page('binds')
end
local function text(s,needle)
    for _,line in ipairs(s.drawnText) do if line:find(needle,1,true) then return true end end
    return false
end
local function create(s,name,script)
    open(s); s.click='+ Новый сценарий ( Добавить бинд )'; s.render()
    s.edits={['Название##bind']=name,['##script']=script}; s.render()
    s.click='Сохранить сценарий'; s.render();s.ackInfo(); s.step()
end
local function focus(s,label,cursor,first,last)
    s.focusInput={label=label,cursor=cursor,first=first or cursor,last=last or cursor}; s.render()
end
local function variable(s,name)
    s.edits={['Найти переменную##search']=name}; s.render()
    s.combo='##Вставка##variable'; s.render()
    local info
    for _,v in ipairs(model.variables) do if v[1]==name then info=v[2] end end
    check(info)
    s.click='{'..name..'} · '..info..'##Вставка##variable'..name
    s.render(); s.combo=nil
    s.click='Вставить {'..name..'}##insert'; s.render(); s.render()
end

-- Byte boundaries, replacement, reverse selections and full buffers.
local result,pos=studioModule.insertText('АБВ',2,2,2,'{my_id}',64)
eq(result,'А{my_id}БВ'); eq(pos,9)
result,pos=studioModule.insertText('АБВ',4,4,2,'{my_id}',64)
eq(result,'А{my_id}В'); eq(pos,9)
check(not studioModule.insertText('АБВ',1,1,1,'{my_id}',64),'never split a UTF-8 character')
check(not studioModule.insertText('abc',3,3,3,'{my_id}',5),'overflow leaves the buffer intact')

local s=fixture(); s.step(); create(s,'Вставка','Начало. Конец.')
local prefix='Начало. '
focus(s,'##script',#prefix)
-- Search and choosing a variable take focus; the text cursor must remain remembered.
variable(s,'my_id')
s.click='Сохранить сценарий'; s.render();s.ackInfo(); s.step()
eq(library(s).bindings[7].script,'Начало. {my_id}Конец.')
check(text(s,'Источник: SA:MP API')); check(not text(s,'Вставка недоступна'))

-- Replacing Cyrillic selected text, not appending to the end.
s.edits={['##script']='Первая строка.\nСтарая вставка.\nПоследняя строка.'}; s.render()
local start=#'Первая строка.\n'
focus(s,'##script',start+#'Старая',start,start+#'Старая')
variable(s,'my_weapon')
s.click='Сохранить сценарий'; s.render();s.ackInfo(); s.step()
eq(library(s).bindings[7].script,'Первая строка.\n{my_weapon} вставка.\nПоследняя строка.')

-- The active step receives insertion; other steps and waits remain unchanged.
s.edits={['##script']='Первая.\n@wait(1500)\nВторая.'}; s.render()
s.click='Шаги##mode'; s.render(); focus(s,'##textstep3',#'Вто')
variable(s,'area')
s.click='Сохранить сценарий'; s.render();s.ackInfo(); s.step()
eq(library(s).bindings[7].script,'Первая.\n@wait(1500)\nВто{area}рая.')

-- Structural edits discard the old step index instead of inserting into another reply.
s.click='Удалить##step1'; s.render()
local before=library(s).bindings[7].script
variable(s,'my_id')
check(text(s,'Поставьте курсор в нужную реплику'))
s.click='ОК##warning-ok'; s.render(); s.render()
s.click='Сохранить сценарий'; s.render();s.ackInfo(); s.step()
eq(library(s).bindings[7].script,'@wait(1500)\nВто{area}рая.')
check(before~=library(s).bindings[7].script)

-- Switching scripts cannot reuse the previous caret; selecting the same row keeps edits.
s.click='001  Представиться##bind1'; s.render(); s.click='Текст##mode'; s.render()
s.edits={['##script']='Свежий текст.'}; s.render()
s.click='001  Представиться##bind1'; s.render()
variable(s,'my_id'); s.click='Сохранить сценарий'; s.render();s.ackInfo(); s.step()
eq(library(s).bindings[1].script,'Свежий текст.{my_id}')
onScriptTerminate(s.script)

-- Explicit row controls: title edits, vector play runs, information stays in the editor.
s=fixture(); s.step(); create(s,'Запуск кнопкой','Проверка кнопки.')
s.click='Общее##editor-tab'; s.render(); s.toggle='В быстром меню##bind'; s.render()
s.click='Сохранить сценарий'; s.render();s.ackInfo(); s.step()
s.sent={}; s.logs={}; s.click='007  Запуск кнопкой##bind7'; s.render(); s.step(100)
check(not s.hasLog('[ДЕМО БИНД]'),'library title only selects for editing')
s.drawnText={}; s.click='Общее##editor-tab'; s.render()
check(text(s,'Клавиша: Не назначено')); check(text(s,'Меню: F11'))
check(text(s,'Можно запускать без другого игрока.')); eq(#s.sent,0)
s.popup=nil; s.click='##bind-run7'; s.render(); s.step(); s.step(100); s.step()
check(s.hasLog('[ДЕМО БИНД]')); eq(#s.sent,0)

-- Unsaved text is never silently replaced by execution of the saved version.
open(s); s.edits={['Название##bind']='Несохранённый заголовок'}; s.render()
s.logs={}; s.click='##bind-run7'; s.render(); s.step(100)
check(text(s,'Сохраните изменения перед запуском')); check(not s.hasLog('[ДЕМО БИНД]'))
onScriptTerminate(s.script)
