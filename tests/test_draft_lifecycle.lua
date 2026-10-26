local fixture=require 'support.fixture'
local ffi=require 'ffi'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local studioModule=require 'pa26_studio'
local libraryPath='moonloader\\config\\police_assistant_2026_library.json'
local function library(s) return s.savedLibrary() end
local function open(s,page)
    -- These historical cases force unrelated/background library updates. The
    -- user-facing leave/save guard is exercised separately in navigation_guard.
    local editor=s.workspace.studio;local guard=editor.requestNavigation
    editor.requestNavigation=function(_,action)action();return true end
    if not s.frames[1].condition() then s.commands.pa26() end
    s.page(page)
    editor.requestNavigation=guard
end
local function newDraft(s,name,script)
    open(s,'binds'); s.click='+ Новый сценарий ( Добавить бинд )'; s.render()
    s.edits={['Название##bind']=name,['##script']=script}; s.render()
end
local function saveProfile(s)
    open(s,'settings'); s.click='1. Профиль##settings-tab-profile'; s.render()
    s.edits={['Позывной экипажа##profile']='P-65'}; s.render()
    s.step(650)
end

-- Reproduce the user's crash: a new unsaved bind, pending selection, profile save,
-- then "Save and switch". The draft must survive the unrelated library update.
local s=fixture(); s.step()
newDraft(s,'Сохраняемый черновик','Содержимое до перехода.')
s.click='001  Представиться##bind1'; s.render(); check(s.modalOpen)
s.page('settings'); check(s.modalOpen)
s.click='Остаться##changes-stay'; s.render()
saveProfile(s); open(s,'binds')
s.click='001  Представиться##bind1'; s.render()
s.click='Сохранить##changes-save'; s.render(); s.step()
local lib=library(s)
eq(#lib.bindings,7,'draft lost or UI failed: '..table.concat(s.logs,'\n'))
eq(lib.bindings[7].name,'Сохраняемый черновик'); eq(lib.bindings[7].script,'Содержимое до перехода.')
eq(lib.profile.callsign,'P-65'); check(s.frames[1].condition()); check(not s.hasLog('Ошибка интерфейса'))
onScriptTerminate(s.script)

-- A normal return from Settings also retains a brand-new draft and its text buffer.
s=fixture(); s.step(); newDraft(s,'Новый после настроек','Новый текст сохранён.')
saveProfile(s); open(s,'binds'); s.click='Сохранить сценарий'; s.render();s.ackInfo(); s.step()
lib=library(s); eq(#lib.bindings,7); eq(lib.bindings[7].id,7)
eq(lib.bindings[7].name,'Новый после настроек'); eq(lib.bindings[7].script,'Новый текст сохранён.')
check(not s.hasLog('Ошибка интерфейса')); onScriptTerminate(s.script)

-- Duplicate is an unsaved record too; settings must not replace it with the source.
s=fixture(); s.step(); open(s,'binds'); s.click='Дублировать##bind'; s.render()
s.edits={['Название##bind']='Самостоятельная копия',['##script']='Текст копии.'}; s.render()
saveProfile(s); open(s,'binds'); s.click='Сохранить сценарий'; s.render();s.ackInfo(); s.step()
lib=library(s); eq(#lib.bindings,7); eq(lib.bindings[7].name,'Самостоятельная копия')
eq(lib.bindings[7].script,'Текст копии.'); check(lib.bindings[1].script~='Текст копии.')
onScriptTerminate(s.script)

-- Failed saving keeps the same draft and pending destination available for retry.
s=fixture(); s.step(); newDraft(s,'Сохранение с повтором','Текст не теряется.')
s.click='001  Представиться##bind1'; s.render(); local before=s.savedBytes()
s.libraryWriteFail=true; s.click='Сохранить##changes-save'; s.render(); s.step()
eq(s.savedBytes(),before); check(s.frames[1].condition()); check(not s.hasLog('Ошибка интерфейса'))
s.click='ОК##warning-ok'; s.render(); s.render()
s.libraryWriteFail=false; s.click='Сохранить##changes-save'; s.render(); s.step()
lib=library(s); eq(#lib.bindings,7); eq(lib.bindings[7].name,'Сохранение с повтором')
eq(lib.bindings[7].script,'Текст не теряется.'); onScriptTerminate(s.script)

-- Removing a note or contact does not discard an unrelated new/edited bind.
s=fixture(); s.step(); newDraft(s,'Черновик при удалении','До удаления памятки.')
open(s,'hints'); s.click='Удалить##note'; s.render()
s.click='ДА##confirm-yes'; s.render(); s.step(); eq(#library(s).notes,1)
open(s,'binds'); s.click='Сохранить сценарий'; s.render();s.ackInfo(); s.step()
eq(library(s).bindings[7].script,'До удаления памятки.')
open(s,'partners'); s.edits={['Игровой ник##partner']='Draft_Partner',['Позывной##partner']='P-65'}
s.render(); s.click='Добавить контакт'; s.render(); s.step(); eq(#library(s).partners,1)
open(s,'binds'); s.edits={['##script']='Редакция после создания контакта.'}; s.render()
open(s,'partners'); s.click='Draft_Partner · P-65##partner1'; s.render()
s.click='Удалить контакт'; s.render(); s.click='ДА##confirm-yes'; s.render(); s.step()
eq(#library(s).partners,0)
open(s,'binds'); s.click='Сохранить сценарий'; s.render();s.ackInfo(); s.step()
eq(library(s).bindings[7].script,'Редакция после создания контакта.')
onScriptTerminate(s.script)

-- Import consumes provisional IDs. The imported record and the draft both survive.
s=fixture(); s.step(); s.commands.pa26export();s.ackInfo(); newDraft(s,'Черновик при импорте','Мой отдельный текст.')
s.commands.pa26import(); s.render(); s.click='ДА##confirm-yes'; s.render(); s.step()
lib=library(s); eq(#lib.bindings,12); eq(lib.bindings[7].id,7)
local imported=model.copy(lib.bindings[7])
open(s,'binds'); s.click='Сохранить сценарий'; s.render();s.ackInfo(); s.step()
lib=library(s); eq(#lib.bindings,13); eq(lib.bindings[13].id,13)
eq(lib.bindings[13].name,'Черновик при импорте'); eq(lib.bindings[13].script,'Мой отдельный текст.')
eq(lib.bindings[7].name,imported.name); eq(lib.bindings[7].script,imported.script)
check(model.validate(lib,core.defaults())); check(not s.hasLog('Ошибка интерфейса'))
onScriptTerminate(s.script)

-- Intentional deletion/discard resets editor state, including the last saved bind.
s=fixture(); s.step(); open(s,'binds')
for _=1,6 do
    lib=library(s); local row=lib.bindings[1]
    s.click='001  '..row.name..'##bind'..row.id; s.render()
    s.click='Удалить##bind'; s.render(); s.click='ДА##confirm-yes'; s.render(); s.step()
end
eq(#library(s).bindings,0)
newDraft(s,'Первый заново','После пустой библиотеки.')
s.click='Сохранить сценарий'; s.render();s.ackInfo(); s.step(); lib=library(s)
eq(#lib.bindings,1); eq(lib.bindings[1].name,'Первый заново'); eq(model.bindingNumber(lib,lib.bindings[1].id),1)
newDraft(s,'Отменённый черновик','Этот текст не сохранять.')
s.click='001  Первый заново##bind'..lib.bindings[1].id; s.render()
s.click='Отбросить##changes-discard'; s.render(); s.step()
newDraft(s,'Новый после отмены','Сохранить этот текст.')
s.click='Сохранить сценарий'; s.render();s.ackInfo(); s.step(); lib=library(s)
eq(#lib.bindings,2); eq(lib.bindings[2].name,'Новый после отмены'); eq(lib.bindings[2].script,'Сохранить этот текст.')
check(not s.hasLog('Ошибка интерфейса')); onScriptTerminate(s.script)

-- Even an unexpected absent draft must not call the persistence callback or crash.
local empty=model.defaults(core.defaults()); empty.bindings={}
local studio=studioModule.new(s.imgui,ffi,empty)
local writes=0
check(studio:saveDraft({save=function() writes=writes+1; return true end})==false)
eq(writes,0); check(studio.status:find('Выберите бинд',1,true))
