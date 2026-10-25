local fixture=require 'support.fixture'
local knowledge=require 'pa26_knowledge'
local edits=require 'pa26_knowledge_edits'
local model=require 'pa26_bindings'
local path='moonloader\\config\\police_assistant_2026_knowledge_edits.json'
local function has(s,text)return table.concat(s.drawnText,'\n'):find(text,1,true)~=nil end
local function fresh(s)s.drawnText={};s.buttonCalls={};s.render();check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0)end
local function savedState(s)
    check(s.files[path], 'No edits file: '..table.concat(s.drawnText,'\n')..'\n'..table.concat(s.logs,'\n'))
    return TEST_JSON_DECODE(s.files[path])
end
local function click(s,label)s.click=label;fresh(s);eq(s.click,nil,label..' was not clickable');fresh(s)end
local index=knowledge.new();index:activate(assert(knowledge.validate(TEST_JSON_DECODE(TEST_KNOWLEDGE_JSON))))
local function rowLabel(key)
    local r=index.byKey[key];local ref=r.item.reference or r.item.command or(r.group=='radio'and r.item.id or'')
    local title=r.title==ref and ref or(ref~=''and ref..' · '..r.title or r.title)
    return title..'\n'..knowledge.status(r)..'##kb-row-'..key
end
local function openRule(s)
    s.page('knowledge');s.combo='##kb-choice-Раздел';click(s,'Правила##kb-choice-Разделrules');s.combo=nil
    s.edits={['##kb-search']='Основание проверки документов'};fresh(s);s.edits={}
    click(s,rowLabel('rules:document_basis'));fresh(s)
end
local s=fixture();s.step();openRule(s)
local originalBundle=s.files['moonloader\\resource\\pa26\\knowledge-base.json']
click(s,'Редактировать карточку##kb-edit');check(has(s,'Моя версия карточки'))
s.edits={['##kb-edit-title']='Мой порядок проверки документов',['##kb-edit-local_text']='Проверить основание и попросить документ.',
    ['##kb-edit-aliases']='моя проверка\nпаспорт'};fresh(s);s.edits={}
