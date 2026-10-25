local fixture=require 'support.fixture';local model=require 'pa26_bindings';local core=require 'pa26_core'
local function healthy(s)check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(s.invalidIOReads,0)end
local function click(s,label)s.click=label;s.render();eq(s.click,nil,'Missing control: '..label);healthy(s)end
local function edit(s,values)s.edits=values;s.render();s.edits={};healthy(s)end
local function setup(demo)
    local lib=model.defaults(core.defaults());lib.procedures.wanted_command='/su {id} {amount} {basis}'
    lib.procedures.enabled=true;lib.procedures.fine_command='/mockfine {id} {amount} {basis}';lib.procedures.fine_verified=true;lib.procedures.fine_source='LOCAL MOCK'
    local s=fixture({demo=demo==true,library=lib,alerts=true,notifications=true});s.step();check(s.workspace:selectTarget({id=s.id,ped=s.mappedPed,name=s.name}));s.step()
    s.page('addons');click(s,'Процедуры##toolprocedures');return s
end
local function appearance(s)
    click(s,'Новая форма##case-new');s.toggle='Основание из текущей ситуации после последней смерти##wanted-life-ack';s.render()
    click(s,'Нет##На саспекте маска?##wanted-maskno')
    click(s,'Нет##Вы видели паспорт этого человека?##wanted-passport_seenno')
    click(s,'Далее · причина розыска##wanted-next')
    s.render();click(s,'С приметами##wanted-appearance-second');s.render()
    edit(s,{['##Приметы##wanted-appearance-modal']='синяя куртка'})
    click(s,'Далее##wanted-appearance-first')
    click(s,'01.01 · Нападение на гражданина · 1 ур.##wanted-reason-01.01')
    click(s,'Проверить отыгровку и команду##wanted-preview')
end
local function prepare(s)
    click(s,'Отправить отыгровку · затем ДА/НЕТ##wanted-prepare')
    for _=1,12 do s.step(1600);if s.workspace.studio.caseConfirm then break end end
    check(s.workspace.studio.caseConfirm,'A final confirmation must appear after RP');healthy(s)
    for _,r in ipairs(s.sent)do check(r.line:match('^/me ')or r.line:match('^/do ')or r.line:match('^/todo '),'Only RP before final YES')end
end
local s=setup();appearance(s);eq(#s.sent,0);prepare(s);local count=#s.sent;check(count>0)
click(s,'НЕТ##confirm-no');s.step();s.step(2000);eq(#s.sent,count);check(not s.caseForms:view().pending)
s=setup();appearance(s);prepare(s);count=#s.sent;click(s,'ДА##confirm-yes');eq(#s.sent,count,'No send from rendering')
s.step();s.step();eq(#s.sent,count+1);eq(s.sent[#s.sent].line,'/su 37 1 1');s.step(3000);eq(#s.sent,count+1)
check(not s.caseForms:offer(s.workspace.studio.caseForm),'No replay of consumed form')
s=setup();appearance(s);prepare(s);count=#s.sent;s.events.onPlayerQuit(s.id,1);s.step();click(s,'ДА##confirm-yes');s.step(2000);eq(#s.sent,count)
s=setup();appearance(s);click(s,'Отправить отыгровку · затем ДА/НЕТ##wanted-prepare');s.step();count=#s.sent
s.step(16,{[0x23]=true});s.step(4000);eq(#s.sent,count);check(not s.caseForms:view().pending)
-- Editable settings preserve personal legacy fields, with autosave and preview.
s=setup();click(s,'Розыск · настройки##Процедуры##case-pagewanted_settings')
edit(s,{['##Розыск · известные приметы##wanted-rp-wanted_appearance_rp']='/me передал приметы: {appearance}.'})
s.intEdits={['##wanted-time-delay_ms']=2100};s.render();s.intEdits={};s.step(700)
eq(s.workspace.library.procedures.delay_ms,2100);eq(s.workspace.library.procedures.wanted_appearance_rp,'/me передал приметы: {appearance}.')
local saved=s.savedLibrary()
eq(saved.procedures.wanted_command,'/su {id} {amount} {basis}');eq(saved.procedures.wanted_direct_command,'/su {id} {game_category} {game_item}')
for _,w in ipairs({760,1000,1600})do s.io.DisplaySize.x=w;s.io.DisplaySize.y=900;s.render();healthy(s)end;eq(#s.sent,0)
-- Registered native and CEF commands open the same wizard without server sends.
for _,backend in ipairs({'native','cef','dot'})do
    s=setup();if s.frames[1].condition()then s.commands.pa26();s.step()end
    if backend=='native'then s.commands.su('37 1 2')
    elseif backend=='cef'then
        local bridge=s.chatBridge;local event={id=1,kind='local',text='/su 37 1 2',session=bridge.env.session()}
        local request=encodeJson({schema=1,page='wanted-cef-test',chat=false,dialog=false,busy=false,events={event}})
        check(bridge:exchange(request,s.now));s.step();check(bridge:exchange(request,s.now))
    else
        s.chat=true;s.chatText=codec.encode('.ыг 37 1 2');s.step();onWindowMessage(0x0100,0x0D)
        eq(s.events.onSendChat(codec.encode('.ыг 37 1 2')),false);s.chat=false
    end
    for _=1,3 do s.step()end
    check(s.workspace.studio.caseForm);eq(s.workspace.studio.caseForm.reason_id,'01.02',backend);eq(s.workspace.studio.caseForm.stage,'identity');eq(#s.sent,0)
    onScriptTerminate(s.script)
end
s=setup();if s.frames[1].condition()then s.commands.pa26();s.step()end
s.commands.wanted('');for _=1,3 do s.step()end;eq(s.workspace.studio.caseForm.kind,'wanted_list');eq(s.workspace.studio.caseForm.target,nil);eq(#s.sent,0)
-- Fine still uses its independent validated contract and one confirmation.
s=setup();click(s,'Штраф##Действие##case-kindfine');click(s,'Новая форма##case-new')
click(s,'Да##Вы видели паспорт этого человека?##case-passport_seenyes');edit(s,{['##IC-имя и фамилия из документа##case-ic_name']='John Smith'})
click(s,'Нет##На человеке маска?##case-maskno');click(s,'Далее · основание##case-next')
edit(s,{['##Точное основание для команды##case-basis']='ПМ 4.1',['##Сумма штрафа · вручную##case-amount']='1000'})
click(s,'Проверить полный текст##case-preview');click(s,'Подтвердить выполнение##case-send');click(s,'ДА##confirm-yes')
for _=1,5 do s.step(1600)end;eq(s.sent[#s.sent].line,'/mockfine 37 1000 ПМ 4.1');healthy(s)
