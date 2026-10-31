local model=require 'pa26_bindings';local core=require 'pa26_core';local M=require 'pa26_manual_actions'
local fixture=require 'support.fixture'
local function setup(demo,gender)
 local lib=model.defaults(core.defaults());lib.profile.gender=gender or'male'
 local s=fixture({productionWindows=true,demo=demo==true,library=lib});s.step()
 if s.frames[1].condition()then s.commands.pa26();s.step()end
 return s
end
local function offer(s)
 s.chat=true;s.chatText='/mask';s.step();onWindowMessage(0x100,13)
 eq(s.events.onSendCommand('/mask'),false);s.chat=false
 for _=1,4 do s.step(200)end;s.render();check(s.workspace.studio.manualAction);eq(#s.sent,0)
 s.click='ДА — отыграть RP и выполнить##confirm-yes';s.render()
 for _=1,18 do s.step(500)end;s.render()
end
for _,gender in ipairs({'male','female'})do
 local s=setup(false,gender);offer(s)
 local text={};for _,row in ipairs(s.sent)do text[#text+1]=row.line end;text=table.concat(text,'\n')
 check(text:find(gender=='male'and'расправил'or'расправила',1,true));eq(s.sent[#s.sent].line,'/mask')
 local p=s.workspace.studio.manualAction;check(p and p.cleanup,'Final command needs a separate confirmation')
 local before=#s.sent;for _=1,4 do s.step(1500)end;eq(#s.sent,before)
 s.render();s.click='ДА — передать команду завершения##confirm-yes';s.render()
 for _=1,5 do s.step(1500)end
 eq(s.sent[#s.sent].line,'/offobject');eq(#s.sent,before+1)
 check(not s.hasLog('Ошибка интерфейса'));eq(s.invalidIOReads,0);onScriptTerminate(s.script)
end
for _,decision in ipairs({'no','escape','session','focus','demo'})do
 local s=setup(decision=='demo');offer(s);local before=#s.sent
 if decision=='no'then s.click='НЕТ — закончить без команды##confirm-no';s.render()
 elseif decision=='escape'then s.workspace.studio:cancelModal()
 elseif decision=='session'then s.address='other'
 elseif decision=='focus'then onWindowMessage(0x8,0)
 else eq(#s.sent,0)end
 for _=1,8 do s.step(1500)end
 eq(#s.sent,before,decision);onScriptTerminate(s.script)
end
local cfg=M.defaults();eq(cfg.mask_delay_ms,700);check(M.validate(cfg))
cfg.mask_delay_ms=-1;check(not M.validate(cfg));cfg.mask_delay_ms=700;cfg.mask_cleanup_command='/mask';check(not M.validate(cfg))
local lib=model.defaults(core.defaults());lib.settings.manual_actions.rules.mask.enabled=false
check(not M.rule(lib,'mask'),'Disabled RP preserves ordinary server /mask')
local back=assert(require('pa26_user_files').combine(require('pa26_user_files').partition(lib),core.defaults()))
check(not back.settings.manual_actions.rules.mask.enabled)
-- Exercise acknowledgement/cancellation separately from renderer and executor mocks.
for _,outcome in ipairs({'cancelled','no-emission','completed','reload','changed-session','failed-start'})do
 local now=1000;local state={session='test',demo=false,ped=1,localId=1,nick='Officer',alive=true,focused=true,paused=false,blocked=false}
 local shown,started;local live=model.defaults(core.defaults());local control
 local env={codec=codec,now=function()return now end,epoch=function()return 1 end,revision=function()return 1 end,library=function()return live end,
  state=function()return state end,busy=function()return false end,account=function()end,accountValid=function()return true end,notice=function()end,
  show=function(p)shown=p.token end,showing=function(token)return shown==token end,close=function()shown=nil end,
  prepare=function(p)local plan={steps={{kind='message',text=p.raw,wire=p.raw}},lines={p.raw}};return plan,nil,plan end,
  start=function(plan)started=plan;return outcome~='failed-start'end}
 control=M.new(env);check(control:offer('/mask'));control:tick();local token=control.pending.token
 check(control:decide(token,true));check(not control:decide(token,true));control:tick()
 local q={plan=started}
 if outcome~='no-emission'then control:onExecution('sent_line',q,'/mask')end
 if outcome=='cancelled'then control:onExecution('cancelled',q)end
 control:onExecution('completed',q);control:onExecution('completed',q)
 if outcome=='completed'or outcome=='reload'or outcome=='changed-session'then
  check(control.cleanupWait);local finalToken=control.cleanupWait.proposal.token;now=1699;control:tick();check(not control.pending)
  if outcome=='reload'then control=M.new(env)
  elseif outcome=='changed-session'then state.session='other'end
  now=1700;control:tick()
  if outcome=='completed'then check(control.pending and control.pending.token==finalToken);check(control:decide(finalToken,false));control:tick();check(not control.pending)
  else check(not control.pending);check(not control.cleanupWait)end
 else check(not control.cleanupWait)end
end