eq(s.files[path],nil,'editing fields must not perform file writes in the renderer')
click(s,'Сохранить карточку##kb-edit-save');eq(s.files[path],nil)
s.step();fresh(s)
local saved=savedState(s);local entry=saved.entries['rules:document_basis'];check(entry)
eq(entry.patch.title,'Мой порядок проверки документов');eq(entry.patch.aliases[2],'паспорт')
check(has(s,'Моя правка'));check(has(s,'Проверить основание и попросить документ.'));eq(#s.sent,0)
eq(s.files['moonloader\\resource\\pa26\\knowledge-base.json'],originalBundle)
click(s,'Посмотреть исходник##kb-source');fresh(s);check(has(s,'Основание проверки документов'))
click(s,'Вернуться к моей версии##kb-source');fresh(s);check(has(s,'Мой порядок проверки документов'))
-- Closing/reopening the menu or visiting another section retains the unsaved editor.
click(s,'Редактировать карточку##kb-edit');s.edits={['##kb-edit-local_text']='Не потерять этот текст.'};fresh(s);s.edits={}
s.page('stats');fresh(s);check(not has(s,'Карточка сохранена.'));s.page('knowledge');fresh(s);check(has(s,'Моя версия карточки'))
s.commands.pa26();s.step();s.commands.pa26();s.step();s.page('knowledge');check(has(s,'Моя версия карточки'))
click(s,'Данные##kb-mode');check(s.modalOpen);check(has(s,'Сохранить изменения карточки?'))
click(s,'Продолжить редактирование##kb-dirty');check(not s.modalOpen);check(has(s,'Моя версия карточки'))
click(s,'Данные##kb-mode');click(s,'Сохранить##kb-dirty');check(not s.modalOpen)
s.step();fresh(s);check(has(s,'Мои карточки и правки'))
saved=savedState(s);eq(saved.entries['rules:document_basis'].patch.local_text,'Не потерять этот текст.')
-- Export is explicit and import replaces only personal cards after a modal.
click(s,'Экспортировать мои карточки##kb-edit-export');s.step();fresh(s)
local exported=path:gsub('_edits%.json$','_edits_export.json');check(s.files[exported])
eq(TEST_JSON_DECODE(s.files[exported]).entries['rules:document_basis'].patch.local_text,'Не потерять этот текст.')
local incoming=edits.defaults();s.files[path:gsub('_edits%.json$','_edits_import.json')]=TEST_JSON_ENCODE(incoming)
click(s,'Проверить файл личных карточек##kb-edit-import');s.step();fresh(s)
click(s,'Импортировать мои карточки##kb-edit-apply');check(s.modalOpen)
local yes,no
for _,b in ipairs(s.buttonCalls)do if b.label=='ДА##kb-confirm'then yes=b elseif b.label=='НЕТ##kb-confirm'then no=b end end
check(yes and no);check(yes.color.g>yes.color.r);check(no.color.r>no.color.g)
click(s,'НЕТ##kb-confirm');s.step();check(TEST_JSON_DECODE(s.files[path]).entries['rules:document_basis'])
click(s,'Импортировать мои карточки##kb-edit-apply');click(s,'ДА##kb-confirm');s.step();fresh(s)
eq(next(TEST_JSON_DECODE(s.files[path]).entries),nil);check(s.files[path..'.bak'])
-- New cards, invalid values, write failures and deletion retain precise state.
click(s,'Всё##kb-mode');click(s,'Создать карточку##kb-new')
s.edits={['##kb-edit-title']='Моя памятка проверки',['##kb-edit-text']='Мои действия.'};fresh(s);s.edits={}
click(s,'Отмена##kb-edit-cancel');check(s.modalOpen)
s.keyMessage(27,true);fresh(s);s.keyMessage(27,false);s.step();check(not s.modalOpen)
check(has(s,'Новая карточка'))
s.libraryWriteFail=true;click(s,'Сохранить карточку##kb-edit-save');s.step();fresh(s)
check(has(s,'Новая карточка'));check(has(s,'Запись не прошла проверку'))
click(s,'ОК##warning-ok');fresh(s)
s.libraryWriteFail=false;click(s,'Сохранить карточку##kb-edit-save');s.step();fresh(s)
saved=TEST_JSON_DECODE(s.files[path]);local createdKey
for key,e in pairs(saved.entries)do if e.kind=='custom'then createdKey=key end end
check(createdKey);check(has(s,'Моя карточка'));check(has(s,'Мои действия.'))
click(s,'Удалить мою карточку##kb-edit-reset');check(s.modalOpen)
click(s,'НЕТ##kb-confirm');s.step();check(TEST_JSON_DECODE(s.files[path]).entries[createdKey])
click(s,'Удалить мою карточку##kb-edit-reset');click(s,'ДА##kb-confirm');s.step();fresh(s)
eq(TEST_JSON_DECODE(s.files[path]).entries[createdKey],nil);eq(#s.sent,0)
-- A new source version displays the conflict instead of silently applying old text.
s=fixture();s.step();openRule(s);click(s,'Редактировать карточку##kb-edit')
s.edits={['##kb-edit-title']='Моя версия заголовка'};fresh(s);s.edits={};click(s,'Сохранить карточку##kb-edit-save');s.step();fresh(s)
local update=TEST_JSON_DECODE(TEST_KNOWLEDGE_JSON);update.catalog_version='new-edited-title'
for _,r in ipairs(update.rules)do if r.id=='document_basis'then r.title='Новый заголовок базы'end end
s.files['moonloader\\config\\police_assistant_2026_knowledge_import.json']=TEST_JSON_ENCODE(update)
click(s,'Данные##kb-mode');click(s,'Проверить файл импорта##kb-import');s.step();fresh(s)
click(s,'Применить базу##kb-apply');click(s,'ДА##kb-confirm');s.step();fresh(s)
click(s,'Сравнить: Новый заголовок базы##kb-review-rules:document_basis');fresh(s)
check(has(s,'Сравнение с обновлённой базой'));check(has(s,'Моя версия заголовка'))
check(has(s,'Новый заголовок базы'));click(s,'Применить выбор##kb-review-save');s.step();fresh(s)
check(has(s,'Выберите вариант для каждого изменившегося поля'))
click(s,'ОК##warning-ok');fresh(s)
s.combo='##kb-choice-Оставить##title';click(s,'Мою версию##kb-choice-Оставить##titlemine');s.combo=nil
click(s,'Применить выбор##kb-review-save');s.step();fresh(s)
check(has(s,'Моя версия заголовка'));check(has(s,'Моя правка'));check(not has(s,'Сравнение с обновлённой базой'))
eq(#s.sent,0)
-- Long forms live in the scrolling card pane at all supported window sizes.
for _,dimensions in ipairs({{760,600},{1200,800},{2560,1440}})do
    s=fixture();s.step();s.resizeWindows={['Police Assistant 2026##pa26-main']={x=dimensions[1],y=dimensions[2]}}
    openRule(s);click(s,'Редактировать карточку##kb-edit');fresh(s);eq(#s.sent,0)
end
-- Structured sanctions and RP steps remain editable without JSON or nested child scrollbars.
local function openEntry(s,group,key,query)
    s.page('knowledge');local label
    for _,g in ipairs(knowledge.groups)do if g[1]==group then label=g[2]end end
    s.combo='##kb-choice-Раздел';click(s,label..'##kb-choice-Раздел'..group);s.combo=nil
    s.edits={['##kb-search']=query};fresh(s);s.edits={};click(s,rowLabel(key));click(s,'Редактировать карточку##kb-edit')
end
s=fixture();s.step();openEntry(s,'offenses','offenses:UK:39','УК ст. 39')
click(s,'Изменить санкции##kb-edit-sanctions')
s.edits={['##kb-edit-sanction-1-min']='',['##kb-edit-sanction-1-max']='30',
    ['##kb-edit-sanction-1-condition']='Только при установленных обстоятельствах.'};fresh(s);s.edits={}
click(s,'Сохранить карточку##kb-edit-save');s.step();fresh(s)
saved=savedState(s);local sanction=saved.entries['offenses:UK:39'].patch.sanctions[1]
eq(sanction.min,nil);eq(sanction.max,30);eq(sanction.condition,'Только при установленных обстоятельствах.')
s=fixture();s.step();openEntry(s,'drafts','drafts:rights','Миранда')
click(s,'Изменить реплики и шаги##kb-edit-steps')
local initial=#index.byKey['drafts:rights'].item.steps
click(s,'Добавить шаг##kb-edit-add-step')
s.edits={['##kb-edit-step-'..(initial+1)..'-text']='Временно добавленный шаг.'};fresh(s);s.edits={}
click(s,'Выше##kb-step-'..(initial+1));click(s,'Удалить##kb-step-'..initial)
click(s,'Добавить шаг##kb-edit-add-step')
s.edits={['##kb-edit-step-'..(initial+1)..'-text']='Сохранённый шаг.'};fresh(s);s.edits={}
local typeLabel='##kb-choice-Тип шага##edit-step-'..(initial+1)
s.combo=typeLabel;click(s,'Продолжить вручную'..typeLabel..'manual_continue');s.combo=nil
s.combo=typeLabel;click(s,'Реплика'..typeLabel..'speech');s.combo=nil
s.io.WantTextInput=true;s.keyMessage(13,true);s.step();s.keyMessage(13,false);s.io.WantTextInput=false
click(s,'Сохранить карточку##kb-edit-save');s.step();fresh(s)
saved=savedState(s);local entry=saved.entries['drafts:rights']
eq(#entry.patch.steps,initial+1);eq(entry.patch.steps[initial+1].text,'Сохранённый шаг.')
eq(entry.base_item.source_recommended_text,index.byKey['drafts:rights'].item.source_recommended_text)
eq(entry.patch.source_recommended_text,nil);eq(#s.sent,0)
