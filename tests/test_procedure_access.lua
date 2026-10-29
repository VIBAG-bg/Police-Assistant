local core=require 'pa26_core'
local model=require 'pa26_bindings'
local wheel=require 'pa26_wheel'
local fixture=require 'support.fixture'
local cfg=core.defaults();local lib=model.defaults(cfg);eq(#wheel.procedureItems(lib),2,'Wanted helper and global list are independent of unverified fine/mark forms')
lib.procedures.enabled=true;eq(#wheel.procedureItems(lib),4)
for _,profile in ipairs({'compact','extended','full'})do
    lib.settings.wheel_profile=profile
    local cat=wheel.build(lib,5,true)
    for _,kind in ipairs({'wanted','wanted_list','fine','mark'})do
        local id='procedure-'..kind;local item=cat.bySystem[id];check(item);eq(item.category,'wanted')
        check(wheel.available(cat,{kind='procedure',id=id,category='wanted'},false,nil),'Opening a form is available without sending or guessing a target')
        check(not wheel.available(cat,{kind='procedure',id=id,category='service'},false,nil))
        check(not wheel.available(cat,{kind='alert',id=id,category='wanted'},false,nil))
    end
end
lib.procedures.wanted_wheel=false;lib.procedures.wanted_label='Личное название'
check(not wheel.build(lib,6,true).bySystem['procedure-wanted']);eq(wheel.procedureItems(lib)[1].name,'Личное название')
lib.procedures.wanted_enabled=false;eq(#wheel.procedureItems(lib),2)
local bad=model.copy(lib);bad.procedures.mark_label='';check(not model.validate(bad,cfg))
bad=model.copy(lib);bad.procedures.mark_quick='yes';check(not model.validate(bad,cfg))
bad=model.copy(lib);bad.procedures.wanted_shortcut={key=0x59,ctrl=false,alt=false,shift=false};check(not model.validate(bad,cfg))
local function healthy(s)
    check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(s.invalidIOReads,0);eq(#s.sent,0)
end
local function click(s,label)s.click=label;s.render();eq(s.click,nil,'Missing control: '..label);healthy(s)end
local function setup(classic,withoutTarget,capture)
    local seed=model.defaults(cfg);seed.procedures.enabled=true;seed.settings.window_layout.fine_separate=false;seed.settings.window_layout.mark_separate=false
    local s=fixture({demo=false,library=seed,categoryWheel=not classic,consumeKeyboard=capture==true});s.step()
    if not withoutTarget then check(s.workspace:selectTarget({id=s.id,ped=s.mappedPed,name=s.name}));s.step()
    else s.aimed=false;s.streamed=false;s.pool={1}end
    if s.frames[1].condition()then s.commands.pa26();s.step()end
    return s
end
local function route(s,kind)
    s.down={[0x58]=true};s.step(16,{[0x58]=true});s.step(150);check(s.runtime.wheel)
    s.runtime:setBindingChoice({kind='procedure',id='procedure-'..kind,category='wanted'},s.now)
    s.down={};s.step();healthy(s)
end
local s=setup();route(s,'wanted');local st=s.workspace.studio
check(st.caseForm);eq(st.caseForm.kind,'wanted');eq(st.caseForm.target.id,37);check(not s.workspace.executor.queue)
click(s,'Нет##Вы видели паспорт этого человека?##wanted-passport_seenno')
click(s,'Нет##На подозреваемом полная RP-маска (/mask + аксессуар на лице)?##wanted-maskno')
s.toggle='Основание получено в текущей игровой жизни · не использую сведения до смерти / RK##wanted-life-ack';s.render()
click(s,'Далее · причина розыска##wanted-next');s.render();click(s,'С приметами##wanted-appearance-second');s.render()
s.edits={['##Приметы##wanted-appearance-modal']='Сохраняемые приметы'};s.render();s.edits={}
click(s,'Далее · к выбору статьи##wanted-appearance-first')
local wanted=st.caseForm
-- A second form has its own fields; switching and closing menus keeps the first.
s.commands.pa26quick();s.step();click(s,'Штраф##quick-system-procedure-fine')
check(st.caseForm);eq(st.caseForm.kind,'fine');check(st.caseForm~=wanted)
local fine=st.caseForm
click(s,'Розыск##Действие##case-kindwanted');eq(st.caseForm,wanted);eq(wanted.appearance,'Сохраняемые приметы')
click(s,'Штраф##Действие##case-kindfine');eq(st.caseForm,fine)
s.commands.pa26quick();s.step();click(s,'Розыск##quick-system-procedure-wanted');eq(st.caseForm,wanted)
-- Label and independent visibility switches persist through GUI auto-save.
click(s,'Розыск · настройки##Процедуры##case-pagewanted_settings')
s.edits={['##Название действия в меню##case-label-wanted']='Мой розыск'};s.render();s.edits={}
s.toggle='В радиальном меню##case-access-wanted_wheel';s.render();s.step(700)
eq(s.workspace.library.procedures.wanted_label,'Мой розыск');check(not s.workspace.library.procedures.wanted_wheel)
check(not s.runtime.env.wheelCatalog().bySystem['procedure-wanted'])
local saved=s.savedLibrary()
eq(saved.procedures.wanted_label,'Мой розыск');check(not saved.procedures.wanted_wheel);check(saved.procedures.wanted_quick)
s.commands.pa26quick();s.step();click(s,'Мой розыск##quick-system-procedure-wanted');eq(st.caseForm,wanted)
-- Overflow from the wheel keeps actions even if their normal F11 flag is off.
s.workspace.library.procedures.mark_quick=false
s.commands.pa26quick();s.workspace.studio.quickWheelCategory='wanted';s.render()
click(s,'Пеленгация##quick-system-procedure-mark');eq(st.caseForm.kind,'mark');healthy(s)
-- Classic-wheel users still get the forms in the independent quick menu.
s=setup(true);s.commands.pa26quick();s.step();click(s,'Розыск##quick-system-procedure-wanted');check(s.workspace.studio.caseForm);healthy(s)
-- No selected player: opening an empty form never manufactures a target.
s=setup(false,true,true);route(s,'wanted');eq(s.workspace.studio.caseForm,nil);healthy(s)
click(s,'ОК##warning-ok');s.render()
-- Feature key uses the same capture dialog, immediate persistence and form path.
click(s,'Розыск · настройки##Процедуры##case-pagewanted_settings');click(s,'Назначить клавишу##case-key-wanted')
check(s.workspace.studio.keyCapture);eq(s.workspace.studio.keyCapture.request.group,'procedures')
s.step();s.keyMessage(0x11,true);s.step();s.keyMessage(0x55,true);s.step()
s.keyMessage(0x55,true,0x0101);s.step();s.keyMessage(0x11,true,0x0101);s.step()
click(s,'Назначить##capture-apply');check(not s.workspace.studio.keyCapture,'Key assignment did not close the capture dialog')
saved=s.savedLibrary()
eq(saved.procedures.wanted_shortcut.key,0x55);check(saved.procedures.wanted_shortcut.ctrl)
s.step(700);eq(s.workspace.library.procedures.wanted_shortcut.key,0x55,'A pending auto-save must not restore the old key')
s=fixture({demo=false,library=saved,categoryWheel=true});s.step()
check(s.workspace:selectTarget({id=s.id,ped=s.mappedPed,name=s.name}));s.step()
if s.frames[1].condition()then s.commands.pa26();s.step()end
s.physicalDown={};s.step();s.physicalDown={[0x11]=true};s.step();s.physicalDown[0x55]=true;s.step()
check(s.workspace.studio.caseForm);eq(s.workspace.studio.caseForm.kind,'wanted');healthy(s)
