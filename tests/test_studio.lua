local fixture=require 'support.fixture'
local core=require 'pa26_core'
local model=require 'pa26_bindings'
local s=fixture(); s.step(); eq(#s.frames,5)
eq(s.frames[5].LockPlayer,false);eq(s.frames[5].HideCursor,true)
s.step(16,{[0x7A]=true}); check(s.frames[4].condition()); check(not s.frames[1].condition()); eq(s.lockRequests,0)
s.io.WantTextInput=true; s.render(); check(s.keyMessage(0x4A,false)==false)
s.io.WantTextInput=false; s.render(); onWindowMessage(0x0100,0x1B); check(s.inputDisabled()); check(s.keyMessage(0x4A,false))
s.step(16,{[0x7B]=true}); check(s.frames[4].condition()); check(table.concat(s.drawnText,'\n'):find('Как пользоваться биндами',1,true))
onWindowMessage(0x0100,0x1B); s.commands.pa26(); s.page('binds')
s.click='+ Новый сценарий ( Добавить бинд )'; s.render()
s.edits={['Название##bind']='Мой доклад',['Команда запуска (pa26_имя)##bind']='pa26_report',['##script']='{my_name}: район {area}.\n@wait(1500)\nПовторная проверка.'}; s.render()
s.click='Общее##editor-tab'; s.render()
s.toggle='В быстром меню##bind'; s.render(); s.toggle='Избранное##bind'; s.render()
s.click='Сохранить сценарий'; s.render();s.click='ОК##warning-ok';s.render(); s.step()
local path='moonloader\\config\\police_assistant_2026_library.json'; local raw=s.savedLibrary(); check(model.validate(raw,core.defaults()));
local recent={}; for i=math.max(1,#s.drawnText-20),#s.drawnText do recent[#recent+1]=s.drawnText[i] end
eq(#raw.bindings,7,'binding count '..#raw.bindings..' | '..table.concat(recent,' | ')); eq(raw.bindings[7].name,'Мой доклад')
check(s.commands.pa26_report~=nil)
s.commands.pa26_report(''); s.step(); s.step(100); s.step(1500); s.step(1500); s.step(); eq(#s.sent,0); check(s.hasLog('[ДЕМО БИНД]'))
local journalPath='moonloader\\config\\police_assistant_2026_journal.json'
if not s.files[journalPath] then s.step(15000) end
check(s.files[journalPath],'completed scenario journal was not saved'); local saved=decodeJson(s.files[journalPath])
check(#saved.events>0); check(saved.events[#saved.events].demo); eq(saved.events[#saved.events].sent,0)
s.commands.pa26(); s.page('hints'); s.click='Добавить новую памятку'; s.render()
s.edits={['Название##note']='Памятка о смене',['Текст##note']='Сначала проверить связь.\nЗатем начать патруль.'}; s.render(); s.click='Сохранить памятку'; s.render();s.click='ОК##warning-ok';s.render()
raw=s.savedLibrary(); eq(#raw.notes,3); eq(raw.notes[3].name,'Памятка о смене')
s.page('partners'); s.edits={['Игровой ник##partner']='Visible_Partner',['Позывной##partner']='P-12'}; s.render(); s.click='Добавить контакт'; s.render()
raw=s.savedLibrary(); eq(#raw.partners,1); eq(raw.partners[1].callsign,'P-12')
s.commands.pa26export();s.render();s.click='ОК##warning-ok';s.render(); check(s.files['moonloader\\config\\police_assistant_2026_binds_exchange.json'])
s.commands.pa26import(); s.render(); s.click='ДА##confirm-yes'; s.render(); s.step()
raw=s.savedLibrary(); eq(#raw.bindings,14); eq(#raw.notes,3); eq(#raw.partners,1)
for i=8,14 do check(not raw.bindings[i].enabled); eq(raw.bindings[i].shortcut.key,0); eq(raw.bindings[i].command,'') end
eq(raw.profile.name,''); eq(raw.wheel[1],1)
s.page('stats'); s.render(); check(s.invalidIOReads==0)
onScriptTerminate(s.script); check(s.frames[4].removed); eq(s.commands.pa26_report,nil)

-- Text editing and hotkeys work without native rendering in the main coroutine.
s=fixture({render=false}); s.step(); s.commands.pa26quick(); s.step(); eq(s.invalidIOReads,0); onWindowMessage(0x0008,0); check(s.inputDisabled()); onScriptTerminate(s.script)
