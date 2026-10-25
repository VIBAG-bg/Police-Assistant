local fixture=require 'support.fixture'
local model=require 'pa26_bindings'
local bit=require 'bit'
local path='moonloader\\config\\police_assistant_2026_library.json'
local popup='Подтверждение##pa26-confirm'
local yes,no='ДА##confirm-yes','НЕТ##confirm-no'
local function library(s) return s.savedLibrary() end
local function fresh(s)
    s.buttonCalls={}; s.childCalls={}; s.drawnText={}; s.drawnLabels={}; s.render()
    check(not s.hasLog('Ошибка интерфейса')); eq(#s.scopes,0)
end
local function button(s,label)
    for _,b in ipairs(s.buttonCalls) do if b.label==label then return b end end
    error('button not drawn: '..label)
end
local function remove(s) s.click='Удалить##bind'; fresh(s); check(s.modalOpen) end
local function answered(s,label) s.click=label; fresh(s); check(not s.modalOpen); eq(s.popup,nil) end

-- Creation belongs to the fixed parent, and all six controls stay outside card scrolling.
local s=fixture(); s.step(); s.page('binds'); fresh(s)
eq(button(s,'+ Новый сценарий ( Добавить бинд )').parent,'content##pa26')
for _,name in ipairs({'Дублировать##bind',
    'Удалить##bind','Экспорт всех биндов','Импорт биндов'}) do
    local b=button(s,name); eq(b.parent,'bindlist##studio'); check(b.width>0 and b.height>=42)
end
for _,c in ipairs(s.childCalls) do
    if c.name=='bindlist##studio' or c.name=='content##pa26' then
        check(bit.band(c.flags,s.imgui.WindowFlags.NoScrollbar)~=0)
        check(bit.band(c.flags,s.imgui.WindowFlags.NoScrollWithMouse)~=0)
    elseif c.name=='bindrows##studio' then
        eq(c.parent,'bindlist##studio'); check(c.height>0); eq(bit.band(c.flags,s.imgui.WindowFlags.NoScrollbar),0)
    end
end
-- Measured button labels fit their reserved height, including both columns at min width.
for _,size in ipairs({{760,600},{1180,700}}) do
    s.resizeWindows={['Police Assistant 2026##pa26-main']={x=size[1],y=size[2]}}; fresh(s)
    for _,paint in ipairs(s.drawnLabels) do
        for _,name in ipairs({'Дублировать','Удалить','Экспорт всех биндов','Импорт биндов'}) do
            if paint.text==name then
                local b=button(s,name..((name=='Дублировать' or name=='Удалить') and '##bind' or ''))
                check(paint.measure.y+16<=b.height)
            end
        end
    end
end
local original=s.savedBytes(); remove(s)
local modal=s.modalCalls[#s.modalCalls]
eq(modal.parent,'Police Assistant 2026##pa26-main'); check(modal.background.a<1 and modal.background.b>modal.background.r)
check(math.abs(modal.x+modal.width/2-s.io.DisplaySize.x/2)<.1)
check(math.abs(modal.y+modal.height/2-s.io.DisplaySize.y/2)<.1)
local affirmative,negative=button(s,yes),button(s,no)
check(affirmative.color.g>affirmative.color.r); check(negative.color.r>negative.color.g)
check(affirmative.width+negative.width+10<=modal.width)
-- Clicking background navigation, creation or a key must not act through the dialog.
s.click='+ Новый сценарий ( Добавить бинд )'; fresh(s); eq(s.click,'+ Новый сценарий ( Добавить бинд )'); eq(s.savedBytes(),original)
s.page('stats'); fresh(s); check(s.modalOpen)
s.step(16,{[0x78]=true,[0x7A]=true,[0x7B]=true}); check(s.frames[1].condition()); check(s.modalOpen)
answered(s,no); eq(s.savedBytes(),original)
remove(s); s.down[0x1B]=true; onWindowMessage(0x0100,0x1B); s.step(16,{[0x1B]=true})
check(s.frames[1].condition(),'Esc should close the confirmation, keeping the editor')
check(not s.modalOpen); eq(s.savedBytes(),original); s.down[0x1B]=false; s.step()
remove(s); s.step(16,{[0x1B]=true}); check(s.frames[1].condition()); check(not s.modalOpen)
s.step()
-- Save errors leave deletion pending; retry removes exactly one stored record.
remove(s); s.libraryWriteFail=true; s.click=yes; fresh(s)
check(s.modalOpen); eq(s.savedBytes(),original); fresh(s)
check(s.workspace.studio:hasWarning());check(table.concat(s.drawnText,'\n'):find('Запись не прошла проверку',1,true))
s.click='ОК##warning-ok';fresh(s);fresh(s)
s.libraryWriteFail=false; answered(s,yes); eq(#library(s).bindings,5)
local after=s.savedBytes(); fresh(s); eq(s.savedBytes(),after,'holding the affirmative answer must not delete twice')
remove(s); answered(s,no); eq(s.savedBytes(),after,'the same popup can reopen and cancel immediately')

-- Other important actions use the same root-level modal and respect NO.
s.page('hints'); s.click='Удалить##note'; fresh(s); check(s.modalOpen); answered(s,no)
s.commands.pa26tips(); fresh(s); s.click='Удалить##note'; fresh(s)
eq(s.modalCalls[#s.modalCalls].parent,'Police Assistant · Памятки##pa26-tips')
answered(s,yes); eq(#library(s).notes,1)
s.commands.pa26(); s.page('partners')
s.edits={['Игровой ник##partner']='Test_Partner',['Позывной##partner']='P-01'}; fresh(s)
s.click='Добавить контакт'; fresh(s); eq(#library(s).partners,1)
s.click='Test_Partner · P-01##partner1'; fresh(s); s.click='Удалить контакт'; fresh(s)
check(s.modalOpen); answered(s,no); eq(#library(s).partners,1)
s.click='Удалить контакт'; fresh(s); answered(s,yes); eq(#library(s).partners,0)
onScriptTerminate(s.script)

-- Import is previewed before applying, and a failed write is retryable.
s=fixture(); s.step(); s.page('binds'); s.commands.pa26export();s.ackInfo(); fresh(s)
original=s.savedBytes(); s.commands.pa26import(); fresh(s); check(s.modalOpen)
answered(s,no); eq(s.savedBytes(),original)
s.commands.pa26import(); fresh(s); s.libraryWriteFail=true; s.click=yes; fresh(s)
check(s.modalOpen); eq(s.savedBytes(),original)
s.click='ОК##warning-ok';fresh(s);fresh(s)
s.libraryWriteFail=false; answered(s,yes); eq(#library(s).bindings,12)
for i=7,12 do check(not library(s).bindings[i].enabled); eq(library(s).bindings[i].shortcut.key,0) end
onScriptTerminate(s.script)

-- Confirmation for an actual server command owns a frozen plan; NO sends nothing.
s=fixture({demo=false}); s.step(); s.page('binds')
s.edits={['##script']='/me Проверка.\n/su {select_id} 1 Тест.'}; fresh(s)
s.click='Сохранить сценарий'; fresh(s);s.ackInfo(); s.commands.pa26select('37'); s.commands.pa26run('1')
s.step(); s.step(100); check(s.modalOpen); eq(#s.sent,0)
eq(s.modalCalls[#s.modalCalls].parent,'Police Assistant · Быстрое меню##pa26-quick')
answered(s,no); s.step(5000); eq(#s.sent,0)
s.commands.pa26run('1'); s.step(); s.step(100); check(s.modalOpen); answered(s,yes)
s.step(); s.step(100); eq(#s.sent,1); s.step(1600); eq(#s.sent,2)
eq(s.sent[2].line,'/su 37 1 Тест.'); onScriptTerminate(s.script)

-- Destructive journal operations roll back in memory as well as on disk on failure.
local journalPath='moonloader\\config\\police_assistant_2026_journal.json'
local seed={schema=1,next_id=2,counters={arrest=1},days={['2026-10-12']={arrest=1}},events={
    {id=1,name='Тест задержания',date='12.10.2026 12:00:00',day='2026-10-12',target='Player_Name [37]',
        demo=false,confirmed=true,sent=1,status='completed',reason='',stat='arrest'}}}
for _,action in ipairs({'Очистить журнал','Обнулить служебную статистику'}) do
    s=fixture({journal=seed}); s.step(); s.page('stats'); fresh(s)
    original=s.files[journalPath]; s.click=action; fresh(s); check(s.modalOpen); answered(s,no)
    eq(s.files[journalPath],original)
    s.click=action; fresh(s); s.libraryWriteFail=true; s.click=yes; fresh(s)
    check(s.modalOpen); eq(s.files[journalPath],original); fresh(s)
    check(table.concat(s.drawnText,'\n'):find('Задержания: 1',1,true),'failed reset must restore the displayed counter')
    check(table.concat(s.drawnText,'\n'):find('Тест задержания',1,true),'failed reset must restore the log')
    s.click='ОК##warning-ok';fresh(s);fresh(s)
    s.libraryWriteFail=false; answered(s,yes)
    local j=decodeJson(s.files[journalPath])
    if action=='Очистить журнал' then eq(#j.events,0); eq(j.counters.arrest,1)
    else eq(#j.events,1); eq(j.counters.arrest,nil); eq(j.days['2026-10-12'],nil) end
    onScriptTerminate(s.script)
end
-- Confirming a service result also requires YES, and retry must not count twice.
seed.events[1].confirmed=false; seed.counters={}; seed.days={}
s=fixture({journal=seed}); s.step(); s.page('stats'); original=s.files[journalPath]
s.click='Подтвердить служебный результат##event1'; fresh(s); check(s.modalOpen); answered(s,no)
eq(s.files[journalPath],original)
s.click='Подтвердить служебный результат##event1'; fresh(s); s.libraryWriteFail=true; s.click=yes; fresh(s)
check(s.modalOpen); eq(s.files[journalPath],original)
s.click='ОК##warning-ok';fresh(s);fresh(s)
s.libraryWriteFail=false; answered(s,yes); eq(decodeJson(s.files[journalPath]).counters.arrest,1)
fresh(s); eq(decodeJson(s.files[journalPath]).counters.arrest,1); onScriptTerminate(s.script)

-- An open confirmation, NO and Esc do not interrupt an already executing text sequence.
s=fixture({demo=false}); s.step(); s.page('binds')
s.edits={['##script']='Проверка первая.\n@wait(3000)\nПроверка вторая.\n@wait(3000)\nПроверка третья.'}; fresh(s)
s.click='Сохранить сценарий'; fresh(s);s.ackInfo(); s.commands.pa26run('1'); s.step(); s.step(100); eq(#s.sent,1)
s.step(); s.commands.pa26(); s.page('binds'); remove(s); answered(s,no)
s.step(3100); s.step(); eq(#s.sent,2)
s.step(); remove(s); s.down[0x1B]=true; onWindowMessage(0x0100,0x1B); s.step(16,{[0x1B]=true})
check(s.frames[1].condition()); check(not s.modalOpen); s.down[0x1B]=false
s.step(3100); s.step(); eq(#s.sent,3); eq(s.sent[3].line,'Проверка третья.')
onScriptTerminate(s.script)

-- If a target leaves while a server-command confirmation is open, the stale dialog disappears.
s=fixture({demo=false}); s.step(); s.commands.pa26select('37'); s.commands.pa26run('5')
s.step(); s.step(100); check(s.modalOpen); eq(#s.sent,0)
s.events.onPlayerQuit(37,1); s.click=yes; s.step(300)
check(not s.modalOpen); s.step(3000); eq(#s.sent,0)
onScriptTerminate(s.script)
