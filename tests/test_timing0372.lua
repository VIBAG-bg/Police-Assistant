local model=require 'pa26_bindings';local core=require 'pa26_core'
local cfg=core.defaults();cfg.main.interval_ms=1000;cfg.recovery.stable_ms=1000;check(core.validateSettings(cfg))
local old=model.defaults(cfg);old.settings.keep_target_on_interior_change=nil
check(assert(model.validate(old,cfg)).settings.keep_target_on_interior_change)
local specs={
    {'alerts',{'cooldown_ms','timeout_ms','help_delay_ms'}},
    {'weapons',{'delay_ms','holster_delay_ms','cooldown_ms','repeat_ms'}},
    {'taser',{'cooldown_ms','reply_timeout_ms'}},
    {'radio_guard',{'lead_ms','toast_ms'}},
    {'weapon_warning',{'delay_ms','toast_ms','cooldown_ms','remember_ms'}},
    {'patrol_session',{'interval_ms'}},
    {'patrol_events',{'attempt_ttl_ms','duplicate_ms','toast_ms','followup_ms','followup_ttl_ms','followup_snooze_ms'}},
    {'operations',{'timeout_ms','confirm_ms','chat_window_ms'}},
    {'identity',{'expiry_ms'}},
    {'procedures',{'delay_ms','wanted_reminder_delay_ms','wanted_reminder_snooze_ms','wanted_reminder_show_ms'}},
    {'vehicle',{'confirmation_ms','pursuit_interval_ms'}},
}
local lib=model.defaults(cfg)
for _,row in ipairs(specs)do
    check(type(lib[row[1]])=='table',row[1])
    for _,key in ipairs(row[2])do lib[row[1]][key]=1000 end
end
lib.alerts.patrol.police_interval_ms=1000;lib.alerts.patrol.prison_interval_ms=1000;lib.alerts.patrol.enabled=true
lib.patrol_session.enabled=true;lib.patrol_session.periodic=true;lib.vehicle.enabled=true;lib.vehicle.pursuit_periodic=true
lib.assist.evidence.timeout_ms=1000;lib.assist.evidence.confirmation_ms=1000
lib.settings.manual_chat.interval_ms=1000
lib.radio_guard.custom={{id=1,name='Тест',enabled=true,confirmation=true,channel='/r',template='Доклад.',interval_ms=1000}}
lib.radio_guard.next_id=2
lib=assert(model.validate(lib,cfg))
local parts=require('pa26_user_files').partition(lib)
local saved=assert(require('pa26_user_files').combine(TEST_JSON_DECODE(TEST_JSON_ENCODE(parts)),cfg))
for _,row in ipairs(specs)do for _,key in ipairs(row[2])do
    eq(saved[row[1]][key],1000,row[1]..'.'..key)
    if not(key=='followup_ttl_ms' or key=='followup_ms' or key=='followup_snooze_ms')then
        for _,bad in ipairs({999,1000.5,-1,math.huge,0/0})do
            local probe=model.copy(lib);probe[row[1]][key]=bad
            check(not model.validate(probe,cfg),row[1]..'.'..key..' accepted invalid time')
        end
    end
