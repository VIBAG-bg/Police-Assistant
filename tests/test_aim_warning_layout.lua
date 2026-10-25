local model=require 'pa26_bindings';local prefs=require 'pa26_preferences';local core=require 'pa26_core'
local module=require 'pa26_weapon_warning';local menu=require 'pa26_menu';local fixture=require 'support.fixture'
-- Migrate only the old moment of the reminder; retain phrases, delays, keys and explicit new choices.
local old=prefs.weaponWarningDefaults();old.trigger_revision=nil;old.trigger='stable';old.taser_template='Стойте! Будет применён тайзер.'
local migrated=assert(prefs.validateWeaponWarning(old));eq(migrated.trigger,'aim');eq(migrated.taser_template,old.taser_template)
old.trigger='draw';eq(assert(prefs.validateWeaponWarning(old)).trigger,'draw')
old.trigger='stable';old.trigger_revision=1;eq(assert(prefs.validateWeaponWarning(old)).trigger,'stable')
old.trigger='other';check(not prefs.validateWeaponWarning(old));old.trigger='aim';old.trigger_revision=2;check(not prefs.validateWeaponWarning(old))
local function setup(extra)
    local seed=model.defaults(core.defaults());seed.weapon_warning.mode='confirm'
    local opts={demo=false,alerts=true,notifications=true,categoryWheel=true,library=seed}
    for k,v in pairs(extra or{})do opts[k]=v end
    local s=fixture(opts);s.step();if s.frames[1].condition()then s.commands.pa26();s.step()end
    s.aimed=false;s.weapon=23;s.aimControl=true;s.step();return s
end
local function healthy(s)
    check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0);eq(s.invalidIOReads,0);eq(s.lockRequests,0)
end
local function aim(s,ms,mode)
    s.events.onSendAimSync({camMode=mode or 53});s.step(0)
    while ms>0 do s.events.onSendAimSync({camMode=mode or 53});local dt=math.min(100,ms);s.step(dt);ms=ms-dt end
    healthy(s)
end
local function yes(s)
    s.physicalDown={};s.step(150);s.physicalDown={[0x59]=true};s.step();s.physicalDown={};s.step(100);s.step(100)
