local fixture=require'support.fixture';local model=require'pa26_bindings';local core=require'pa26_core'
local path='moonloader\\config\\police_assistant_2026_library.json'
local function healthy(s)check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(s.invalidIOReads,0);eq(#s.sent,0)end
local function click(s,label)s.click=label;s.render();eq(s.click,nil,label);healthy(s)end
local function setup()
    local s=fixture({library=model.defaults(core.defaults())});s.step();s.page('binds')
    local st=s.workspace.studio;st:select(1);st.bindPane='editor';st.editorTab='text';s.render()
    s.edits={['##script']='Новый сохранённый текст.'};s.render();s.edits={};check(st.dirty)
    return s,st
end
local s,st=setup();local before=s.savedBytes()
s.page('settings');check(st.pendingNavigation);check(st:hasModal());eq(s.savedBytes(),before)
click(s,'Остаться##changes-stay');check(not st.pendingNavigation);check(st.dirty);eq(s.savedBytes(),before)
s.page('settings');s.libraryWriteFail=true;click(s,'Сохранить##changes-save')
check(st.pendingNavigation);check(st.dirty);eq(s.savedBytes(),before,'A failed disk write cannot continue navigation or discard the draft')
click(s,'ОК##warning-ok');s.render();s.libraryWriteFail=false;click(s,'Сохранить##changes-save');check(not st.pendingNavigation);check(not st.dirty)
eq(s.savedLibrary().bindings[1].script,'Новый сохранённый текст.');healthy(s);onScriptTerminate(s.script)

s,st=setup();s.commands.pa26();s.render();check(st.pendingNavigation);check(s.frames[1].condition(),'F9 cannot silently close a dirty bind')
click(s,'Остаться##changes-stay');check(st.dirty)
s.commands.pa26quick();s.render();check(st.pendingNavigation)
click(s,'Отбросить##changes-discard');check(not st.dirty);check(not st.pendingNavigation);healthy(s);onScriptTerminate(s.script)

-- One transaction saves both documents, and failure preserves both for retry.
s,st=setup();local note=s.workspace.library.notes[1]
st.noteDraft={id=note.id,name='Правки памятки',body='Новый текст памятки.'};st.noteMode=true
local applied=0;check(not st:requestNavigation(function()applied=applied+1 end,'перейти дальше'))
local rev=s.workspace.libraryRevision
check(not st:resolveNavigation(true,{save=function()return nil,'Disk unavailable'end}));eq(applied,0);check(st.dirty);check(st.noteDraft)
check(st:resolveNavigation(true,{save=function(candidate)return s.workspace:save(candidate)end}));eq(applied,1)
eq(s.workspace.libraryRevision,rev+1);local saved=s.savedLibrary();eq(saved.bindings[1].script,'Новый сохранённый текст.');eq(saved.notes[1].body,'Новый текст памятки.')
check(not st:unsavedChanges());healthy(s);onScriptTerminate(s.script)

s=fixture({library=model.defaults(core.defaults())});s.step();s.page('hints');st=s.workspace.studio
click(s,'Редактировать##note');s.edits={['Текст##note']='Черновик памятки остаётся после фонового сохранения.'};s.render();s.edits={}
check(st:unsavedChanges());local copy=model.copy(s.workspace.library);copy.profile.callsign='S-01';check(s.workspace:save(copy));s.render()
eq(st.noteDraft.body,'Черновик памятки остаётся после фонового сохранения.')
s.commands.pa26();s.render();check(st.pendingNavigation);click(s,'Сохранить##changes-save')
eq(s.savedLibrary().notes[1].body,'Черновик памятки остаётся после фонового сохранения.');check(not st:unsavedChanges())
healthy(s);onScriptTerminate(s.script)
