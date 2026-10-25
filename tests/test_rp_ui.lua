local fixture=require 'support.fixture'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local rp=require 'pa26_rp_text'
local function healthy(s)check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(s.invalidIOReads,0)end
local function click(s,label)s.click=label;s.render();eq(s.click,nil,label);healthy(s)end
local lib=model.defaults(core.defaults());local b=model.newBinding(7);b.name='Длинная отыгровка';b.enabled=true;b.target_required=false
local body=string.rep('осмотрелся вокруг и проверил обстановку ',4):match('^(.-)%s*$')
b.script='/me '..body..'\n/do '..body..'\n/r Готово.';lib.bindings[#lib.bindings+1]=b;lib.next_id=8
local s=fixture({demo=false,library=lib});s.step();s.page('settings');click(s,'Перенос /me и /do##rp-settings');s.render()
eq(s.workspace.studio.assistPage,'roleplay')
s.edits={['##Маркер продолжения##rp-marker']='…'};s.render();s.edits={};s.step(700);eq(s.workspace.library.rp_text.marker,'…')
local saved=s.savedLibrary();eq(saved.rp_text.body_limit,90);eq(saved.rp_text.marker,'…')
-- Invalid numeric edits preserve the last valid settings, with visible retry/correction.
s.intEdits={['Запас до края строки · 0–32##rp-margin']=-1};s.render();s.intEdits={};s.step(700)
eq(s.workspace.library.rp_text.margin,6);check(s.workspace.studio.autosaves.rp_text.failed)
s.click='ОК##warning-ok';s.render();s.render()
s.intEdits={['Запас до края строки · 0–32##rp-margin']=5};s.render();s.intEdits={};s.step(700);eq(s.workspace.library.rp_text.margin,5)
-- The real main/controller path previews all chunks before consent.
s.commands.pa26run('7');s.step();s.step(150);s.render()
local plan=s.workspace.prepared;check(plan);check(#plan.lines>2);eq(#s.sent,0)
check(plan.rpSignature);check(s.workspace.studio.confirmPlan)
click(s,'НЕТ##confirm-no');s.step();eq(#s.sent,0)
s.commands.pa26run('7');s.step();s.step(150);s.render();plan=s.workspace.prepared;click(s,'ДА##confirm-yes')
for _=1,#plan.lines+2 do s.step(1500)end
eq(#s.sent,#plan.lines)
for i,v in ipairs(s.sent)do eq(v.line,plan.lines[i]);if i>1 then check(v.time-s.sent[i-1].time>=1500)end end
-- A later change of RP settings cancels consent, even for a regular binding.
s.commands.pa26run('7');s.step();s.step(150);s.render();eq(#s.sent,#plan.lines)
local changed=model.copy(s.workspace.library);changed.rp_text.margin=7;check(s.workspace:save(changed))
-- Saving settings removes the old binding confirmation, so it cannot be executed.
check(not s.workspace.studio.confirmPlan);s.step();eq(#s.sent,#plan.lines)
healthy(s);onScriptTerminate(s.script)