end end
eq(saved.settings.manual_chat.interval_ms,1000);eq(saved.assist.evidence.timeout_ms,1000)
eq(saved.assist.evidence.confirmation_ms,1000);eq(saved.radio_guard.custom[1].interval_ms,1000)
-- A one-second report still requires a visible countdown, with no backlog.
local radio=require 'pa26_radio_guard';local prefs=require 'pa26_preferences'
local now=0;local gc=prefs.radioGuardDefaults();gc.custom=model.copy(lib.radio_guard.custom);gc.custom[1].confirmation=false
gc.next_id=2;local plans={}
local state={session='S',ped=1,demo=false,alive=true,onDuty=true,radioEnabled=true,focused=true,paused=false,blocked=false}
local guard=radio.new({settings=function()return gc end,codec=codec,start=function(p)plans[#plans+1]=p;return true end})
local function tick(ms,paint)
    now=now+ms;guard:tick(model.copy(state),now)
    if paint then for _,t in ipairs(guard:candidates())do guard:shown(t.token)end end
end
tick(0,false);for _=1,30 do tick(100,false)end;eq(#plans,0,'hidden preview sent a short report')
local candidate=guard:candidates()[1];check(candidate);eq(guard:find(candidate.token).lead,1000)
tick(0,true);for _=1,9 do tick(100,true)end;eq(#plans,0)
tick(100,true);eq(#plans,1);check(guard:validPlan(plans[1]))
for _=1,100 do tick(100,true)end;eq(#plans,1,'queued report multiplied into a backlog')
guard:onExecution('sent_line',{plan=plans[1]});tick(0,true)
tick(100,true);candidate=guard:candidates()[1];check(candidate);check(guard:cancel(candidate.token))
tick(100,true);eq(#plans,1)
-- Rendered controls and split-document autosave retain all three one-second
-- weapon timers. Changing a lower bound must not replace users' saved values.
local fixture=require 'support.fixture';local s=fixture({demo=true});s.step();s.page('settings')
local im=require 'mimgui';local slider=im.SliderInt;local seen={}
local fields={['Оружие в руках, с##weapons-delay_ms']='delay_ms',
    ['Между отыгровками, с##weapons-cooldown_ms']='cooldown_ms',
    ['Повтор одного оружия, с##weapons-repeat_ms']='repeat_ms'}
im.SliderInt=function(label,value,low,high)
    if fields[label]then eq(low,1);value[0]=1;seen[fields[label]]=true;return true end
    return slider(label,value,low,high)
end
s.click='5. Оружие и тайзер##settings-tab-weapons';s.render();im.SliderInt=slider;s.step(650)
local raw=s.savedLibrary();for _,key in pairs(fields)do check(seen[key],key);eq(raw.weapons[key],1000)end
check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0);onScriptTerminate(s.script)
-- The actual main script executes with a one-second global interval; it never
-- treats 1000 ms as corrupt and it never sends the next line at 999 ms.
local seed=model.defaults(core.defaults());seed.bindings[1].target_required=false;seed.bindings[1].skip_confirmation=true
seed.bindings[1].script='/me проверил запись.\n/me закрыл журнал.'
s=fixture({demo=false,library=seed});s.step();s.workspace.cfg.main.interval_ms=1000
s.commands.pa26run('1');s.step(16);s.step(100);eq(#s.sent,1)
s.step(999);eq(#s.sent,1);s.step(1);eq(#s.sent,2)
check(not s.hasLog('Ошибка интерфейса'));onScriptTerminate(s.script)
-- Manual splitting uses the same one-second timing contract on all radio/OOC
-- and RP channels, including the action-preserving /todo form.
local manual=require 'pa26_manual_chat';local rp=require 'pa26_rp_settings'
for _,channel in ipairs({'','/me','/do','/try','/r','/rn','/f','/fn','/d','/df','/n','/todo'})do
    local text=string.rep('очень длинное сообщение ',6):match('^(.-)%s*$')
    if channel~=''then text=channel..' '..text end
    if channel=='/todo'then text=text..'*обращаясь к диспетчеру' end
    local mc=manual.defaults();mc.interval_ms=1000;local clock=1000;local lines={}
    local context={session='S',alive=true,focused=true,paused=false,blocked=false,chatActive=false,ownWindow=false,dialogActive=false}
    local q=manual.new({codec=codec,now=function()return clock end,epoch=function()return 1 end,context=function()return context end,
        interval=function()return 1000 end,settings=function()return mc,rp.defaults(),'',{},'Officer_Name'end,
        busy=function()return false end,send=function(line)lines[#lines+1]=line;return true end})
    eq(q:offer(text,'one').status,'accepted',channel);q:tick();eq(#lines,1)
    clock=clock+999;q:tick();eq(#lines,1);clock=clock+1;q:tick();eq(#lines,2)
end
