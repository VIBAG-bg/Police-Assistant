local support=require 'support.fixture'
local function fixture(options)options=options or{};options.legacyWanted=true;return support(options)end
local model=require 'pa26_bindings'
local path='moonloader\\config\\police_assistant_2026_library.json'
local function lib(s) return s.savedLibrary() end
local function fresh(s)
    s.drawnText={}; s.buttonCalls={}; s.multilineCalls={}; s.render()
    check(not s.hasLog('Ошибка интерфейса')); eq(#s.scopes,0)
end
local function text(s,value) return table.concat(s.drawnText,'\n'):find(value,1,true)~=nil end
local function script(s)
    for _,field in ipairs(s.multilineCalls) do if field.label=='##script' then return field.text end end
end
local function button(s,label)
    for _,value in ipairs(s.buttonCalls) do if value.label==label then return value end end
end
local function new(s)
    s.page('binds'); s.click='+ Новый сценарий ( Добавить бинд )'; fresh(s)
    s.edits={['Название##bind']='Новый несохранённый',['##script']='Первый текст.\nВторая строка.'}; fresh(s)
end
local function destination(s,id,name)
    s.click=string.format('%03d',model.bindingNumber(lib(s),id))..'  '..name..'##bind'..id; fresh(s)
    check(s.modalOpen); check(text(s,'Сохранить изменения бинда?'))
end

local s=fixture(); s.step(); new(s); local before=s.savedBytes()
destination(s,1,'Представиться')
local save,discard,stay=button(s,'Сохранить##changes-save'),button(s,'Отбросить##changes-discard'),button(s,'Остаться##changes-stay')
check(save and discard and stay); check(save.color.g>save.color.r); check(discard.color.r>discard.color.g)
eq(save.window,'Подтверждение##pa26-confirm'); eq(s.modalCalls[#s.modalCalls].parent,'Police Assistant 2026##pa26-main')
s.page('settings'); fresh(s); check(s.modalOpen); eq(s.savedBytes(),before)
s.click='Остаться##changes-stay'; fresh(s); check(not s.modalOpen); fresh(s)
eq(script(s),'Первый текст.\nВторая строка.'); eq(s.savedBytes(),before)
destination(s,1,'Представиться'); s.libraryWriteFail=true; s.click='Сохранить##changes-save'; fresh(s)
check(s.modalOpen); eq(s.savedBytes(),before); fresh(s);check(s.workspace.studio:hasWarning());check(text(s,'Предупреждение'))
s.click='ОК##warning-ok';fresh(s);fresh(s);check(not s.workspace.studio:hasWarning())
s.libraryWriteFail=false; s.click='Сохранить##changes-save'; fresh(s); check(not s.modalOpen); fresh(s)
eq(#lib(s).bindings,7); eq(lib(s).bindings[7].name,'Новый несохранённый')
eq(lib(s).bindings[7].script,'Первый текст.\nВторая строка.'); eq(script(s),lib(s).bindings[1].script)
local stored=lib(s).bindings[1].script
s.edits={['##script']='Изменение, которое отбросим.'}; fresh(s)
destination(s,2,'Документы'); s.click='Отбросить##changes-discard'; fresh(s); check(not s.modalOpen); fresh(s)
eq(lib(s).bindings[1].script,stored); eq(script(s),lib(s).bindings[2].script)
s.edits={['##script']='Черновик остаётся после Esc.'}; fresh(s); destination(s,1,'Представиться')
s.down[0x1B]=true; onWindowMessage(0x0100,0x1B); s.step(16,{[0x1B]=true})
check(not s.modalOpen); check(s.frames[1].condition()); fresh(s); eq(script(s),'Черновик остаётся после Esc.')
s.down[0x1B]=false; s.step(); s.commands.pa26(); s.step(); s.commands.pa26(); s.step(); fresh(s)
eq(script(s),'Черновик остаётся после Esc.'); onScriptTerminate(s.script)

-- Each row owns its movement, including while another draft is unsaved.
s=fixture(); s.step(); s.page('binds'); fresh(s)
check(not button(s,'##bind-info1')); check(not button(s,'Выше##binding-order')); check(not button(s,'Ниже##binding-order'))
local up,down,title=button(s,'##bind-up3'),button(s,'##bind-down3'),button(s,'003  Розыск##bind3')
check(up and down and title); eq(up.width,34); eq(up.height,20); eq(down.height,20)
eq(up.x,down.x); check(up.y+up.height<=down.y); check(down.y+down.height<=title.y+title.height)
local old=lib(s); s.edits={['##script']='Несохранённый текст первого.'}; fresh(s)
s.click='##bind-down3'; fresh(s); fresh(s)
local moved=lib(s); eq(model.bindingNumber(moved,3),4); eq(script(s),'Несохранённый текст первого.')
eq(moved.bindings[1].script,old.bindings[1].script); check(not s.modalOpen)
for i,id in ipairs(old.wheel) do eq(moved.wheel[i],id) end
eq(moved.next_id,old.next_id)
before=s.savedBytes(); s.click='##bind-up1'; fresh(s); eq(s.savedBytes(),before)
s.click='##bind-down6'; fresh(s); eq(s.savedBytes(),before)
s.libraryWriteFail=true; s.click='##bind-up3'; fresh(s); eq(s.savedBytes(),before)
s.click='ОК##warning-ok';fresh(s)
s.libraryWriteFail=false; s.edits={['Поиск##library']='Досмотр'}; fresh(s)
s.click='##bind-up4'; fresh(s); fresh(s); eq(model.bindingNumber(lib(s),4),2)
check(button(s,'002  Досмотр##bind4')); eq(script(s),'Несохранённый текст первого.')
for _,display in ipairs({{640,480},{1280,720},{2560,1440}}) do
    s.io.DisplaySize.x,s.io.DisplaySize.y=display[1],display[2]; fresh(s)
    check(button(s,'##bind-up4')); check(button(s,'##bind-down4')); eq(#s.scopes,0)
end
onScriptTerminate(s.script)

-- Quick-menu information is still available and describes the requested bind.
s=fixture(); s.step(); s.commands.pa26quick(); fresh(s)
s.click='##quick-info2'; fresh(s); check(text(s,'Документы')); check(text(s,'Команда: /pa26run 2'))
s.popup=nil; s.click='##quick-info5'; fresh(s); check(text(s,'Наручники')); check(text(s,'Команда: /pa26run 5'))
eq(#s.sent,0); onScriptTerminate(s.script)
