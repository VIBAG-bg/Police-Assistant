local fixture=require 'support.fixture';local model=require 'pa26_bindings';local core=require 'pa26_core'
local function healthy(s)check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(s.invalidIOReads,0);eq(#s.scopes,0)end
local function click(s,label)s.click=label;s.render();eq(s.click,nil,label);healthy(s)end
-- Idle cancellation invalidates stale proposals without fabricating a status event.
local e=require('pa26_evidence').new({date=function()return'2026-10-29'end});e:cancel('idle');eq(e.message,nil);e.intent={demo=true};e:cancel('active');eq(e.message,'active');check(e.pendingRecord)
local v=require('pa26_vehicle').new({});v:cancel('idle');eq(v.message,nil);v.intent={};v:cancel('active');eq(v.message,'active')
local s=fixture({productionWindows=true,demo=false,categoryWheel=true});s.step()
for _=1,3 do s.chat=true;s.step();s.chat=false;s.step()end
eq(s.evidence.message,nil);eq(s.vehicleController.message,nil);eq(s.caseForms.message,nil)
if s.frames[1].condition()then s.commands.pa26();s.step()end
s.caseForms.message='Old scene';s.workspace.studio.statusInfo={key='procedures',message='Old scene'}
s.commands.su('37');s.step();s.step();local f=s.workspace.studio.caseForm
check(f);eq(f.reason_group,'all');eq(s.caseForms.message,nil);check(not s.workspace.studio.statusInfo)
f.stage='basis';s.render();eq(s.workspace.studio.wantedMatchedCount,31)
f.reason_group='08';s.render();eq(s.workspace.studio.wantedMatchedCount,2)
s.edits={['##Поиск · можно оставить пустым##wanted-search']='Похищение'};s.render();s.edits={};check(s.workspace.studio.wantedMatchedCount>=3)
eq(#s.sent,0);healthy(s);onScriptTerminate(s.script)
-- A save failure cannot call finish; all successful writes precede finish.
local shutdown=require 'pa26_shutdown';local log={}
local ok=shutdown.run{stop=function()log[#log+1]='stop'end,saves={{'first',function()log[#log+1]='first';return true end},{'failed',function()return nil,'disk'end}},finish=function()error('must not finish')end}
check(not ok);eq(table.concat(log,','),'stop,first')
check(shutdown.run{stop=function()end,saves={{'ok',function()return true end}},finish=function()log[#log+1]='finish'end});eq(log[#log],'finish')
-- Actual Home -> NO remains running; YES only queues main-thread shutdown.
s=fixture({productionWindows=true,demo=false});s.step();s.page('home')
click(s,'Отключить PA##home');check(s.workspace.studio:hasModal());eq(s.unloadCalls,nil)
click(s,'НЕТ — отмена##confirm-no');check(not s.workspace.studio.shutdownConfirm);check(not s.frames[1].removed)
click(s,'Отключить PA##home');click(s,'ДА — отключить PA##confirm-yes');eq(s.unloadCalls,nil)
s.step();check(s.frames[1].removed);eq(s.unloadCalls,nil,'Unload belongs to the following main tick')
s.step();eq(s.unloadCalls,1);s.step();eq(s.unloadCalls,1);eq(#s.sent,0);healthy(s)
onWindowMessage(0x100,0x49);eq(s.unloadCalls,1);onScriptTerminate(s.script)
-- Failed persistence leaves subscriptions and hooks loaded for an explicit retry.
s=fixture({productionWindows=true,demo=false});s.step();s.page('home')
local knowledge=s.knowledgeUi.knowledge
local original=knowledge.flush;knowledge.flush=function()return nil,'Injected write failure'end
click(s,'Отключить PA##home');click(s,'ДА — отключить PA##confirm-yes');s.step()
check(not s.frames[1].removed);eq(s.unloadCalls,nil);check(s.workspace.studio:hasWarning());eq(#s.sent,0)
knowledge.flush=original;onScriptTerminate(s.script)
