local fixture=require 'support.fixture';local core=require 'pa26_core';local model=require 'pa26_bindings'
local function healthy(s)
    check(not s.hasLog('Ошибка интерфейса'));check(not s.hasLog('Компактный виджет отключён'));eq(#s.scopes,0);eq(s.invalidIOReads,0);eq(s.lockRequests,0)
end
local function setup(seed)
    seed=seed or model.defaults(core.defaults());seed.weapon_warning.trigger='stable';seed.weapon_warning.trigger_revision=1
    local s=fixture({demo=false,alerts=true,notifications=true,categoryWheel=true,library=seed});s.step()
    if s.frames[1].condition()then s.commands.pa26();s.step()end
    healthy(s);return s
end
local function wait(s,ms)for i=1,math.floor(ms/1000)do s.step(1000)end;if ms%1000>0 then s.step(ms%1000)end end
local function chord(s,key,mods)
    s.physicalDown={};s.step(150);s.physicalDown={[key]=true}
    for k,v in pairs(mods or {})do s.physicalDown[k]=v end
    s.step();s.physicalDown={};s.step();s.step(100);s.step(100);healthy(s)
end
-- Real main/physical reader/shared executor: weapon reminder never speaks itself.
local s=setup();s.weapon=23;s.step();wait(s,5000);check(s.weaponWarning.pending);check(s.notifications.bounds);eq(#s.sent,0)
chord(s,0x57,{[0x12]=true});eq(#s.sent,1);check(s.sent[1].line:match('^/s '));eq(s.weaponWarning.pending,nil)
wait(s,30000);eq(#s.sent,1);onScriptTerminate(s.script)
-- Confirm mode, held Y, N, and critical priority; no Y leaks between surfaces.
local seed=model.defaults(core.defaults());seed.weapon_warning.mode='confirm'
s=setup(seed);s.weapon=23;s.physicalDown={[0x59]=true};s.step();wait(s,5000);eq(#s.sent,0)
s.physicalDown={};s.step(150);chord(s,0x4e);eq(#s.sent,0)
s.commands.pa26warn();s.step();s.step(150);s.commands.pa26sos();s.step();check(s.alerts.pending);check(not s.notifications:view().visible)
chord(s,0x59);eq(#s.sent,1);check(s.sent[1].line:find('10-70',1,true));check(not s.sent[1].line:match('^/s'))
onScriptTerminate(s.script)
-- Existing police and prison reports include the warning and persistent cancel.
for _,kind in ipairs({'police','prison'})do
    seed=model.defaults(core.defaults());seed.weapon_warning.enabled=false;seed.alerts.patrol.enabled=true;seed.alerts.patrol.mode=kind
    seed.alerts.patrol.confirmation=false;seed.alerts.patrol[kind..'_interval_ms']=60000;seed.alerts.patrol.post='Северный пост'
    s=setup(seed);wait(s,30000);check(s.notifications.active and s.notifications.active.owner=='radio');check(s.notifications.active.full);eq(#s.sent,0)
    wait(s,11000);check(not s.notifications.active.full);check(s.notifications.buttons.no);eq(#s.sent,0)
    chord(s,0x4e,{[0x12]=true});wait(s,25000);eq(#s.sent,0,'cancelled occurrence must stay cancelled');healthy(s)
    onScriptTerminate(s.script)
end
seed=model.defaults(core.defaults());seed.weapon_warning.enabled=false;seed.alerts.patrol.enabled=true;seed.alerts.patrol.confirmation=false;seed.alerts.patrol.police_interval_ms=60000
s=setup(seed);wait(s,60000);s.step(100);eq(#s.sent,1);check(s.sent[1].line:find('Продолжаю патруль',1,true));healthy(s);onScriptTerminate(s.script)
-- User-authored scheduled radio text goes through the same producer and queue.
seed=model.defaults(core.defaults());seed.weapon_warning.enabled=false;seed.radio_guard.next_id=2
seed.radio_guard.custom={{id=1,name='Мой доклад',enabled=true,confirmation=false,interval_ms=60000,channel='/d',template='{my_name}: пост {post}.'}}
seed.profile.name='Officer Name';seed.alerts.patrol.post='Пост А'
s=setup(seed);wait(s,30000);check(s.notifications.active.body:match('^/d Officer Name'));wait(s,30000);s.step(100)
eq(#s.sent,1);eq(s.sent[1].line,'/d Officer Name: пост Пост А.');onScriptTerminate(s.script)
-- Built-in confirmation shares the cancellable occurrence, including queued Y.
seed=model.defaults(core.defaults());seed.weapon_warning.enabled=false;seed.radio_guard.next_id=3
seed.radio_guard.custom={
    {id=1,name='Первый',enabled=true,confirmation=false,interval_ms=60000,channel='/r',template='Первое расписание.'},
    {id=2,name='Второй',enabled=true,confirmation=false,interval_ms=60000,channel='/r',template='Второе расписание.'}}
s=setup(seed);wait(s,60000);eq(#s.sent,1);eq(s.sent[1].line,'/r Первое расписание.')
wait(s,31000);eq(#s.sent,2,'simultaneous schedules must not starve each other');eq(s.sent[2].line,'/r Второе расписание.');healthy(s);onScriptTerminate(s.script)
-- Built-in confirmation shares the cancellable occurrence, including queued Y.
seed=model.defaults(core.defaults());seed.weapon_warning.enabled=false;seed.alerts.patrol.enabled=true;seed.alerts.patrol.police_interval_ms=60000
s=setup(seed);wait(s,60000);eq(s.notifications.active.mode,'confirm');eq(#s.sent,0)
s.runtime.lastSentAt=s.now;chord(s,0x59);check(s.workspace.executor.queue and s.workspace.executor.queue.plan.radioGuard)
eq(#s.sent,0);chord(s,0x4e,{[0x12]=true});wait(s,2000);eq(#s.sent,0);check(not s.workspace.executor.queue)
onScriptTerminate(s.script)
-- Cancel and emergency preemption are effective after queueing, before wire send.
for _,method in ipairs({'cancel','emergency'})do
    seed=model.defaults(core.defaults());seed.weapon_warning.enabled=false;seed.alerts.patrol.enabled=true
    seed.alerts.patrol.confirmation=false;seed.alerts.patrol.police_interval_ms=60000
    s=setup(seed);wait(s,59000);s.runtime.lastSentAt=s.now+1000;s.step(1000)
    check(s.workspace.executor.queue and s.workspace.executor.queue.plan.radioGuard);eq(#s.sent,0)
    if method=='cancel'then chord(s,0x4e,{[0x12]=true})else s.commands.pa26sos();s.step();check(s.alerts.pending)end
    wait(s,2000);eq(#s.sent,0);check(not s.workspace.executor.queue);healthy(s);onScriptTerminate(s.script)
end
-- Own windows do not interrupt unrelated binders, weapon warning waits its turn.
seed=model.defaults(core.defaults());seed.bindings[1].target_required=false;seed.bindings[1].script='Начало\n@wait(10000)\nКонец'
s=setup(seed);s.weapon=23;s.step();s.commands.pa26run('1');s.step(100);s.step(100);eq(#s.sent,1)
wait(s,5000);chord(s,0x57,{[0x12]=true});eq(#s.sent,1);s.commands.pa26tips();wait(s,6000);wait(s,2000);s.step(100);wait(s,2000)
eq(#s.sent,3,'expected binder and warning: '..#s.sent..' lines, warning '..tostring(s.weaponWarning.pending and s.weaponWarning.pending.phase));eq(s.sent[2].line,'Конец');check(s.sent[3].line:match('^/s'));healthy(s);onScriptTerminate(s.script)
-- Native renderer doubles: target, taser and toast share the available viewport.
s=setup();s.hud.settings.visible=false;s.weapon=23;s.step();wait(s,5000);check(s.notifications.bounds,'notifications must work with the HUD hidden');eq(#s.sent,0);onScriptTerminate(s.script)
for _,size in ipairs({{640,480},{1280,720},{2560,1440}})do
    s=setup();s.io.DisplaySize.x,s.io.DisplaySize.y=size[1],size[2];s.weapon=23;s.step();wait(s,5000)
    s.commands.pa26select('37');s.step();healthy(s)
    local r=s.notifications.bounds
    if r then
        check(r.x>=0 and r.y>=0 and r.x+r.w<=size[1]and r.y+r.h<=size[2])
        local blockers={};if s.hud.bounds then blockers[#blockers+1]=s.hud.bounds end
        if s.taser.bounds then blockers[#blockers+1]=s.taser.bounds end
        for _,b in ipairs(s.hud.noticeBounds or {})do blockers[#blockers+1]=b end
        for _,b in ipairs(blockers)do check(not require('pa26_notifications').overlaps(r,b),'notification overlaps another widget')end
    end
    onScriptTerminate(s.script)
end
-- Actual settings form, persisted custom reports, deletion popup and feature capture.
s=setup();s.commands.pa26();s.step();s.page('settings');s.click='Связь##settings-tab-radio';s.render()
local studio=s.workspace.studio;studio.radioPage='automatic';s.render();s.click='+ Новый автодоклад##guard-new';s.render()
check(studio.radioGuardDraft);s.edits={['##Название##guard-name']='Мой пользовательский доклад'};s.render();s.edits={}
studio.radioGuardDraft.custom[1].interval_ms=60000;s.toggle='Включить расписание##guard-enabled';s.render()
s.step(650)
local path='moonloader\\config\\police_assistant_2026_library.json';local saved=s.savedLibrary();eq(#saved.radio_guard.custom,1);check(saved.radio_guard.custom[1].enabled)
s.click='Удалить##guard-delete';s.render();check(studio.customRemove);s.click='НЕТ##confirm-no';s.render();eq(#s.savedLibrary().radio_guard.custom,1)
s.click='Удалить##guard-delete';s.render();s.click='ДА##confirm-yes';s.render();eq(#s.savedLibrary().radio_guard.custom,0)
s.click='+ Новый автодоклад##guard-new';s.render();eq(studio.radioGuardDraft.custom[1].id,2,'internal IDs do not reuse stale callbacks')
s.click='Оружие##settings-tab-weapons';s.render();studio.weaponPage='warning';s.render()
s.edits={['##Предупреждение: Тайзер##warning-taser_template']='Предупреждение: будет применён тайзер.'};s.render();s.edits={}
s.click='Назначить сочетание предупреждения##warning-key';s.render();check(studio.keyCapture)
s.guiDown={[0x11]=true,[0x12]=true,[0x48]=true};s.step();s.guiDown={};s.step();check(studio.keyCapture.valid)
s.click='Назначить##capture-apply';s.render();s.step(650)
saved=s.savedLibrary();eq(saved.weapon_warning.shortcut.key,0x48);check(saved.weapon_warning.shortcut.ctrl and saved.weapon_warning.shortcut.alt)
eq(saved.weapon_warning.taser_template,'Предупреждение: будет применён тайзер.');healthy(s);onScriptTerminate(s.script)
