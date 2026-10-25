local fixture=require 'support.fixture';local model=require 'pa26_bindings';local core=require 'pa26_core'
local path='moonloader\\config\\police_assistant_2026_library.json'
local s=fixture({alerts=true,notifications=true,categoryWheel=true});s.step();s.page('settings')
local function tab(name)s.click=name;s.render()end
local function read()return s.savedLibrary()end
tab('Связь##settings-tab-radio');s.toggle='Включить SOS##alerts-sos_enabled';s.render();s.step();check(not read().alerts.sos_enabled)
tab('Профиль##settings-tab-profile');s.edits={['RP-имя##profile']='Auto Officer',['Акцент##profile']='[Русский акцент]:'};s.render();s.edits={}
s.step(300);check(read().profile.name~='Auto Officer');s.step(350);eq(read().profile.name,'Auto Officer');check(not read().alerts.sos_enabled)
local after=s.savedBytes();s.step(1000);eq(s.savedBytes(),after,'idle settings cannot repeat writes')
-- Invalid radio text preserves the last accepted values and supports retry.
tab('Связь##settings-tab-radio');s.edits={['##Текст##alerts-template-shots_template']='{unknown}'};s.render();s.edits={};s.step(650)
check(read().alerts.shots_template~='{unknown}');check(s.workspace.studio.autosaves.alerts.failed)
check(s.workspace.studio:hasWarning());s.click='ОК##warning-ok';s.render();check(not s.workspace.studio:hasWarning())
s.edits={['##Текст##alerts-template-shots_template']='{local_tag} Новый доклад.'};s.render();s.edits={};s.libraryWriteFail=true;s.step(650)
check(read().alerts.shots_template~='{local_tag} Новый доклад.');s.libraryWriteFail=false
check(s.workspace.studio:hasWarning());s.click='ОК##warning-ok';s.render()
s.click='Повторить запись##autosave-alerts';s.render();s.step();eq(read().alerts.shots_template,'{local_tag} Новый доклад.')
-- Pending settings still autosave while closing asks about an unsaved bind.
tab('Профиль##settings-tab-profile');s.edits={['Позывной экипажа##profile']='AUTO-1'};s.render();s.edits={}
s.page('binds');s.click='+ Новый сценарий ( Добавить бинд )';s.render();s.edits={['Название##bind']='Новый несохранённый',['##script']='Текст черновика.'};s.render();s.edits={}
s.commands.pa26();s.render();check(s.workspace.studio.pendingNavigation);s.step(650)
eq(read().profile.callsign,'AUTO-1');check(s.workspace.studio.draft);eq(s.workspace.studio.draft.script,'Текст черновика.');eq(#read().bindings,6)
check(not s.hasLog('Ошибка интерфейса'));eq(s.invalidIOReads,0);onScriptTerminate(s.script)
-- A newly added filter must not be overwritten by a stale empty draft.
s=fixture({alerts=true});s.step();s.page('addons');s.click='Дополнения##toolextras';s.render()
s.edits={['##Новый префикс##newfilter']='[Реклама]'};s.render();s.edits={}
s.click='Добавить выключенный фильтр';s.render();s.step(1000);eq(#read().filters,1);s.step(1000);eq(#read().filters,1)
s.edits={['##Префикс##filter1']='[Другой]'};s.render();s.edits={};s.click='Удалить##filter1';s.render();s.step(700)
s.click='ДА##confirm-yes';s.render();s.step(700);eq(#read().filters,0);check(not s.hasLog('Ошибка интерфейса'));onScriptTerminate(s.script)
