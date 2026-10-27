local core=require 'pa26_core';local model=require 'pa26_bindings';local fixture=require 'support.fixture'
local ini=dofile('moonloader/lib/pa26_config.lua')
check(not core.defaults().main.demo_mode,'A clean install starts in real mode')
local disk=assert(ini.load('moonloader/config/police_assistant_2026.ini'));check(not disk.main.demo_mode)
local saved=model.copy(disk);saved.main.demo_mode=true
local parsed=assert(ini.parse(assert(ini.serialize(saved))));check(core.normalizeConfig(parsed).main.demo_mode,'An existing explicit demo choice remains authoritative')

local s=fixture({demo=false,categoryWheel=true});s.step();s.page('settings')
local function chooseMode(demo)
 local target=demo and'ДЕМО РЕЖИМ · без отправки'or'РЕАЛЬНЫЙ РЕЖИМ · ДЕМО ВЫКЛ'
 local label
 for _,b in ipairs(s.buttonCalls)do if b.label:find(target,1,true)==1 then label=b.label end;check(not b.label:find('##sidebar-demo',1,true))end
 check(label,'Mode switch is visible in Profile');s.click=label;s.render();s.step()
end
chooseMode(true);check(s.runtime.demo);check(s.saved.main.demo_mode);s.ackInfo()
chooseMode(false);check(not s.runtime.demo);check(not s.saved.main.demo_mode);s.ackInfo()
s.saveFail=true;chooseMode(true);check(not s.runtime.demo,'Failed persistence restores the previous mode');check(not s.saved.main.demo_mode)
eq(#s.sent,0);onScriptTerminate(s.script)

-- Actual main -> controller -> atomic store -> live library -> standalone
-- acknowledgement -> reload. Network and disk writes are fake.
local f=assert(io.open('presets/pa-binds.json','rb'));local payload=f:read('*a');f:close()
local remote={start=function(_,kind)return{id=string.rep('a',32),kind=kind}end,
 poll=function()return payload,nil,'v0.40.3'end}
local lib=model.defaults(core.defaults());lib.profile.name='Private Officer';lib.notes[1].body='PRIVATE NOTE'
s=fixture({demo=false,library=lib,authorPresetIO=remote});s.step();s.ackInfo()
local base=s.workspace.base;local documents=require('pa26_user_files').partition(s.workspace.library)
for _,kind in ipairs({'binds','settings','notes'})do s.files[base..'_'..kind..'.json']=TEST_JSON_ENCODE(documents[kind])end
s.files[base..'.ini']=assert(ini.serialize(s.authorPresets.env.config()))
local beforeIni,beforeNotes,beforeSettings=s.files[base..'.ini'],s.files[base..'_notes.json'],s.files[base..'_settings.json']
check(s.authorPresets:start('binds'));s.step();check(s.workspace.studio.authorPresetConfirm)
eq(#s.workspace.library.bindings,6);s.click='ДА##confirm-yes';s.render();check(s.authorPresets.applied)
s.step();check(s.workspace.studio:hasWarning());check(not s.inputDisabled(),'OK must receive mouse and keyboard after the old pages close')
check(not s.frames[4].HideCursor,'The acknowledgement must show the cursor')
eq(#s.workspace.library.bindings,83);eq(s.workspace.library.profile.name,'Private Officer');eq(s.workspace.library.notes[1].body,'PRIVATE NOTE')
eq(s.files[base..'.ini'],beforeIni);eq(s.files[base..'_notes.json'],beforeNotes);eq(s.files[base..'_settings.json'],beforeSettings)
check(not s.reloads);s.click='ОК##warning-ok';s.render();eq(s.click,nil)
for _=1,5 do s.step()end;eq(s.reloads,1,'One acknowledgement queues exactly one reload')
local installed=s.savedLibrary();eq(#installed.bindings,83);eq(installed.profile.name,'Private Officer')
eq(#s.sent,0);check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0);eq(s.invalidIOReads,0);onScriptTerminate(s.script)
s=fixture({demo=false,library=installed});s.step();eq(#s.workspace.library.bindings,83);eq(s.workspace.library.notes[1].body,'PRIVATE NOTE')
eq(#s.sent,0);onScriptTerminate(s.script)