end
-- No target selected or nearby is needed. 4.9 s is insufficient; the prompt never speaks by itself.
local s=setup();aim(s,4900);eq(s.weaponWarning.pending,nil);aim(s,100);check(s.weaponWarning.pending);eq(#s.sent,0)
local token=s.weaponWarning.pending.token;s.aimControl=false;s.step();check(s.weaponWarning.pending,'release aim to click/confirm the toast')
yes(s);eq(#s.sent,1);check(s.sent[1].line:match('^/s '));onScriptTerminate(s.script)
-- One prompt per hold, even when the cooldown elapses, N is chosen or the toast times out.
s=setup();aim(s,5000);token=s.weaponWarning.pending.token;check(s.weaponWarning:decide(token,false));aim(s,45000);eq(s.weaponWarning.pending,nil);eq(#s.sent,0)
s.aimControl=false;s.step();s.aimControl=true;aim(s,5000);check(s.weaponWarning.pending);onScriptTerminate(s.script)
s=setup();aim(s,16000);eq(s.weaponWarning.pending,nil);aim(s,40000);eq(s.weaponWarning.pending,nil);eq(#s.sent,0);onScriptTerminate(s.script)
-- Release, changed weapon, UI, death, vehicle, pause/focus loss and long scheduling gaps reset the 5 s.
for _,kind in ipairs({'release','weapon','menu','chat','pause','focus','death','vehicle','gap'})do
    s=setup();aim(s,4000)
    if kind=='release'then s.aimControl=false
    elseif kind=='weapon'then s.weapon=31
    elseif kind=='menu'then s.commands.pa26()
    elseif kind=='chat'then s.chat=true
    elseif kind=='pause'then s.paused=true
    elseif kind=='focus'then onWindowMessage(0x0008,0)
    elseif kind=='death'then s.localDead=true
    elseif kind=='vehicle'then s.vehicle=true end
    s.step(kind=='gap'and 2000 or 100);eq(s.weaponWarning.pending,nil,kind)
    if kind=='menu'and s.frames[1].condition()then s.commands.pa26()end
    s.aimControl=true;s.weapon=23;s.chat=false;s.paused=false;s.localDead=false;s.vehicle=false
    if kind=='focus'then onWindowMessage(0x0007,0)end
    aim(s,4000);eq(s.weaponWarning.pending,nil,kind..' starts a new hold');aim(s,1200);check(s.weaponWarning.pending,kind)
    eq(#s.sent,0);onScriptTerminate(s.script)
end
-- A fresh normal camera must win over a selected/aimed actor. Stale camera data cannot sustain aiming.
s=setup();s.aimed=true;aim(s,6000,4);eq(s.weaponWarning.pending,nil);s.aimed=false
aim(s,4000);s.step(1700);eq(s.weaponWarning.pending,nil);aim(s,4000);eq(s.weaponWarning.pending,nil);onScriptTerminate(s.script)
-- Without usable camera/control data the fallback requires an actual live mapped player under aim.
s=setup({aimControlApi=false});s.aimed=false;aim(s,6000);eq(s.weaponWarning.pending,nil,'no aim control and no player')
s.aimed=true;aim(s,6000);check(s.weaponWarning.pending);eq(#s.sent,0);onScriptTerminate(s.script)
s=setup();s.aimControl=false;s.aimed=true;for i=1,6 do s.step(1000)end;eq(s.weaponWarning.pending,nil,'target without mapped aim control is insufficient')
s.aimControl=true;for i=1,6 do s.step(1000)end;check(s.weaponWarning.pending,'target API fallback');onScriptTerminate(s.script)
-- Cooperative event ownership: retain previous return values; never rewrite/send/force sync.
local previous=function(data)return {{camMode=4}}end
s=setup({aimHandler=previous});local out=s.events.onSendAimSync({camMode=53});eq(out[1].camMode,4);aim(s,6000);eq(s.weaponWarning.pending,nil)
onScriptTerminate(s.script);eq(s.events.onSendAimSync,previous)
s=setup({aimHandler=function()return false end});eq(s.events.onSendAimSync({camMode=53}),false);eq(s.weaponWarning.aimSample,nil);onScriptTerminate(s.script)
s=setup();local later=function()end;s.events.onSendAimSync=later;onScriptTerminate(s.script);eq(s.events.onSendAimSync,later)
-- Both editable warning texts are reachable from the default Weapons page and autosave.
s=setup();s.commands.pa26();s.step();s.page('settings');s.click='Оружие##settings-tab-weapons';s.render()
s.click='Предупреждения##Снаряжение##weapons-pagewarning';s.render();s.render()
s.edits={['##Предупреждение: Тайзер##warning-taser_template']='Стойте! Будет применён тайзер.',
    ['##Предупреждение: Огнестрельное оружие##warning-firearm_template']='Стоять! Прекратите опасные действия.'};s.render();s.edits={};s.step(650)
local saved=s.savedLibrary()
eq(saved.weapon_warning.taser_template,'Стойте! Будет применён тайзер.');eq(saved.weapon_warning.firearm_template,'Стоять! Прекратите опасные действия.');healthy(s);onScriptTerminate(s.script)
-- Show actual profile IDs in its actual order. Hidden names survive 8 -> 4 -> 6 -> 8 and reload validation.
s=setup();s.commands.pa26();s.step();s.page('settings');s.click='Доступ##settings-tab-options';s.render();local studio=s.workspace.studio
local function profile(name,count)
    studio.optionDraft=studio.optionDraft or model.copy(s.workspace.library.settings);studio.optionDraft.wheel_profile=name
    s.drawnText={};s.render();local fields=0
    for _,text in ipairs(s.drawnText)do if text:match('^Категория %d+$')then fields=fields+1 end end;eq(fields,count)
end
profile('full',8)
s.edits={['##Категория 2##wheel-name-documents']='Паспорт и документы',['##Категория 8##wheel-name-custom']='Мои сценарии'};s.render();s.edits={};s.step(650)
profile('compact',4);s.edits={['##Категория 2##wheel-name-detention']='Работа с задержанным'};s.render();s.edits={};s.step(650)
profile('extended',6);s.step(650);profile('full',8);s.step(650)
saved=assert(model.validate(s.workspace.library,core.defaults()));eq(saved.settings.wheel_names.documents,'Паспорт и документы');eq(saved.settings.wheel_names.custom,'Мои сценарии');eq(saved.settings.wheel_names.detention,'Работа с задержанным')
healthy(s);onScriptTerminate(s.script)
-- Measured confirmations shrink for short text, grow with actual wrapping, and stay inside the screen.
s=setup();local im=s.imgui or require 'mimgui';s.rendererContext=true
for _,screen in ipairs({{640,480},{1280,720},{2560,1440}})do
    s.io.DisplaySize.x,s.io.DisplaySize.y=screen[1],screen[2]
    local short=menu.confirmationLayout(im,{title='Удалить сценарий?',lines={'Тест','Удалить эту запись?'},buttons={'ДА','НЕТ'}})
    local long=menu.confirmationLayout(im,{title='Запустить сценарий?',lines={string.rep('Длинный русский текст. ',400)},buttons={'ДА','НЕТ'}})
    check(short.height<258);check(short.height<long.height);check(long.overflow and #long.pages>1)
    check(long.width<=screen[1]-32);check(long.height<=screen[2]-32);check(long.footer>=42)
end
s.rendererContext=false;onScriptTerminate(s.script)
-- Real modal content has no scrolling child; long previews retain every line on pages.
s=setup();s.commands.pa26();s.step();s.page('binds');s.render();local st=s.workspace.studio
st.remove={kind='binding',id=1};s.childCalls={};s.render();check(s.modalOpen)
local compact=s.modalCalls[#s.modalCalls];check(compact.height<258)
for _,child in ipairs(s.childCalls)do check(child.window~='Подтверждение##pa26-confirm','confirmation text must not be a scrolling child')end
s.click='НЕТ##confirm-no';s.render();check(not s.modalOpen)
st.confirmPlan={binding={name='Очень длинный предпросмотр'},target={name='Player_Name',id=37},lines={}}
for n=1,64 do st.confirmPlan.lines[n]='Сообщение '..n..': '..string.rep('Полный текст без удаления. ',4)end
s.render();check(s.modalOpen);s.drawnText={};s.render();local first=table.concat(s.drawnText,'\n')
check(first:find('Сообщение 1:',1,true));local page=st.modalPagination.page
s.click='Далее##confirmation-page';s.render();check(st.modalPagination.page>page);s.drawnText={};s.render()
check(table.concat(s.drawnText,'\n')~=first)
s.click='НЕТ##confirm-no';s.render();check(not s.modalOpen);eq(#s.sent,0);healthy(s);onScriptTerminate(s.script)
