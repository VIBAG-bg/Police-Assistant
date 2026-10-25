local fixture=require 'support.fixture';local model=require 'pa26_bindings';local core=require 'pa26_core'
local function click(s,label)s.click=label;s.render();eq(s.click,nil,'Missing dedicated wanted control: '..label);check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0)end
local function setup(demo)
    local s=fixture({productionWindows=true,demo=demo==true,library=model.defaults(core.defaults()),alerts=true,categoryWheel=true})
    s.streamed=false;s.aimed=false;s.onScreen=false;s.distance=5000;s.pool={1};s.step()
    if s.frames[1].condition()then s.commands.pa26();s.step()end
    s.commands.su('37');for _=1,3 do s.step()end
    check(not s.frames[1].condition(),'The main PA window must stay closed')
    check(s.windows['Police Assistant · Розыск##pa26-wanted']);check(s.frames[4].condition())
    eq(#s.sent,0);return s,s.workspace.studio.caseForm
end
for _,demo in ipairs({false,true})do
    local s,f=setup(demo)
    s.toggle='Основание из текущей ситуации после последней смерти##wanted-life-ack';s.render()
    click(s,'Нет##На саспекте маска?##wanted-maskno')
    click(s,'Да##Вы видели паспорт этого человека?##wanted-passport_seenyes')
    click(s,'Далее · причина розыска##wanted-next');eq(f.stage,'basis');eq(f.ic_name,'Player Name');eq(f.passport_number,'37')
    s.edits={['##Поиск · можно оставить пустым##wanted-search']='неподчинение'};s.render();s.edits={}
    click(s,'08.01 · Неподчинение сотруднику ПД/ФБР · 2 ур.##wanted-reason-08.01')
    click(s,'Подробности основания и факты##wanted-basis-details');s.render()
    click(s,'Назад · выбор причины##wanted-basis-details-back')
    click(s,'Проверить отыгровку и команду##wanted-preview');eq(f.stage,'preview')
    click(s,'Следующая##wanted-preview-page-next');check(s.workspace.studio.wantedPreviewPage>1)
    click(s,'Отправить отыгровку · затем ДА/НЕТ##wanted-prepare')
    for _=1,32 do s.step(1600);if s.workspace.studio.caseConfirm then break end end
    check(s.workspace.studio.caseConfirm);for _,row in ipairs(s.sent)do check(not row.line:match('^/su '))end
    click(s,'ДА##confirm-yes');s.step();s.step(1800)
    if demo then eq(#s.sent,0)else eq(s.sent[#s.sent].line,'/su 37 8 1')end
    check(not s.frames[1].condition());onScriptTerminate(s.script)
end
local s,f=setup(false)
s.events.onPlayerQuit(37,1);s.targetConnected=false;s.step();s.render();eq(#s.sent,0)
check(not s.hasLog('Ошибка интерфейса'));onScriptTerminate(s.script)
