local fixture=require 'support.fixture'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local wheel=require 'pa26_wheel'
local function healthy(s)
    check(not s.hasLog('Ошибка интерфейса'));check(not s.hasLog('ошибки отрисовки'));eq(#s.scopes,0);eq(s.invalidIOReads,0)
    check(not s.alerts.failed);eq(s.lockRequests,0)
end
local function setup(options)
    options=options or {};options.alerts=true;options.categoryWheel=true
    local s=fixture(options);s.step()
    if s.frames[1].condition() then s.commands.pa26();s.step() end
    healthy(s);check(s.alerts.bounds)
    return s
end
local function arm(s)
    s.down={};s.step(150);s.step();check(s.alerts.pending);check(s.alerts.armed);healthy(s)
end
local function press(s,key)
    s.down={[key]=true};s.step();s.down={};s.step();healthy(s)
end
local function flush(s)
    s.step(100);s.step(100);s.step(1600);healthy(s)
end
-- Real main(), real hook, real CP1251 wire and no extra help command placeholder.
local s=setup({demo=false})
check(type(s.events.onSendTakeDamage)=='function');check(not s.events.onSendGiveDamage)
for i=1,30 do s.events.onSendTakeDamage(245,20,24,3) end
s.step();check(s.alerts.pending);eq(s.alerts.pending.kind,'shots');eq(s.alerts.pending.hits,30);eq(#s.sent,0)
eq(s.remoteIdentityReads,0,'damage source must never trigger lookup/selection')
arm(s);press(s,0x59);flush(s);eq(#s.sent,1)
eq(s.sent[1].line,'/r Shots fired. По мне открыли огонь. Мой 10-20: East Beach, квадрат M-13.')
s.step(5000,{[0x59]=true});eq(#s.sent,1)
onScriptTerminate(s.script);eq(s.events.onSendTakeDamage,nil);eq(s.events.onSendSpawn,nil)
-- Demo invokes the same confirmation/executor, and sends no network lines.
s=setup();s.events.onSendTakeDamage(245,20,31,3);s.step();arm(s);press(s,0x59);flush(s)
eq(#s.sent,0);check(s.hasLog('[ДЕМО БИНД]'));healthy(s);onScriptTerminate(s.script)
-- N, waiting, held Y, typing/server dialogs, death and lost focus send zero.
for _,reason in ipairs({'no','timeout','held','chat','dialog','dead','focus','pause','spawn','disconnect'}) do
    s=setup({demo=false});s.down[0x59]=reason=='held';s.events.onSendTakeDamage(245,20,24,3);s.step();check(s.alerts.pending)
    if reason=='no' then arm(s);press(s,0x4e)
    elseif reason=='timeout' then s.step(16000)
    elseif reason=='held' then s.step(150);s.step(5000);eq(#s.sent,0)
    else arm(s)
        if reason=='chat' then s.chat=true
        elseif reason=='dialog' then s.dialog=true
        elseif reason=='dead' then s.localDead=true
        elseif reason=='focus' then onWindowMessage(0x0008,0)
        elseif reason=='pause' then s.paused=true
        elseif reason=='spawn' then s.events.onSendSpawn()
        else s.events.onConnectionClosed() end
        s.down[0x59]=true;s.step();s.down={}
    end
    s.step(2500);eq(#s.sent,0,reason);healthy(s);onScriptTerminate(s.script)
end
-- HP changes without a valid firearms RPC, outgoing damage and SD pistol do not suggest shots.
s=setup({demo=false});for _,weapon in ipairs({3,23,49,51,54}) do s.events.onSendTakeDamage(245,25,weapon,3);s.step();eq(s.alerts.pending,nil) end
s.localDead=false;s.step(300);eq(s.alerts.pending,nil);eq(#s.sent,0);healthy(s);onScriptTerminate(s.script)
-- The GUI consumes game keys; Y/N still work through ImGuiIO, while typing does not.
s=setup({demo=false,consumeKeyboard=true});s.commands.pa26();s.step();s.commands.pa26sos();s.step();arm(s)
s.guiDown={[0x59]=true};s.step();s.step();s.guiDown={};flush(s);eq(#s.sent,1);healthy(s);onScriptTerminate(s.script)
s=setup({demo=false,consumeKeyboard=true});s.commands.pa26();s.step();s.commands.pa26sos();s.step();arm(s)
s.io.WantTextInput=true;s.render();s.guiDown={[0x59]=true};s.step();s.step();eq(#s.sent,0)
s.io.WantTextInput=false;s.render();s.step();eq(#s.sent,0);s.guiDown={};s.step();s.step()
s.guiDown={[0x59]=true};s.step();s.step();s.guiDown={};flush(s);eq(#s.sent,1);healthy(s);onScriptTerminate(s.script)
-- Changes of area invalidate a displayed card; a fresh release/press is required.
s=setup({demo=false});s.commands.pa26sos();s.step();arm(s);local token=s.alerts.pending.token
s.zoneKey='GAN';s.down[0x59]=true;s.step();check(s.alerts.pending.token~=token);eq(#s.sent,0)
s.step(150);s.down={};s.step();press(s,0x59);flush(s);eq(#s.sent,1);check(s.sent[1].line:find('Ganton',1,true));onScriptTerminate(s.script)
-- SOS stops an existing frozen binder only after Y; no report interleaves its lines.
local seed=model.defaults(core.defaults());seed.bindings[1].target_required=false;seed.bindings[1].script='Первая\n@wait(6000)\nПоследняя'
s=setup({demo=false,library=seed});s.commands.pa26run('1');flush(s);eq(#s.sent,1)
s.commands.pa26sos();s.step();check(s.alerts.pending.busy);arm(s);eq(#s.sent,1)
press(s,0x59);flush(s);eq(#s.sent,2);check(s.sent[2].line:find('10-70',1,true))
s.step(10000);eq(#s.sent,2);check(s.hasLog('остановлен'));onScriptTerminate(s.script)
-- Shared lane, hidden HUD fallback, supported sizes and large widget scale.
for _,viewport in ipairs({{640,480},{1280,720},{1920,1080},{2560,1440}}) do
    for _,hidden in ipairs({false,true}) do
        s=setup({demo=false});s.io.DisplaySize.x,s.io.DisplaySize.y=viewport[1],viewport[2]
        if hidden then s.commands.pa26hud() end
        s.commands.pa26sos();s.step();arm(s)
        local r=s.alerts.bounds;check(r);check(r.x>=0 and r.y>=0);check(r.x+r.w<=viewport[1]);check(r.y+r.h<=viewport[2])
        local b=s.alerts.buttons;check(b.yes);check(b.no);check(b.yes.x+b.yes.w<b.no.x)
        press(s,0x4e);eq(#s.sent,0);healthy(s);onScriptTerminate(s.script)
    end
end
-- Mouse requires an available cursor, then closes immediately without a second popup.
s=setup({demo=false});s.commands.pa26();s.step();s.commands.pa26sos();s.step();arm(s)
local no=s.alerts.buttons.no;s.io.MousePos.x,s.io.MousePos.y=no.x+no.w/2,no.y+no.h/2
s.mouseClicks={[0]=true};s.render();s.mouseClicks={};s.step();eq(s.alerts.pending,nil);eq(#s.sent,0);healthy(s);onScriptTerminate(s.script)
-- SOS/report routes in Service use the same controller, not the binding executor directly.
local catalog=wheel.build(model.defaults(core.defaults()),0,true)
eq(catalog.byCategory.service.items[1].kind,'alert');eq(catalog.byCategory.service.items[1].id,'sos')
check(wheel.available(catalog,{kind='alert',id='sos',category='service'},false,nil))
check(not wheel.available(catalog,{kind='alert',id='sos',category='wanted'},false,nil))
check(not wheel.available(catalog,{kind='alert',id='missing',category='service'},false,nil))
check(not wheel.available(catalog,{kind='alert',id='sos',category='missing'},false,nil))
-- A server whose library lacks SAMP.Lua still has manual confirmed reports.
s=setup({demo=false,sampEvents=false});s.commands.pa26sos();s.step();arm(s);press(s,0x59);flush(s);eq(#s.sent,1);healthy(s);onScriptTerminate(s.script)
-- Closing/spawning cancels even a wheel frozen before the native state updates.
s=setup({demo=false});s.down[0x58]=true;s.step(16,{[0x58]=true});check(s.runtime.wheel)
s.events.onSendSpawn();eq(s.runtime.wheel,nil);s.down={};s.step(150);eq(#s.sent,0);onScriptTerminate(s.script)
-- Existing hook contracts and ownership are preserved on unload.
local called=0;local previous=function()called=called+1;return false end
local previousSpawn=function()called=called+10;return 'previous' end
s=setup({demo=false,damageHandler=previous,spawnHandler=previousSpawn})
eq(s.events.onSendTakeDamage(245,20,24,3),false);s.step();eq(s.alerts.pending,nil);eq(called,1)
eq(s.events.onSendSpawn(),'previous');eq(called,11);onScriptTerminate(s.script)
eq(s.events.onSendTakeDamage,previous);eq(s.events.onSendSpawn,previousSpawn)
-- A passenger/driver can report received bullet damage; no aimed target is needed.
s=setup({demo=false});s.vehicle=true;s.aimed=false;s.events.onSendTakeDamage(245,20,31,3);s.step();arm(s);press(s,0x59);flush(s)
eq(#s.sent,1);eq(s.remoteIdentityReads,0);healthy(s);onScriptTerminate(s.script)
-- A failed send, death or location change during the preparation delay cannot retry.
for _,failure in ipairs({'send','death','area'}) do
    s=setup({demo=false});s.commands.pa26sos();s.step();arm(s);press(s,0x59)
    if failure=='send' then s.sendError=true elseif failure=='death' then s.localDead=true else s.zoneKey='GAN' end
    flush(s);eq(#s.sent,0);s.sendError=false;s.localDead=false;s.step(10000);eq(#s.sent,0);healthy(s);onScriptTerminate(s.script)
end
-- N leaves the running binder alone; opening notes does not pause its queue.
s=setup({demo=false,library=seed});s.commands.pa26run('1');flush(s);eq(#s.sent,1)
s.commands.pa26sos();s.step();arm(s);press(s,0x4e);s.commands.pa26tips();s.step();s.step(6500);s.step(1600)
eq(#s.sent,2);eq(s.sent[2].line,'Последняя');healthy(s);onScriptTerminate(s.script)
-- A large HUD and a selected-person card share a non-overlapping overlay lane.
s=setup({demo=false,widgetScale=2});s.io.DisplaySize.x,s.io.DisplaySize.y=2560,1440
s.commands.pa26select('37');s.step();s.commands.pa26sos();s.step();arm(s)
local r=s.alerts.bounds;check(r);check(r.x+r.w<=2560 and r.y+r.h<=1440)
healthy(s);press(s,0x4e);eq(#s.sent,0);onScriptTerminate(s.script)
-- Save the new channel/templates through the real settings editor, reopen and confirm.
s=setup({demo=false});s.commands.pa26();s.step();s.page('settings')
s.click='4. Рация и тревоги##settings-tab-radio';s.render()
s.edits={['##Текст##alerts-template-shots_template']='{callsign} Shots fired. 10-20: {area}.'}
s.render();s.edits={};s.step(650)
local saved=s.savedLibrary()
eq(saved.alerts.shots_template,'{callsign} Shots fired. 10-20: {area}.')
healthy(s);onScriptTerminate(s.script)
-- Clearing ImGui's cache while a physical Y is still held cannot manufacture
-- a new press; even OS repeat must wait for release and a new physical edge.
s=setup({demo=false,consumeKeyboard=true});s.physicalDown={[0x59]=true};s.guiDown={}
s.commands.pa26();s.step();s.commands.pa26sos();s.step();s.step(600);s.io.KeysDown[0x59]=false;s.step(600)
eq(#s.sent,0);check(s.alerts.pending);check(not s.alerts.armed)
s.physicalDown={};s.step();s.physicalDown={[0x59]=true};s.step();s.physicalDown={};flush(s)
eq(#s.sent,1);healthy(s);onScriptTerminate(s.script)
-- Losing an unrelated selected person cannot cancel a target-free SOS.
s=setup({demo=false});s.commands.pa26select('37');s.step();s.commands.pa26sos();s.step();arm(s);press(s,0x59)
s.events.onPlayerQuit(37,1);flush(s);eq(#s.sent,1);check(s.sent[1].line:find('10-70',1,true));onScriptTerminate(s.script)
-- If a very large HUD cannot fit beside a confirmation on a small screen,
-- temporarily hide its rendering rather than layering unreadable panels.
s=setup({demo=false,widgetScale=2});s.io.DisplaySize.x,s.io.DisplaySize.y=640,480
s.commands.pa26sos();s.step();arm(s);check(s.alerts.suppressHud);check(s.alerts.bounds.y+s.alerts.bounds.h<=480)
press(s,0x4e);s.render();check(not s.alerts.suppressHud);eq(#s.sent,0);healthy(s);onScriptTerminate(s.script)
