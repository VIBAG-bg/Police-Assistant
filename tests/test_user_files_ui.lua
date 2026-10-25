local fixture=require 'support.fixture'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local base='moonloader\\config\\police_assistant_2026'
local function click(s,label)
    s.ackInfo()
    s.click=label;s.render();check(not s.click,'Button not reached: '..label)
    check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'))
end
local function payload(s,kind)return TEST_JSON_DECODE(assert(s.files[base..'_'..kind..'_exchange.json']))end
local seed=model.defaults(core.defaults());seed.profile.name='Private Officer';seed.notes[1].body='Private notes';seed.partners={{id=1,nickname='Private_Partner',callsign='P-7'}};seed.next_partner_id=2
local s=fixture({library=seed});s.step();s.page('binds')
local legacy=s.files[base..'_library.json'];local original=s.savedBytes()
click(s,'Экспорт всех биндов');local exported=payload(s,'binds')
eq(#exported.bindings,6);check(not exported.notes and not exported.profile and not exported.partners and not exported.settings)
check(not s.files[base..'_exchange.json'],'old mixed exchange must not be exported')
click(s,'Экспорт выбранного бинда');eq(#payload(s,'binds').bindings,1);eq(s.savedBytes(),original)
-- A portable file may originate from another user's on-disk binds document.
s.files[base..'_binds_exchange.json']=s.files[base..'_binds.json']
click(s,'Импорт биндов');check(s.modalOpen);click(s,'НЕТ##confirm-no');s.step();eq(s.savedBytes(),original)
click(s,'Импорт биндов');local snapshot=s.workspace.studio.importPreview
-- Replacing the file after preview cannot alter the data approved in the modal.
local foreign=model.copy(snapshot);foreign.bindings[1].name='Unapproved replacement';s.files[base..'_binds_exchange.json']=TEST_JSON_ENCODE(foreign)
click(s,'ДА##confirm-yes');s.step();local lib=s.savedLibrary();eq(#lib.bindings,12)
eq(lib.bindings[7].name,snapshot.bindings[1].name);eq(#lib.notes,2);eq(lib.notes[1].body,'Private notes');eq(lib.profile.name,'Private Officer');eq(#lib.partners,1)
for i=7,12 do check(not lib.bindings[i].enabled);check(not lib.bindings[i].skip_confirmation);eq(lib.bindings[i].command,'');eq(lib.bindings[i].shortcut.key,0)end
s.render();s.step();eq(#s.savedLibrary().bindings,12,'held YES must not import twice')
eq(s.files[base..'_library.json'],legacy);eq(#s.sent,0)
-- Separate note exchange never changes binds, shortcuts, profile or contacts.
s.page('hints');click(s,'Экспорт всех заметок##notes-export');local notes=payload(s,'notes')
eq(#notes.notes,2);check(not notes.bindings and not notes.profile and not notes.partners)
click(s,'Экспорт выбранной заметки##notes-export-one');eq(#payload(s,'notes').notes,1)
local bindsBefore=s.files[base..'_binds.json'];local settingsBefore=s.files[base..'_settings.json']
click(s,'Импорт заметок##notes-import');check(s.modalOpen);click(s,'ДА##confirm-yes');s.step()
eq(#s.savedLibrary().notes,3);eq(s.files[base..'_binds.json'],bindsBefore);eq(s.files[base..'_settings.json'],settingsBefore)
-- A binds file in the notes slot, bad JSON and excessive counts do not write.
original=s.savedBytes();s.files[base..'_notes_exchange.json']=s.files[base..'_binds_exchange.json']
click(s,'Импорт заметок##notes-import');check(not s.workspace.studio.importPreview);check(s.workspace.studio:hasWarning());eq(s.savedBytes(),original)
click(s,'ОК##warning-ok');s.render()
s.files[base..'_notes_exchange.json']='{broken';click(s,'Импорт заметок##notes-import');check(not s.workspace.studio.importPreview);check(s.workspace.studio:hasWarning());eq(s.savedBytes(),original)
click(s,'ОК##warning-ok');s.render()
-- Limit/ID exhaustion rejects the complete append rather than partly importing.
local all=s.savedLibrary();all.bindings={};all.wheel={0,0,0,0,0,0};all.next_id=129
for id=1,128 do local row=model.newBinding(id);row.name='Бинд '..id;row.script='Текст.';all.bindings[id]=row end
check(s.workspace:save(all));original=s.savedBytes();check(not s.workspace:import(exported));eq(s.savedBytes(),original)
all=s.savedLibrary();all.next_id=999999999;check(s.workspace:save(all));original=s.savedBytes()
check(not s.workspace:import(exported));eq(s.savedBytes(),original);eq(#s.sent,0)
-- Old mixed exchange files are accepted only for the explicitly selected kind.
s.files[base..'_notes_exchange.json']=nil;s.files[base..'_exchange.json']=legacy
local legacyNotes=assert(s.workspace:prepareImport('notes'));check(legacyNotes.notes);check(not legacyNotes.bindings and not legacyNotes.partners)
onScriptTerminate(s.script)
