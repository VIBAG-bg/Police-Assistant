local fixture=require 'support.fixture';local model=require 'pa26_bindings';local core=require 'pa26_core'
local function setup(seed)
    local s=fixture({demo=false,alerts=true,notifications=true,categoryWheel=true,library=seed});s.step()
    if s.frames[1].condition()then s.commands.pa26();s.step()end;return s
end
local function key(s,k,mods)
    s.physicalDown={};s.step(150);s.physicalDown={[k]=true};for code,v in pairs(mods or{})do s.physicalDown[code]=v end
    s.step();s.physicalDown={};s.step()
end
for _,row in ipairs({{0x31,'sos'},{0x32,'shots'},{0x33,'code0'}})do
    local s=setup();if row[2]=='code0'then s.health=20;s.step()end
    key(s,row[1],{[0x12]=true});check(s.alerts.pending);eq(s.alerts.pending.kind,row[2]);eq(#s.sent,0)
    s.step(150);key(s,0x4e);eq(#s.sent,0);check(not s.alerts.pending)
    check(not s.hasLog('Ошибка интерфейса'));eq(s.invalidIOReads,0);eq(s.lockRequests,0);onScriptTerminate(s.script)
end
local s=setup();key(s,0x33,{[0x12]=true});check(not s.alerts.pending);eq(#s.sent,0);check(s.hasLog('HP'))
key(s,0x31,{[0x11]=true,[0x12]=true});check(not s.alerts.pending)
s.chat=true;key(s,0x31,{[0x12]=true});check(not s.alerts.pending);s.chat=false
s.physicalDown={[0x12]=true,[0x31]=true};s.step();check(not s.alerts.pending,'held after chat cannot open a confirmation')
s.physicalDown={};s.step();key(s,0x31,{[0x12]=true});check(s.alerts.pending);key(s,0x4e);eq(#s.sent,0)
key(s,0x31,{[0x12]=true});s.physicalDown={[0x12]=true};s.step(150)
local no=s.alerts.buttons.no;check(no);s.mx,s.my=no.x+3,no.y+3;s.down[0x01]=true;s.mouseClicks={[0]=true};s.step()
s.down[0x01]=false;s.mouseClicks={};s.step();check(not s.alerts.pending,'mouse N works with Alt cursor, without F9');eq(#s.sent,0)
s.physicalDown={};s.commands.pa26();s.step();s.page('settings');s.click='4. Рация и тревоги##settings-tab-radio';s.render()
s.workspace.studio.warningDraft=model.copy(s.workspace.library.weapon_warning)
s.click='Назначить SOS##alert-key-sos';s.render();eq(s.workspace.studio.keyCapture.name,'SOS')
s.guiDown={[0x11]=true,[0x12]=true,[0x51]=true};s.step();s.guiDown={};s.step();check(s.workspace.studio.keyCapture.valid)
s.click='Назначить##capture-apply';s.render()
local saved=s.savedLibrary();eq(saved.alert_shortcuts.sos.key,0x51);check(saved.alert_shortcuts.sos.ctrl and saved.alert_shortcuts.sos.alt)
-- Cursor is available without F9, including on a running narrative.
local seed=model.defaults(core.defaults());seed.bindings[1].target_required=false;seed.bindings[1].script='Начало\n@wait(10000)\nКонец'
onScriptTerminate(s.script);s=setup(seed);s.commands.pa26run('1');s.step(100);s.step(100);eq(#s.sent,1)
s.physicalDown={[0x12]=true};s.step();check(not s.frames[3].HideCursor);check(not s.hud.editing);check(s.workspace.executor.queue)
s.physicalDown={};s.step();check(s.frames[3].HideCursor);eq(s.lockRequests,0);onScriptTerminate(s.script)
-- Defaults never replace a legacy conflicting bind; all assignments validate.
seed=model.defaults(core.defaults());seed.alert_shortcuts=nil;seed.bindings[1].shortcut={key=0x31,alt=true,ctrl=false,shift=false}
local clean,err=model.validate(seed,core.defaults());check(clean,err);eq(clean.alert_shortcuts.sos.key,0);eq(clean.bindings[1].shortcut.key,0x31)
seed=model.defaults(core.defaults());seed.alert_shortcuts.shots=model.copy(seed.alert_shortcuts.sos);check(not model.validate(seed,core.defaults()))
seed=model.defaults(core.defaults());check(not model.checkKeyAssignment(seed,core.defaults(),nil,{kind='feature',group='alert_shortcuts',field='sos'},seed.weapon_warning.shortcut))
