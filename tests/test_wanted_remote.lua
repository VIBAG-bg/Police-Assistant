local fixture=require 'support.fixture';local model=require 'pa26_bindings';local core=require 'pa26_core'
local function inline()local seed=model.defaults(core.defaults());seed.settings.window_layout.wanted_separate=false;return seed end
local function healthy(s)check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(s.invalidIOReads,0)end
local function click(s,label)s.click=label;s.render();eq(s.click,nil,'Missing: '..label);healthy(s)end
local function setup(vehicle)
    local s=fixture({demo=false,library=inline(),alerts=true,categoryWheel=true})
    s.streamed=false;s.aimed=false;s.onScreen=false;s.distance=5000;s.pool={1};s.vehicle=vehicle==true
    s.step();if s.frames[1].condition()then s.commands.pa26();s.step()end
    s.commands.su('37');for _=1,3 do s.step()end
    local f=s.workspace.studio.caseForm;check(f,'Remote /su did not create a form');check(f.target.account);eq(f.target.id,37)
    eq(s.workspace.selectedTarget,nil,'Remote wanted must not manufacture a physical interaction')
    eq(#s.sent,0);return s,f
end
-- Actual native/CEF passport messages, before any physical selection, then travel.
for _,backend in ipairs({'native','cef'})do
    local s=fixture({demo=false,library=inline(),alerts=true,categoryWheel=true})
    s.id=5;s.name='Local_Officer';s.aimed=false
    s.actors={[99]={id=37,name='John_Smith',x=0,y=3,z=0,sx=600,sy=350}}
    s.step();local line='[ME] John_Smith достал паспорт и показал его Local_Officer'
    if backend=='native'then s.events.onServerMessage(-1,codec.encode(line))
    else check(s.chatBridge:exchange(encodeJson({schema=1,page='remote-passport',chat=false,dialog=false,busy=false,
        events={{id=1,kind='message',text=line,session=s.chatBridge.env.session()}}}),s.now))end
    s.step();s.actors[99].streamed=false;s.actors[99].onScreen=false;s.actors[99].y=5000;s.pool={1};s.step()
    if s.frames[1].condition()then s.commands.pa26();s.step()end
    s.commands.su('37');for _=1,3 do s.step()end
    local f=s.workspace.studio.caseForm;check(f);eq(f.passport_seen,'yes',backend)
    eq(f.ic_name,'John Smith');eq(f.passport_number,'37');eq(f.passport_source,'server');eq(s.workspace.selectedTarget,nil)
    eq(#s.sent,0);healthy(s);onScriptTerminate(s.script)
end
-- New behaviour/template controls persist through the actual GUI and split files.
local s,f=setup();click(s,'Розыск · настройки##Процедуры##case-pagewanted_settings')
s.toggle='Каждую примету через запятую отыгрывать отдельной /todo##wanted-config-wanted_each_trait';s.render()
s.edits={['##Розыск · /todo с введёнными приметами##wanted-rp-wanted_traits_rp']='/todo Приметы: {appearance}*докладывая диспетчеру.'};s.render();s.edits={};s.step(700)
local saved=s.savedLibrary();check(saved.procedures.wanted_each_trait)
eq(saved.procedures.wanted_traits_rp,'/todo Приметы: {appearance}*докладывая диспетчеру.')
check(saved.procedures.wanted_allow_remote);check(saved.procedures.wanted_autofill_passport);eq(#s.sent,0);onScriptTerminate(s.script)
local function identity(s,passport)
    s.toggle='Основание из текущей ситуации после последней смерти##wanted-life-ack';s.render()
    click(s,'Нет##На саспекте маска?##wanted-maskno')
    click(s,(passport and 'Да'or 'Нет')..'##Вы видели паспорт этого человека?##wanted-passport_seen'..(passport and 'yes'or 'no'))
    click(s,'Далее · причина розыска##wanted-next')
end
local function reason(s)
    s.combo='##Раздел преступления##wanted-group'
    click(s,'08 · Неподчинение##Раздел преступления##wanted-group08')
    s.combo=nil
    click(s,'08.01 · Неподчинение сотруднику ПД/ФБР · 2 ур.##wanted-reason-08.01')
    click(s,'Проверить отыгровку и команду##wanted-preview')
end
local function prepare(s)
    click(s,'Отправить отыгровку · затем ДА/НЕТ##wanted-prepare')
    for _=1,28 do s.step(1600);if s.workspace.studio.caseConfirm then break end end
    check(s.workspace.studio.caseConfirm,'RP did not reach the final separate confirmation')
    for _,r in ipairs(s.sent)do check(not r.line:match('^/su '));check(#codec.encode(r.line)<=127)end
end
-- Passport confirmation fills the nick-based IC name and ID-based document number,
-- without manual fields and without requiring a selected or streamed player.
for _,vehicle in ipairs({false,true})do
    local s,f=setup(vehicle);identity(s,true);eq(f.ic_name,'Player Name');eq(f.passport_number,'37');eq(f.stage,'basis')
    reason(s);local p=assert(s.caseForms:preview(f));check(table.concat(p.lines,'\n'):find('Player Name',1,true))
    check(table.concat(p.lines,'\n'):find('номер паспорта: 37',1,true))
    check(p.lines[1]:find(vehicle and 'бортовому компьютеру'or 'КПК',1,true))
    prepare(s);local count=#s.sent;click(s,'ДА##confirm-yes');eq(#s.sent,count)
    s.step();s.step(1600);eq(s.sent[#s.sent].line,'/su 37 8 1');eq(#s.sent,count+1)
    onScriptTerminate(s.script)
end
-- Separate windows: general and detailed. Short comma-separated traits stay in a single /todo report by default.
for _,detailed in ipairs({false,true})do
    local s,f=setup();identity(s,false);s.render();eq(f.stage,'appearance_choice');check(s.workspace.studio.wantedAppearance)
    click(s,(detailed and 'С приметами##wanted-appearance-second'or 'Общая##wanted-appearance-first'))
    if detailed then
        s.render();eq(f.stage,'appearance_input');check(s.workspace.studio.wantedAppearance)
        s.edits={['##Приметы##wanted-appearance-modal']='высокий, на вид 25 лет'};s.render();s.edits={}
        click(s,'Далее##wanted-appearance-first')
    end
    eq(f.stage,'basis');reason(s)
    local p=assert(s.caseForms:preview(f));local todos=0
    for _,line in ipairs(p.lines)do if line:match('^/todo ')then
        todos=todos+1;check(line:find('*обращаясь по рации к диспетчеру.',1,true));check(#codec.encode(line)<=127)
    end end
    eq(todos,detailed and 1 or 0);check(not table.concat(p.lines):find('Player Name',1,true),'No passport name in appearance RP')
    prepare(s);local count=#s.sent;click(s,'НЕТ##confirm-no');s.step(3000);eq(#s.sent,count);onScriptTerminate(s.script)
end
-- Missing identity offers OOC from the answers and requires an explicit decision.
local s,f=setup();s.toggle='Основание из текущей ситуации после последней смерти##wanted-life-ack';s.render()
click(s,'Да##На саспекте маска?##wanted-maskyes');click(s,'Нет##Вы видели паспорт этого человека?##wanted-passport_seenno')
check(s.caseForms:oocSuggested(f));eq(f.mode,'ic');click(s,'Перейти к OOC-звёздам##wanted-use-ooc');eq(f.mode,'ooc');check(not f.ooc_ack)
eq(#s.sent,0);check(not s.caseForms:next(f),'OOC still needs explicit mechanism acknowledgement');onScriptTerminate(s.script)
-- Disconnect and ID reuse between RP and final YES never send /su.
for _,change in ipairs({'disconnect','rename','rejoin'})do
    s,f=setup();identity(s,true);reason(s);prepare(s);local count=#s.sent
    if change=='disconnect'then s.targetConnected=false
    elseif change=='rename'then s.name='Other_Player'
    else s.events.onPlayerQuit(37,1);s.events.onPlayerJoin(37,-1,false,'Player_Name')end
    s.step();if s.workspace.studio.caseConfirm then click(s,'ДА##confirm-yes')end
    s.step(3000);eq(#s.sent,count,change);onScriptTerminate(s.script)
end
