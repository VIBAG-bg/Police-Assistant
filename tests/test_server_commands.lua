local catalog=require 'pa26_server_commands'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local fixture=require 'support.fixture'
eq(#catalog.commands,41);local seen={}
for _,r in ipairs(catalog.commands)do check(not seen[r[1]]);seen[r[1]]=true;check(core.validUtf8(r[2]))end
eq(catalog.find('/find')[2],'Посмотреть онлайн фракции');eq(catalog.find('/r')[2],'Рация подразделения');eq(catalog.find('/f')[2],'Рация организации')
check(catalog.find('/taser'));check(not catalog.find('/tazer'));eq(catalog.procedureHeads.fine,'/ticket')
check(catalog.find('/wanted'));check(catalog.find('/su'));check(catalog.find('/pt'));check(catalog.find('/setmark'))
local lib=model.defaults(core.defaults());eq(lib.taser.command,'/taser')
for _,key in ipairs({'wanted','mark'})do eq(lib.procedures[key..'_command'],'');check(not lib.procedures[key..'_verified'])end
eq(lib.procedures.fine_command,'/ticket {id} {amount} {basis}');check(lib.procedures.fine_verified)
lib.alerts.channel='/f';lib.alerts.patrol.police_channel='/f';lib.alerts.patrol.prison_channel='/f'
lib.patrol_session.channel='/f';lib.vehicle.channel='/f'
for _,r in ipairs(lib.patrol_events.items or {})do r.channel='/f'end
for _,r in ipairs(lib.radio_guard.custom)do r.channel='/f'end
local clean,err=model.validate(lib,core.defaults());check(clean,err);eq(clean.alerts.channel,'/f');eq(clean.vehicle.channel,'/f')
local guard=require 'pa26_radio_guard';local c=model.copy(clean.radio_guard)
local radio=require 'pa26_radio_text';local p=assert(radio.prepare('/f','Проверка связи.',codec,c));eq(p.lines[1],'/f Проверка связи.')
lib.taser.command='/tazer';lib.taser.activation='weapon';check(#catalog.audit(lib)>0)
local s=fixture({demo=false,library=lib});s.step();require('support.ui_routes').chat(s,'commands');require('support.ui_routes').click(s,'Справка и сверка серверных команд##chat-server-reference')
check(table.concat(s.drawnText,'\n'):find('/ticket',1,true))
s.click='Взять имя /taser из справки##server-apply-taser';s.render();s.step(700);eq(s.click,nil)
eq(s.workspace.library.taser.command,'/taser');eq(s.workspace.library.taser.activation,'weapon','Changing a name must not assume activation semantics')
eq(#s.sent,0);eq(#s.localChat,0);check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(s.invalidIOReads,0);eq(#s.scopes,0)
onScriptTerminate(s.script)
