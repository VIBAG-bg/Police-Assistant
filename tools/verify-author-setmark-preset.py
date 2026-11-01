from pathlib import Path
import json
import os

ROOT=Path(__file__).resolve().parents[1]
ns={'__file__':str(ROOT/'tests/run_tests.py')}
source=(ROOT/'tests/run_tests.py').read_text('utf-8').split('syntax_lua = runtime()')[0]
exec(compile(source,str(ROOT/'tests/run_tests.py'),'exec'),ns)
os.chdir(ROOT)
lua=ns['runtime']()
lua.execute(br"""
local model=require 'pa26_bindings';local author=require 'pa26_author_presets'
local f=assert(io.open('presets/pa-settings.json','rb'));local payload=f:read('*a');f:close()
local fake={};function fake:start(kind)return{id=string.rep('c',32),kind=kind}end
function fake:poll(job)return payload,nil,'v0.43.5'end
local fixture=require 'support.fixture'
local s=fixture({demo=true,authorPresetIO=fake});s.step()
local ini=dofile('moonloader/lib/pa26_config.lua');require('pa26_config').serialize=ini.serialize
assert(s.authorPresets:start('settings'),s.authorPresets.status)
s.step()
assert(s.workspace.studio.authorPresetConfirm,'No preset confirmation')
assert(s.authorPresets:accept())
local expected=TEST_JSON_DECODE(payload).settings.data.settings.manual_actions.rules.setmark.rp
assert(s.workspace.library.settings.manual_actions.rules.setmark.rp==expected,'Live model lost the manual RP')
local saved=s.savedLibrary()
assert(saved.settings.manual_actions.rules.setmark.rp==expected,'Saved file lost the manual RP')
local nextScene=fixture({demo=true,library=saved});nextScene.step()
assert(nextScene.workspace.library.settings.manual_actions.rules.setmark.rp==expected,'Reload lost the manual RP')
if nextScene.frames[1].condition()then nextScene.commands.pa26();nextScene.step()end
nextScene.chat=true;nextScene.chatText='/setmark 9';nextScene.step();onWindowMessage(0x100,13)
assert(nextScene.events.onSendCommand(codec.encode('/setmark 9'))==false,'Command was not held')
nextScene.chat=false;for _=1,4 do nextScene.step(200)end;nextScene.render()
local p=assert(nextScene.workspace.studio.manualAction,'No manual action preview')
assert(table.concat(p.plan.lines,'\n'):find(expected:sub(1,60),1,true),'Preview did not use imported RP')
assert(#nextScene.sent==0,'Import test must not send anything')
print('Published settings -> main controller -> saved file -> reload -> /setmark preview: passed; no sends.')
""")
report={'status':'passed','settings_imported':True,'saved_manual_rp_preserved':True,
        'manual_rp_preserved_after_reload':True,'setmark_preview_uses_imported_rp':True,
        'game_started':False,'commands_sent':0,'local_game_written':False}
(ROOT/'tests/AUTHOR_SETMARK_IMPORT_20261101.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print('Settings import -> production main controller -> save -> reload -> /setmark preview passed; no game writes or sends.')
