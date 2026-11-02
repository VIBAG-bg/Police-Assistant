"""Exercise public GUI persistence/preview paths without modifying the installed game."""
from pathlib import Path
import json, os, subprocess, sys

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
ns = {'__file__': str(ROOT/'tests/run_tests.py')}
source = (ROOT/'tests/run_tests.py').read_text('utf-8').split('syntax_lua = runtime()')[0]
exec(compile(source, str(ROOT/'tests/run_tests.py'), 'exec'), ns)
lua = ns['runtime']()
lua.execute(r'''
local model=require 'pa26_bindings';local core=require 'pa26_core'
local lib=model.defaults(core.defaults());lib.alerts.on_duty=true;lib.alerts.enabled=true
lib.weapon_warning.enabled=false
local s=require('support.fixture')({demo=false,library=lib,alerts=true})
local function click(label)
 s.click=label;s.render();eq(s.click,nil,'Missing control: '..label)
 check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0)
end
s.step();s.page('partners');click('События##Патруль и служба##partners-pageevents')
click('Настройки##События##patrol-event-pagesettings')
local title='Проверка размещения в КПЗ';local template='{unit}: задержанный помещён в КПЗ. Место: {location}.'
s.edits={['##Заголовок##custody-title-jail']=title,['##Текст доклада##custody-template-jail']=template,
 ['##Пояснение под докладом##custody-hint']='Y — передать проверенный доклад; N — отменить.'}
s.render();s.edits={}
s.intEdits={['Видимое время тоста, с##custody-toast_ms']=25,['Срок актуальности предложения, с##custody-ttl_ms']=150,
 ['Защита от повторов команды, с##custody-duplicate_ms']=2,['Максимум ожидающих докладов##custody-queue_limit']=3}
s.render();s.intEdits={};s.step(700)
local cfg=s.workspace.library.patrol_events.command_reports
eq(cfg.jail.title,title);eq(cfg.jail.template,template);eq(cfg.toast_ms,25000);eq(cfg.ttl_ms,150000)
eq(cfg.duplicate_ms,2000);eq(cfg.queue_limit,3)
local saved=s.savedLibrary().patrol_events.command_reports
eq(saved.jail.title,title);eq(saved.jail.template,template);eq(saved.toast_ms,25000);eq(saved.queue_limit,3)
check(table.concat(s.drawnText,'\n'):find('Предпросмотр:',1,true),'Real preview is rendered')
s.toggle='Предлагать после /cuff ID##custody-detention';s.render();eq(s.toggle,nil);s.step(700)
eq(s.savedLibrary().patrol_events.command_reports.detention.enabled,false)
s.toggle='Предлагать готовые доклады##custody-enabled';s.render();eq(s.toggle,nil);s.step(700)
eq(s.savedLibrary().patrol_events.command_reports.enabled,false)
for _,size in ipairs({{640,480},{1152,864},{1366,768},{1920,1080},{2560,1440}})do
 s.io.DisplaySize.x,s.io.DisplaySize.y=size[1],size[2];s.render()
 check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0)
end
eq(#s.sent,0,'Editing report settings never sends radio or server commands')
onScriptTerminate(s.script)
'''.encode('utf-8'))
report={'status':'passed','checks':int(lua.globals()[b'TEST_CHECKS']),
        'scope':'GUI edits, preview, autosave, independent toggles, five viewports, no transmission',
        'game_started':False,'live_game_written':False}
(ROOT/'tests/CUSTODY_GUI0440.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n','utf-8')
print(json.dumps(report))
if '--native' in sys.argv:
    # Reuse the same real x86 ImGui harness; the generated probe remains local.
    probe=(ROOT/'tests/test_ux0440_native32.lua').read_text('utf-8')
    probe=probe.replace("local screens={'patrol','patrol-settings','f4','f4-dispatch','f4-shell','f9-shell','home','knowledge','guide','appearance'}",
                        "local screens={'custody-settings'}")
    probe=probe.replace("if screen=='f9-shell'or screen=='home'then",
        "if screen=='custody-settings'then require('pa26_custody_ui').draw(studio,ui,model.copy(lib.patrol_events),data,{custodyPreview=function()return '/f 1-L-1: один задержанный помещён в КПЗ.'end}) elseif screen=='f9-shell'or screen=='home'then")
    probe=probe.replace('tests/UX_NATIVE32_0440.json','tests/CUSTODY_NATIVE32_0440.json')
    probe=probe.replace('UX 0.44.0 native32: ','Custody 0.44.0 native32: ')
    target=ROOT/'tests/native0440/custody-draw0440.txt';target.parent.mkdir(exist_ok=True)
    target.write_text(probe,'utf-8')
    subprocess.run([r'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe',
        '-NoProfile','-ExecutionPolicy','Bypass','-File',str(ROOT/'tests/support/run_game_lua32.ps1'),
        '-Script',str(target)],check=True,cwd=ROOT)
