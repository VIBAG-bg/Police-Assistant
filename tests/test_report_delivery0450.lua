local executor=require 'pa26_executor'
local prefs=require 'pa26_preferences'
local cfg=prefs.radioGuardDefaults()
local state={session='server',alive=true,focused=true,paused=false,blocked=false,window=false,chatActive=false,dialogActive=false}
local now=1000;local last;local sent={};local events={}
local env={now=function()return now end,context=function()return state end,demo=function()return false end,
 reportDelivery=function()return cfg end,lastSent=function()return last end,markSent=function(v)last=v end,
 send=function(wire)sent[#sent+1]=wire;return true end,event=function(kind,q,why)events[#events+1]={kind=kind,why=why}end,
 planValid=function()return true end}
local e=executor.new(env)
local function plan()
 return {binding={name='Patrol'},steps={{kind='message',text='/f first',wire='/f first'},{kind='message',text='/f ...second',wire='/f ...second'},
  {kind='message',text='/f ...third',wire='/f ...third'}},requirements={},demo=false,session='server',createdAt=now,automatic={kind='patrol_session'},patrolSession={token='p'}}
end
check(e:start(plan(),false,1000));e:step();eq(#sent,1)
now=2000;state.blocked=true;state.chatActive=true;e:step()
check(e.queue,'Opening chat after line one must retain the unsent tail')
eq(#sent,1)
now=2500;state.blocked=false;state.chatActive=false;e:step();eq(#sent,2)
now=3500;e:step();eq(#sent,3);eq(e.queue,nil)
eq(sent[1],'/f first');eq(sent[2],'/f ...second');eq(sent[3],'/f ...third')
-- A new server, real death, user cancellation, a modal or ambiguous send failure must never replay.
now=5000;last=nil;check(e:start(plan(),false,1000));e:step();state.blocked=true;state.chatActive=true;state.dialogActive=true
now=6000;e:step();eq(e.queue,nil);check(e.status:find('1 / 3',1,true),'Partial delivery must report exact progress')
state.dialogActive=false;state.chatActive=false;state.blocked=false
now=7000;last=nil;check(e:start(plan(),false,1000));e:step();state.blocked=true;state.chatActive=true;now=8000;e:step()
now=8000+cfg.radio_resume_ms+1;e:step();eq(e.queue,nil)
state.chatActive=false;state.blocked=false;now=30000;last=nil
check(e:start(plan(),false,1000));e:step();state.chatActive=true;state.blocked=true;now=31000;e:step()
state.session='new-server';now=32000;e:step();eq(e.queue,nil);state.session='server'
state.chatActive=false;state.blocked=false
cfg.resume_radio_batches=false;now=40000;last=nil;check(e:start(plan(),false,1000));e:step();state.chatActive=true;state.blocked=true;now=41000;e:step();eq(e.queue,nil)
cfg.resume_radio_batches=true
local clean=assert(prefs.validateRadioGuard(cfg));eq(clean.radio_resume_ms,cfg.radio_resume_ms)
local bad=require('pa26_bindings').copy(cfg);bad.radio_resume_ms=0;check(not prefs.validateRadioGuard(bad))
for _,cause in ipairs({'focus','death','cancel','failure'})do
 state.chatActive=false;state.blocked=false;state.focused=true;state.alive=true;now=now+10000;last=nil
 check(e:start(plan(),false,1000));e:step();local before=#sent
 if cause=='focus'then state.focused=false elseif cause=='death'then state.alive=false
 elseif cause=='cancel'then e:cancel('manual')else env.send=function()return false end end
 now=now+1000;e:step();eq(e.queue,nil);eq(#sent,before)
end
state.focused=true;state.alive=true;env.send=function(w)sent[#sent+1]=w;return true end
now=now+10000;last=nil;cfg.radio_gap_ms=3000;check(e:start(plan(),false,1000));e:step();local before=#sent
now=now+1000;e:step();eq(#sent,before);now=now+2000;e:step();eq(#sent,before+1);e:cancel('done')
state.chatActive=false;state.blocked=false;state.focused=true;cfg.radio_gap_ms=1000;last=nil;now=now+10000
local f4=plan();f4.patrolSession=nil;f4.copilotAction={token='f4',routineRadio=true}
check(e:start(f4,false,1000));e:step();local count=#sent
state.chatActive=true;state.blocked=true;now=now+1000;e:step();check(e.queue);eq(#sent,count)
state.chatActive=false;state.blocked=false;now=now+1000;e:step();eq(#sent,count+1);e:cancel('done')
