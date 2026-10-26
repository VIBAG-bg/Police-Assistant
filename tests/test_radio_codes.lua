local core=require 'pa26_core'
local model=require 'pa26_bindings'
local alerts=require 'pa26_alerts'
local cfg=model.alertDefaults()
check(not cfg.code1_enabled);check(not cfg.code4_enabled)
eq(model.alertShortcutDefaults().code1.key,0);eq(model.alertShortcutDefaults().code4.key,0)
local state={session='test:7777',ped=1,localId=0,demo=false,alive=true,focused=true,paused=false,blocked=false,
    typing=false,recording=false,area='Ganton',health=100,local_tag='A-1'}
for _,kind in ipairs({'code1','code4'})do
    check(not alerts.prepare(kind,state,cfg,codec,100,1))
    cfg[kind..'_enabled']=true;cfg[kind..'_channel']='/d'
    cfg[kind..'_template']='{local_tag}'..kind..' · район {area}'
    local plan,err=alerts.prepare(kind,state,cfg,codec,100,1);check(plan,err)
    eq(#plan.lines,1);eq(plan.target,nil);check(not plan.requirements.target)
    check(plan.lines[1]:find('/d A-1 '..kind..' · район Ganton',1,true));eq(codec.decode(plan.wire[1]),plan.lines[1])
    local bad=model.copy(cfg);bad[kind..'_channel']='/rn';check(not model.validateAlerts(bad))
    bad=model.copy(cfg);bad[kind..'_template']='text\n/r injected';check(not model.validateAlerts(bad))
    bad=model.copy(cfg);bad[kind..'_template']='{select_name}';check(not model.validateAlerts(bad))
end
local confirmed={};local now=10000
local helper=model.copy(cfg);helper.help_enabled=true
for _,key in ipairs({'code1_template','code4_template','help_command','help_source'})do
    local t=model.copy(cfg);t[key]=false;check(not model.validateAlerts(t),'Invalid text type '..key)
end
check(not model.validateAlerts(helper),'A name/evidence/acknowledgement are required')
helper.help_command='/testhelp {area}';helper.help_source='Только имитационная модель';helper.help_verified=true;helper.help_delay_ms=2000
local helperPlan,helperError=alerts.prepare('sos',state,helper,codec,now,1);check(helperPlan,helperError)
eq(#helperPlan.lines,2);eq(#helperPlan.steps,3);eq(helperPlan.steps[2].kind,'wait');eq(helperPlan.steps[2].ms,2000)
eq(helperPlan.lines[2],'/testhelp Ganton');eq(codec.decode(helperPlan.wire[2]),helperPlan.lines[2])
local missing=model.copy(state);missing.area='';check(not alerts.prepare('sos',missing,helper,codec,now,1))
for _,bad in ipairs({'/r text','/me test','/pa26restart','/testhelp\n/q','/testhelp {unknown}'})do
    local t=model.copy(helper);t.help_command=bad;check(not model.validateAlerts(t))
end
local c=alerts.new({settings=function()return cfg end,codec=codec,confirm=function(plan)confirmed[#confirmed+1]=plan;return true end})
c:tick(state,now,{})
c:request('sos');now=now+16;c:tick(state,now,{});check(c.pending);local token=c.pending.token
c:request('code4');now=now+16;c:tick(state,now,{});eq(c.pending.token,token,'Cancellation reports cannot replace a critical question')
c:request('code1');now=now+16;c:tick(state,now,{});eq(c.pending.token,token);eq(#confirmed,0)
c:paint(token,now,{});now=now+150;c:tick(state,now,{});c:paint(token,now,{})
now=now+16;c:tick(state,now,{n=true});eq(c.pending,nil)
c:request('code1');now=now+16;c:tick(state,now,{});check(c.pending);eq(c.pending.kind,'code1')
state.alive=false;now=now+16;c:tick(state,now,{y=true});eq(c.pending,nil);eq(#confirmed,0)

local fixture=require 'support.fixture'
local function healthy(s)
    check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(s.invalidIOReads,0)
end
local function click(s,label)s.click=label;s.render();eq(s.click,nil,'Missing control '..label);healthy(s)end
local function key(s,k,mods)
    s.physicalDown={};s.step(150);s.physicalDown={[k]=true}
    for code,v in pairs(mods or {})do s.physicalDown[code]=v end
    s.step();s.physicalDown={};s.step()
end
local function setup(demo)
    local seed=model.defaults(core.defaults());seed.alerts.code1_enabled=true;seed.alerts.code4_enabled=true
    seed.alert_shortcuts.code1={key=0x34,alt=true,ctrl=false,shift=false}
    seed.alert_shortcuts.code4={key=0x35,alt=true,ctrl=false,shift=false}
    local s=fixture({library=seed,demo=demo==true,alerts=true,notifications=true,categoryWheel=true});s.step()
    if s.frames[1].condition()then s.commands.pa26();s.step()end
    return s
end
for _,row in ipairs({{0x34,'code1'},{0x35,'code4'}})do
    local s=setup(false);local c=s.alerts;check(c.buttons.code1);check(c.buttons.code4)
    eq(c.metrics.columns,3);check(c.buttons.code1.y>c.buttons.sos.y)
    key(s,row[1],{[0x12]=true});check(c.pending,row[2]..': '..table.concat(s.logs,'\n')..' shortcut='..model.shortcutName(s.workspace.library.alert_shortcuts[row[2]]));eq(c.pending.kind,row[2]);eq(#s.sent,0)
    key(s,0x4e);eq(c.pending,nil);eq(#s.sent,0)
    key(s,row[1],{[0x12]=true});check(c.pending);key(s,0x59);s.step(120);s.step(1500)
    eq(#s.sent,1);check(s.sent[1].line:find(row[2]=='code1'and'CODE 1'or'CODE 4',1,true))
    s.step(1500);eq(#s.sent,1,'Holding/late frames cannot repeat a confirmed cancellation')
    healthy(s);onScriptTerminate(s.script)
end
local s=setup(true);key(s,0x35,{[0x12]=true});check(s.alerts.pending);key(s,0x59);s.step(120);s.step(1500)
eq(#s.sent,0);healthy(s);onScriptTerminate(s.script)
s=setup(false);s.commands.pa26();s.step();s.page('settings');click(s,'4. Рация и тревоги##settings-tab-radio')
s.edits={['##Текст##alerts-template-code4_template']='CODE 4. Поддержка не нужна, {area}.'};s.render();s.edits={};s.step(700)
eq(s.workspace.library.alerts.code4_template,'CODE 4. Поддержка не нужна, {area}.')
local saved=s.savedLibrary()
eq(saved.alerts.code4_template,'CODE 4. Поддержка не нужна, {area}.');check(saved.alerts.code1_enabled)
click(s,'Назначить CODE 1##alert-key-code1');eq(s.workspace.studio.keyCapture.name,'CODE 1')
click(s,'Отмена##capture-cancel')
for _,width in ipairs({760,1050,1680})do
    s.io.DisplaySize.x=width;s.io.DisplaySize.y=900;s.render();healthy(s)
    local buttons=s.alerts.buttons
    if buttons.code1 and buttons.code4 then
        check(buttons.code1.x+buttons.code1.w<=buttons.code4.x)
        check(buttons.code4.x+buttons.code4.w<=s.io.DisplaySize.x)
        check(buttons.sos.y+buttons.sos.h<buttons.code1.y)
    end
end
eq(#s.sent,0);onScriptTerminate(s.script)
for _,cancel in ipairs({false,true})do
    s=setup(false);local lib=model.copy(s.workspace.library)
    lib.alerts.help_enabled=true;lib.alerts.help_verified=true;lib.alerts.help_command='/testhelp {area}'
    lib.alerts.help_source='Имитационная модель';lib.alerts.help_delay_ms=2000;check(s.workspace:save(lib))
    s.commands.pa26sos();s.step();check(s.alerts.pending);eq(#s.alerts.pending.plan.lines,2);eq(#s.sent,0)
    key(s,0x59)
    for i=1,10 do s.step(100);if #s.sent>0 then break end end
    eq(#s.sent,1);check(s.workspace.executor.queue)
    if cancel then key(s,0x23)end
    for _=1,12 do s.step(500)end
    eq(#s.sent,cancel and 1 or 2,'The optional helper respects cancellation and the shared queue')
    if not cancel then check(s.sent[2].line:find('/testhelp ',1,true));check(s.sent[2].time-s.sent[1].time>=2000)end
    healthy(s);onScriptTerminate(s.script)
end
-- The final native callback must not replace an accepted radio preview.
local seed=model.defaults(core.defaults())
s=fixture({library=seed,demo=false,alerts=true,sendCommandHandler=function()return {'/d rewritten'}end})
s.step();if s.frames[1].condition()then s.commands.pa26();s.step()end
s.commands.pa26sos();s.step();key(s,0x59);s.step(120);s.step(1500)
eq(#s.sent,0);check(s.hasLog('другой обработчик'));healthy(s);onScriptTerminate(s.script)
-- Configure through the actual GUI, reload the saved library, then execute it.
s=setup(false);s.commands.pa26();s.step();s.page('settings');click(s,'4. Рация и тревоги##settings-tab-radio')
s.edits={['##Команда помощи из /help##alerts-help_command']='/testhelp {area}',
    ['##Где и когда проверено##alerts-help_source']='Тестовая модель, не контракт Exsellent'};s.render();s.edits={}
s.intEdits={['Пауза до команды помощи, мс##alerts-help-delay']=2500};s.render();s.intEdits={}
s.toggle='Я проверил название и параметры на сервере##alerts-help_verified';s.render()
s.toggle='Добавлять команду помощи к SOS##alerts-help_enabled';s.render();s.step(700)
saved=s.savedLibrary()
check(saved.alerts.help_enabled);check(saved.alerts.help_verified);eq(saved.alerts.help_delay_ms,2500)
eq(saved.alerts.help_command,'/testhelp {area}');eq(saved.alerts.help_source,'Тестовая модель, не контракт Exsellent')
healthy(s);onScriptTerminate(s.script)
s=fixture({library=saved,demo=false,alerts=true});s.step();if s.frames[1].condition()then s.commands.pa26();s.step()end
s.commands.pa26sos();s.step();key(s,0x59);for _=1,30 do s.step(250)end
eq(#s.sent,2);check(s.sent[2].line:find('/testhelp ',1,true));check(s.sent[2].time-s.sent[1].time>=2500)
healthy(s);onScriptTerminate(s.script)
return TEST_CHECKS
