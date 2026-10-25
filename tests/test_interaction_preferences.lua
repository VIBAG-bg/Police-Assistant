local fixture=require 'support.fixture'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local prefs=require 'pa26_assist_settings'
local function click(s,label)s.click=label;s.render();eq(s.click,nil,label);check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0)end
local cfg=prefs.defaults();cfg.interaction.started_ms=999;check(not prefs.validate(cfg));cfg.interaction.started_ms=1000
cfg.interaction.disconnected='{unknown}';check(not prefs.validate(cfg));cfg.interaction.disconnected='{name} [{id}] вышел.';check(prefs.validate(cfg))
local s=fixture({demo=false});s.step();s.page('settings')
click(s,'Доступ##settings-tab-options')
click(s,'Тексты и сроки карточек##interaction-edit');s.render();eq(s.workspace.studio.assistPage,'notices')
s.edits={['##Человек вышел с сервера##notice-disconnected']='{name} [{id}] вышел с сервера.',
    ['##Заголовок завершения##notice-ended_title']='Общение закончено'}
s.intEdits={['Выход человека с сервера, с##notice-disconnected_ms']=7,['Начало взаимодействия, с##notice-started_ms']=4,
    ['Завершение, с##notice-ended_ms']=5,['Одновременно карточек · 1–3##notice-count']=1}
s.render();s.edits={};s.intEdits={};s.step(700)
local saved=s.workspace.library.assist.interaction;eq(saved.disconnected_ms,7000);eq(saved.started_ms,4000);eq(saved.ended_ms,5000);eq(saved.max_cards,1)
s.commands.pa26select('37');s.step(300);eq(s.hud.notices[1].duration,4000)
s.events.onPlayerQuit(37,1);eq(#s.hud.notices,1);eq(s.hud.notices[1].duration,7000)
eq(s.hud.notices[1].detail,'Player_Name [37] вышел с сервера.');eq(s.hud.notices[1].title,'Общение закончено')
s.step(6999);check(#s.hud.notices==1);s.step(1);eq(#s.hud.notices,0)
eq(#s.localChat,0);eq(#s.sent,0);eq(s.invalidIOReads,0)
local file=s.savedLibrary();eq(file.assist.interaction.disconnected_ms,7000)
onScriptTerminate(s.script)
