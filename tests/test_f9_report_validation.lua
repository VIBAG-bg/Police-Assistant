local fixture=require 'support.fixture'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local lib=model.defaults(core.defaults())
lib.profile.name='Victor Auditore';lib.profile.callsign='A-1'
lib.patrol_session.enabled=true;lib.patrol_session.unit='A-1'
lib.patrol_session.start_template='Мой патруль: {unit}, курс {direction}.'
lib.alerts.on_duty=true
local s=fixture({library=lib,alerts=true,notifications=true,categoryWheel=true})
s.step()
local c=s.patrolSession
c.state.direction=nil;c.state.directionKnown=false
s.page('partners')
s.click='Патруль##Напарники и служба##partners-pagepatrol';s.render()
check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'))
check(s.frames[1].condition(),'A normal preview warning must leave F9 available')
eq(#s.scopes,0);eq(s.invalidIOReads,0);eq(#s.sent,0)
local warning=false;for _,line in ipairs(s.drawnText)do if line:find('{direction}:',1,true)then warning=true end end
check(warning,'The affected preview must explain the missing direction')
eq(s.workspace.library.patrol_session.start_template,lib.patrol_session.start_template)
-- All five failed previews remain normal form text and keep independent drafts.
local studio=s.workspace.studio
local titles={start='Начало патруля',resume='Продолжение патруля',finish='Завершение патруля',crew='Смена экипажа',periodic='Периодический доклад'}
s.edits={}
for _,key in ipairs({'start','resume','finish','crew','periodic'})do
 local text='{unit}: личный '..key..', курс {direction}.'
 s.edits[titles[key]..'##session-template-'..key]=text
end
s.drawnText={};s.render();s.edits={}
local warnings=0;for _,line in ipairs(s.drawnText)do if line:find('{direction}:',1,true)then warnings=warnings+1 end end
eq(warnings,5,'Expected five independent warnings, got '..warnings);check(s.frames[1].condition());eq(#s.sent,0)
for _,key in ipairs({'start','resume','finish','crew','periodic'})do
 eq(studio.patrolSessionDraft[key..'_template'],'{unit}: личный '..key..', курс {direction}.')
end
-- A valid preview does not depend on the failed neighbour.
s.edits={['Завершение патруля##session-template-finish']='{unit}: смена завершена.'}
s.drawnText={};s.render();s.edits={};local valid=false
for _,line in ipairs(s.drawnText)do if line:find('/r 1-L-1: смена завершена.',1,true)or line:find('/r A-1: смена завершена.',1,true)then valid=true end end
check(valid);check(not s.hasLog('Ошибка интерфейса'))
s.click='Контакты##Напарники и служба##partners-pagecontacts';s.render();eq(s.click,nil)
s.page('settings');check(s.frames[1].condition());eq(#s.sent,0)
s.commands.pa26();s.render();check(not s.frames[1].condition())
s.commands.pa26();s.render();check(s.frames[1].condition())
s.page('partners');s.click='Патруль##Напарники и служба##partners-pagepatrol';s.render()
check(s.frames[1].condition());check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0);eq(s.invalidIOReads,0);eq(#s.sent,0)
-- Unexpected renderer failures still use the established recovery path.
s.widgetError=true;s.page('addons');s.render();check(not s.frames[1].condition());check(s.hasLog('Ошибка интерфейса'))
s.widgetError=false;s.commands.pa26repair();s.step();check(s.frames[1].condition());eq(#s.scopes,0);eq(#s.sent,0)
onScriptTerminate(s.script)
