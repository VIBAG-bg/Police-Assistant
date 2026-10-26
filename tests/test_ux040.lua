local fixture=require 'support.fixture';local routes=require 'support.ui_routes';local model=require 'pa26_bindings';local core=require 'pa26_core'
local s=fixture();s.step();routes.settings(s,'options')
local before=model.copy(s.workspace.library.bindings)
routes.chat(s,'split');routes.click(s,'Изменить порог и маркер продолжения##manual-chat-rp-settings');s.step();eq(s.workspace.studio.chatSettingsPage,'split');check(not s.frames[4].condition());routes.settings(s,'options')
-- An older full-options draft must not overwrite a later change in a different group.
local slider=s.imgui.SliderInt;s.imgui.SliderInt=function(label,n,...)if label=='Удержание перед выбором, мс'then n[0]=600;return true end;return slider(label,n,...)end
s.render();s.imgui.SliderInt=slider
routes.chat(s,'filters');s.toggle='Поддержка чата лаунчера##cef-chat';s.render()
routes.chat(s,'commands');s.toggle='Предлагать RP при ручном вводе команды##manual-actions-enabled';s.render()
routes.screen(s,'windows');s.floatEdits={['Непрозрачность']=.73};s.render();s.floatEdits={};s.step(700)
local saved=s.savedLibrary();eq(saved.settings.cef_chat_support,false);eq(saved.settings.manual_actions.enabled,false)
check(math.abs(saved.settings.opacity-.73)<.001);eq(saved.settings.aim_select_delay_ms,600)
for i,b in ipairs(before)do eq(saved.bindings[i].script,b.script)end
-- All helper/stats routes keep their execution controllers and render with no sends.
s.page('addons')
for _,label in ipairs({'Патруль и экипаж##toolpatrol','События патруля##toolevents','Человек и личность##toolidentity',
    'Машина и мегафон##toolvehicle','Розыск, штрафы, /setmark##toolprocedures','Фиксация (F8)##toolevidence','Обучение##tooltraining','Собеседование##toolextras'})do routes.click(s,label)end
s.page('partners');routes.click(s,'Перейти к текущему патрулю и экипажу →##partners-patrol')
routes.operations(s);routes.click(s,'Системный лог PA##История работы##stats-pagesystem_log')
eq(#s.sent,0);eq(#s.scopes,0);eq(s.invalidIOReads,0);onScriptTerminate(s.script)
-- Three choices for a held manual server command. The third is a full cancellation.
local lib=model.defaults(core.defaults());lib.settings.manual_actions.rules.cuff.prefer_bind=false
s=fixture({demo=false,library=lib});s.step();if s.frames[1].condition()then s.commands.pa26();s.step()end
s.chat=true;s.chatText='/cuff 37';s.step();onWindowMessage(0x100,13);eq(s.events.onSendCommand('/cuff 37'),false)
s.chat=false;for _=1,4 do s.step(200)end
routes.click(s,'Отменить всё (Esc) — не отправлять##confirm-cancel')
for _=1,10 do s.step(1500)end;eq(#s.sent,0);check(not s.workspace.studio.manualAction);onScriptTerminate(s.script)
