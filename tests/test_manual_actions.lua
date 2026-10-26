local module=require 'pa26_manual_actions';local model=require 'pa26_bindings';local core=require 'pa26_core';local fixture=require 'support.fixture'
local cfg=module.defaults();check(cfg.enabled);check(cfg.rules.cuff and cfg.rules.setmark)
check(not cfg.rules.su and not cfg.rules.r and not cfg.rules.wanted)
for _,bad in ipairs({'/cuff 37','/r привет','/su 37','text','/me ok\n/clear 37'})do
 local copy=model.copy(cfg);copy.rules.cuff.rp=bad;check(not module.validate(copy),bad)
end
check(module.validate(cfg));cfg.rules.cuff.rp='/todo Текст для {param1}*обращаясь к задержанному.';check(module.validate(cfg))
check(module.preview(cfg.rules.cuff.rp):find('37',1,true))
local function setup(demo)
 local lib=model.defaults(core.defaults());lib.settings.manual_actions.rules.cuff.prefer_bind=false
 local s=fixture({productionWindows=true,demo=demo==true,library=lib});s.step()
 if s.frames[1].condition()then s.commands.pa26();s.step()end
 return s
end
local function offer(s,command)
 s.chat=true;s.chatText=command;s.step();onWindowMessage(0x100,13)
 eq(s.events.onSendCommand(codec.encode(command)),false,'Manual RPC must be held before any server send')
 s.chat=false;for _=1,4 do s.step(200)end;s.render()
 check(s.workspace.studio.manualAction,'Manual action confirmation missing');eq(#s.sent,0)
end
local function choose(s,yes)
 s.click=yes and'ДА — отыграть RP и выполнить##confirm-yes'or'НЕТ — выполнить сразу без RP##confirm-no';s.render()
 eq(s.click,nil);for _=1,22 do s.step(1500)end
 check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0)
end
for _,demo in ipairs({false,true})do for _,yes in ipairs({false,true})do
 local s=setup(demo);offer(s,'/cuff 37');choose(s,yes)
 if demo then eq(#s.sent,0)else
  eq(s.sent[#s.sent].line,'/cuff 37');local count=0
  for _,r in ipairs(s.sent)do if r.line=='/cuff 37'then count=count+1 else check(r.line:match('^/me ')or r.line:match('^/do '))end end
  eq(count,1);check(yes and #s.sent>1 or not yes and #s.sent==1)
 end
 onScriptTerminate(s.script)
end end
-- Escape cancels the original command as well. Disconnect and ID reuse must
-- invalidate the frozen target even when the typed ID is unchanged.
for _,change in ipairs({'escape','quit','reuse','settings','session','focus'})do
 local s=setup();offer(s,'/cuff 37')
 if change=='escape'then s.workspace.studio:cancelModal()
 elseif change=='quit'then s.targetConnected=false;s.events.onPlayerQuit(37)
 elseif change=='reuse'then s.name='Other_Person'
 elseif change=='settings'then local value=model.copy(s.workspace.library);value.settings.manual_actions.enabled=false;check(s.workspace:save(value))
 elseif change=='session'then s.address='10.0.0.2'
 else onWindowMessage(0x8,0)end
 if change~='escape'and change~='focus'then s.click='ДА — отыграть RP и выполнить##confirm-yes';s.render()end
 for _=1,8 do s.step(1600)end;eq(#s.sent,0,change);onScriptTerminate(s.script)
end
-- CEF uses a local event; retries of the same receipt cannot ask/send twice.
local s=setup();local packet={schema=1,page='manual-action-test',chat=false,dialog=false,busy=false,
 events={{id=1,kind='local',text='/cuff 37',session=s.chatBridge.env.session()}}}
check(s.chatBridge:exchange(encodeJson(packet),s.now));check(s.chatBridge:exchange(encodeJson(packet),s.now))
s.chatBridge:dispatch(s.now);for _=1,4 do s.step(200)end;s.render();check(s.workspace.studio.manualAction)
choose(s,false);eq(#s.sent,1);eq(s.sent[1].line,'/cuff 37')
check(s.chatBridge:exchange(encodeJson(packet),s.now));s.chatBridge:dispatch(s.now);s.step(1000);eq(#s.sent,1)
onScriptTerminate(s.script)
-- An alias seen as an RPC before the CEF command list refreshes still reaches
-- its local handler on the very first attempt, never the game server.
local aliasLib=model.defaults(core.defaults());aliasLib.bindings[1].command_alias='add';aliasLib.bindings[1].target_required=false
aliasLib.bindings[1].script='/me проверил служебный планшет.';aliasLib.bindings[1].skip_confirmation=true
s=fixture({demo=false,library=aliasLib});s.step();if s.frames[1].condition()then s.commands.pa26();s.step()end
eq(s.events.onSendCommand('/add'),false);for _=1,8 do s.step(1500)end
eq(#s.sent,1);eq(s.sent[1].line,'/me проверил служебный планшет.');onScriptTerminate(s.script)
-- Settings and editable RP survive saving through split user documents.
local lib=model.defaults(core.defaults());lib.settings.manual_actions.rules.cuff.rp='/me поправил наручники.'
local parts=require('pa26_user_files').partition(lib)
local back=assert(require('pa26_user_files').combine(parts,core.defaults()));eq(back.settings.manual_actions.rules.cuff.rp,'/me поправил наручники.')
s=setup();s.commands.pa26();s.render();require('support.ui_routes').chat(s,'commands')
s.edits={['##RP-шаблон · резерв при отсутствии подходящего бинда##manual-action-rp']='/me подготовил наручники.'};s.render();s.edits={}
s.toggle='Предлагать RP при ручном вводе команды##manual-actions-enabled';s.render();s.step(750)
eq(s.workspace.library.settings.manual_actions.enabled,false)
eq(s.savedLibrary().settings.manual_actions.rules.cuff.rp,'/me подготовил наручники.')
check(not s.hasLog('Ошибка интерфейса'));eq(#s.sent,0);onScriptTerminate(s.script)
