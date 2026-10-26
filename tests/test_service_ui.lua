-- Actual main(), callbacks, shared executor and native FFI renderer doubles.
local fixture=require 'support.fixture'
local core=require 'pa26_core'
local model=require 'pa26_bindings'
local function healthy(s)
    check(not s.hasLog('Ошибка интерфейса'));check(not s.hasLog('ошибки отрисовки'))
    eq(#s.scopes,0);eq(s.invalidIOReads,0);eq(s.lockRequests,0)
end
local function setup(seed,extra)
    seed=model.copy(seed or model.defaults(core.defaults()));seed.taser.activation='weapon';seed.taser.weapon_id=23 -- Explicit legacy integration scenario.
    local options={demo=false,alerts=true,categoryWheel=true,library=seed}
    for k,v in pairs(extra or {})do options[k]=v end
    local s=fixture(options);s.step();if s.frames[1].condition()then s.commands.pa26();s.step()end
    healthy(s);return s
end
local function shot(s,id)s.events.onSendBulletSync({weaponId=id or 23,hitType=0,targetId=65535});s.step();healthy(s)end
local function wait(s,ms)for i=1,math.floor(ms/1000)do s.step(1000)end end
local function overlaps(a,b)return a and b and a.x<b.x+b.w and a.x+a.w>b.x and a.y<b.y+b.h and a.y+a.h>b.y end
local s=setup();s.weapon=23;s.step();check(s.taser:view().visible);eq(s.taser:view().charges,2)
shot(s);eq(s.taser:view().charges,1);eq(#s.sent,0);wait(s,5000);check(s.taser:view().ready)
shot(s);eq(#s.sent,1);check(s.sent[1].line:match('^/me '));eq(s.taser:view().charges,0);check(not s.taser:view().ready)
wait(s,4000);check(not s.taser:view().ready);wait(s,1000);check(s.taser:view().ready);eq(s.taser:view().charges,2)
eq(s.remoteIdentityReads,0);onScriptTerminate(s.script);eq(s.events.onSendBulletSync,nil)
-- A real failed send keeps 0 charges and never retries. Explicit /pa26reload works.
s=setup();s.weapon=23;s.step();shot(s);wait(s,5000);s.sendError=true;shot(s)
eq(#s.sent,0);check(s.taser:view().button);wait(s,10000);eq(#s.sent,0)
s.sendError=false;s.commands.pa26reload();s.step();eq(#s.sent,1);check(s.taser:view().ready);onScriptTerminate(s.script)
local commandCancelled=function()return false end
s=setup(nil,{sendCommandHandler=commandCancelled});s.weapon=23;s.step();shot(s);wait(s,5000);shot(s);wait(s,5000)
eq(#s.sent,0);check(not s.taser:view().ready);check(s.taser:view().button)
onScriptTerminate(s.script);eq(s.events.onSendCommand,commandCancelled)
-- Own note windows coexist with a narrative; taser reload never cuts it in half.
local seed=model.defaults(core.defaults());seed.bindings[1].target_required=false
seed.bindings[1].script='Начало\n@wait(10000)\nКонец'
s=setup(seed);s.weapon=23;s.step();s.commands.pa26run('1');s.step(100);s.step(100)
eq(#s.sent,1);shot(s);wait(s,5000);shot(s);check(s.taser:needsReload());eq(#s.sent,1)
s.commands.pa26tips();s.step();wait(s,6000);s.step(1600);s.step(1600)
eq(#s.sent,3);eq(s.sent[2].line,'Конец');check(s.sent[3].line:match('^/me '));healthy(s);onScriptTerminate(s.script)
-- Critical health needs fresh firearm evidence; Y sends once with the configured channel.
seed=model.defaults(core.defaults());seed.alerts.auto_code0=true;seed.alerts.code0_channel='/d'
s=setup(seed);s.events.onSendTakeDamage(245,25,24,3);s.health=20;s.step();eq(s.alerts.pending.kind,'code0')
s.step(150);s.step();s.physicalDown={[0x59]=true};s.step();s.physicalDown={};s.step(100);s.step(100)
eq(#s.sent,1);check(s.sent[1].line:match('^/d CODE 0'));onScriptTerminate(s.script)
-- Periodic automatic report uses its own timer and the same queue; no catch-up.
seed=model.defaults(core.defaults());seed.alerts.patrol.enabled=true;seed.alerts.patrol.confirmation=false
seed.alerts.patrol.police_interval_ms=60000
s=setup(seed);check(s.patrol:view().visible);wait(s,59000);eq(#s.sent,0);wait(s,1000);eq(#s.sent,1)
check(s.sent[1].line:find('Продолжаю патруль',1,true));s.step();check(s.patrol:view().remaining>59000)
s.step(600000);eq(#s.sent,1);onScriptTerminate(s.script)
-- Death/spawn clears old shot events, counters, RP queues and patrol clocks.
s=setup();s.weapon=23;s.step();shot(s);s.events.onSendBulletSync({weaponId=23});s.events.onSendSpawn();s.step()
eq(s.taser.shots,0);eq(#s.sent,0);healthy(s);onScriptTerminate(s.script)
-- The previous script may cancel a packet. Hook ownership survives unload.
local called=0;local previous=function(data)called=called+1;return false end
s=setup(nil,{bulletHandler=previous});s.weapon=23;s.step();eq(s.events.onSendBulletSync({weaponId=23}),false)
s.step();eq(s.taser.shots,0);eq(called,1);onScriptTerminate(s.script);eq(s.events.onSendBulletSync,previous)
-- Fresh foreground layout: no taser/SOS/target-card overlap, edges fit viewport.
for _,size in ipairs({{640,480},{1280,720},{1920,1080},{2560,1440}})do
    for _,scale in ipairs({.75,1,2})do
        s=setup(nil,{widgetScale=scale});s.io.DisplaySize.x,s.io.DisplaySize.y=size[1],size[2]
        s.weapon=23;s.step();s.commands.pa26select('37');s.step();s.commands.pa26sos();s.step(150);s.render()
        healthy(s);local gear=s.taser.bounds;local alert=s.alerts.bounds
        if gear then check(gear.x>=0 and gear.y>=0 and gear.x+gear.w<=size[1] and gear.y+gear.h<=size[2]);check(not overlaps(gear,alert))end
        check(alert and alert.x+alert.w<=size[1] and alert.y+alert.h<=size[2])
        local hud=s.hud
        if hud then
            if not s.alerts.suppressHud then check(not overlaps(gear,hud.bounds));check(not overlaps(alert,hud.bounds))end
            for _,notice in ipairs(hud.noticeBounds or {})do check(not overlaps(gear,notice));check(not overlaps(alert,notice))end
        end
        onScriptTerminate(s.script)
    end
end
-- Settings routes: independent drafts, channel save, patrol save, weapon and taser save.
s=setup();s.commands.pa26();s.step();s.page('settings');s.click='4. Рация и тревоги##settings-tab-radio';s.render()
s.edits={['##Текст##alerts-template-shots_template']='{callsign} Shots fired. 10-20: {area}.'};s.render();s.edits={}
local studio=s.workspace and s.workspace.studio
check(studio and studio.alertDraft)
-- Saving patrol while a radio draft is open must not roll patrol back later.
studio.radioPage='patrol';s.render()
s.toggle='Включить периодические доклады##patrol-enabled';s.render()
s.edits={['##Пост тюрьмы · вручную##patrol-post']='Северный пост'};s.render();s.edits={}
s.step(650)
local path='moonloader\\config\\police_assistant_2026_library.json'
local raw=s.savedLibrary();check(raw.alerts.patrol.enabled);eq(raw.alerts.patrol.post,'Северный пост')
check(not studio.alertDraft,'independent debounced radio settings also save automatically')
studio.radioPage='emergency';s.render()
s.step()
raw=s.savedLibrary();eq(raw.alerts.shots_template,'{callsign} Shots fired. 10-20: {area}.')
check(raw.alerts.patrol.enabled);eq(raw.alerts.patrol.post,'Северный пост')
s.click='5. Оружие и тайзер##settings-tab-weapons';s.render();s.toggle='Включить отыгровку доставания##weapons-enabled';s.render()
s.edits={['##Название для переменных и /me##weapon-name']='ERP Taser'};s.render();s.edits={}
s.step(650);raw=s.savedLibrary()
check(raw.weapons.enabled);eq(raw.weapons.items['23'].name,'ERP Taser');eq(raw.alerts.shots_template,'{callsign} Shots fired. 10-20: {area}.')
s.io.DisplaySize.x,s.io.DisplaySize.y=640,480;s.render();healthy(s)
local bar;for _,child in ipairs(s.childCalls)do if child.name=='settings-tabs##pa26'then bar=child end end
check(bar and bar.height>=100,'narrow settings tabs must use two visible rows')
studio.weaponPage='taser';s.render()
s.intEdits={['RP-выстрелов до перезарядки##taser-capacity']=3};s.render();s.intEdits={};s.step(650)
raw=s.savedLibrary();eq(raw.taser.capacity,3);eq(raw.weapons.items['23'].name,'ERP Taser')
onScriptTerminate(s.script)
