local fixture=require 'support.fixture'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local function healthy(s)
    check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(s.invalidIOReads,0)
end
local function click(s,label)s.click=label;s.render();eq(s.click,nil,'Missing control: '..label);healthy(s)end
local function edit(s,values)s.edits=values;s.render();s.edits={};healthy(s)end
local function setup(verified)
    local lib=model.defaults(core.defaults());lib.procedures.enabled=true
    -- Only local fake transport syntax; release default remains empty.
    if verified then lib.procedures.mark_command='/setmark {id}';lib.procedures.mark_verified=true;lib.procedures.mark_source='LOCAL TEST CONTRACT'end
    local s=fixture({demo=false,library=lib});s.step()
    check(s.workspace:selectTarget({id=s.id,ped=s.mappedPed,name=s.name}));s.step()
    s.page('addons');click(s,'Розыск, штрафы, /setmark##toolprocedures');click(s,'Пеленгация##Действие##case-kindmark');return s
end
local function form(s)
    click(s,'Новая форма##case-new');click(s,'Далее · основание##case-next')
    eq(s.workspace.studio.caseForm.stage,'identity','A nickname or ID does not supply an IC phone')
    click(s,'ОК##warning-ok');s.render()
    click(s,'Да##Номер известен вашему персонажу?##case-phone_knownyes')
    edit(s,{['##Известный IC-номер телефона##case-phone_number']='555-0100',
        ['##Откуда персонажу известен номер##case-phone_source']='Сказал в IC-разговоре'})
    click(s,'Далее · основание##case-next')
    edit(s,{['##Основание и условия пеленгации##case-basis']='Проверенное основание'})
    click(s,'Проверить полный текст##case-preview')
end
local s=setup(false);form(s);local st=s.workspace.studio
check(not s.caseForms:preview(st.caseForm).ready);eq(#s.sent,0)
click(s,'Создать отключённый черновик бинда##case-draft')
check(not st.draft.enabled);check(not st.draft.script:find('555-0100',1,true));eq(#s.sent,0)
s=setup(true);form(s);click(s,'Подтвердить выполнение##case-send');click(s,'НЕТ##confirm-no')
s.step();eq(#s.sent,0)
click(s,'Подтвердить выполнение##case-send');click(s,'ДА##confirm-yes');eq(#s.sent,0)
for _=1,45 do s.step(100)end
eq(#s.sent,3);check(s.sent[1].line:match('^/me '));check(s.sent[1].line:find('555-0100',1,true))
check(s.sent[2].line:match('^/do '));eq(s.sent[3].line,'/setmark 37');healthy(s)
-- There is no automatic /su alongside a marker operation.
for _,row in ipairs(s.sent)do check(not row.line:match('^/su '))end
-- Changing the selected person during the RP sequence cancels its remaining tail.
s=setup(true);form(s);click(s,'Подтвердить выполнение##case-send');click(s,'ДА##confirm-yes');s.step();eq(#s.sent,1)
s.workspace:clearTarget();s.step(2000);eq(#s.sent,1);check(not s.workspace.executor.queue)
-- Separate OOC form still requires acknowledgement and a stated basis.
s=setup(true);click(s,'Новая форма##case-new')
click(s,'OOC · отдельная процедура##Ветка пеленгации##case-modeooc')
click(s,'Далее · основание##case-next');eq(s.workspace.studio.caseForm.stage,'identity')
click(s,'ОК##warning-ok');s.render()
s.toggle='Понимаю, что выбираю отдельную OOC-механику##case-ooc-ack';s.render();click(s,'Далее · основание##case-next')
eq(s.workspace.studio.caseForm.stage,'identity','OOC acknowledgement does not invent an IC phone')
click(s,'ОК##warning-ok');s.render()
click(s,'Да##Номер известен вашему персонажу?##case-phone_knownyes')
edit(s,{['##Известный IC-номер телефона##case-phone_number']='555-0100',
    ['##Откуда персонажу известен номер##case-phone_source']='Сообщён по RP'})
click(s,'Далее · основание##case-next')
edit(s,{['##Основание и условия пеленгации##case-basis']='Отдельное OOC-основание'});click(s,'Проверить полный текст##case-preview')
check(s.caseForms:preview(s.workspace.studio.caseForm).ready);eq(#s.sent,0)
-- GUI editing, previews, help, and persistence for both RP branches and contract.
s=setup(false);click(s,'Настройки##Процедуры##case-pagesettings')
click(s,'Пеленгация##Настраиваемая процедура##case-settings-kindmark')
edit(s,{['##Пеленгация · известный IC-номер##case-rp-mark_ic_rp']='/me вводит номер {phone_number}.\n/do Идёт поиск сигнала.',
    ['##Точная команда сервера##case-command-mark']='/setmark {id}',
    ['##Где проверен синтаксис##case-source-mark']='LOCAL TEST CONTRACT'})
s.step(700);eq(s.workspace.library.procedures.mark_command,'/setmark {id}');check(not s.workspace.library.procedures.mark_verified)
local saved=s.savedLibrary()
eq(saved.procedures.mark_ic_rp,'/me вводит номер {phone_number}.\n/do Идёт поиск сигнала.')
eq(saved.procedures.mark_source,'LOCAL TEST CONTRACT');check(not saved.procedures.mark_verified)
s.hover='##settings-info-case-templates';s.render();healthy(s);s.hover=nil
for _,w in ipairs({760,1000,1600})do s.io.DisplaySize.x=w;s.io.DisplaySize.y=900;s.render();healthy(s)end
eq(#s.sent,0)
