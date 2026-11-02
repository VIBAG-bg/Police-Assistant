local M=require 'pa26_custody_reports';local prefs=require 'pa26_custody_settings'
local model=require 'pa26_bindings';local equal=require('pa26_author_presets').equal
local function fixture()
 local f={now=100,cfg=prefs.defaults(),plans={},notes={},names={[7]={name='Other_Person',connected=true,generation=1}},reads=0}
 f.state={session='one',ped=1,alive=true,focused=true,paused=false,blocked=false,demo=false,onDuty=true,radioEnabled=true,
  typing=false,modal=false,unit='1-L-7',location='Ganton (H-18)',area='Ganton',local_tag='',gender='male',my_nick='Officer_Demo',
  radioText={split_enabled=true,continuation='...',max_lines=3},rpText=require('pa26_rp_settings').defaults()}
 f.c=M.new({settings=function()return f.cfg end,equal=equal,codec=codec,values=function(s)return model.copy(s)end,
  identity=function(id)f.reads=f.reads+1;return model.copy(f.names[id])end,
  start=function(p)check(f.c:validPlan(p));f.plans[#f.plans+1]=p;return not f.fail,'send failed'end,
  notice=function(n)f.notes[#f.notes+1]=n end,cancel=function()f.cancelled=true end})
 function f.tick(ms)f.now=f.now+(ms or 16);f.c:tick(f.state,f.now)end
 function f.yes()local p=f.c.offers[1];check(p);f.c:shown(p.token);check(f.c:decide(p.token,true));f.tick();return f.plans[#f.plans]end
 f.tick(0);return f,f.c
end
check(prefs.validate(nil));check(not prefs.validate(false))
for _,edit in ipairs({function(p)p.detention.channel='/cuff'end,function(p)p.jail.template='/arrest 7'end,
 function(p)p.detention.template='{unknown}'end,function(p)p.toast_ms=0 end,function(p)p.ttl_ms=1000 end,
 function(p)p.queue_limit=999 end,function(p)p.enabled='true'end,function(p)p.hint='\n'end})do
 local p=prefs.defaults();edit(p);check(not prefs.validate(p))
end
local f,c=fixture()
check(c:observe('/cuff 7'));eq(#c.offers,1);eq(#f.plans,0,'No send until Y')
local p=c.offers[1];check(p.prepared.line:find('10-15',1,true));check(p.prepared.line:find('один подозреваемый',1,true))
check(not p.prepared.line:find('Other_Person',1,true),'Nickname is not IC identity');check(not p.prepared.line:find('/cuff',1,true))
check(not c:decide(p.token,true),'Unpainted toast is not accepted');c:shown(p.token);check(c:decide(p.token,false));f.tick();eq(#f.plans,0)
for _,line in ipairs({'/cuff','/cuff abc','/cuff -1','/cuff 1000000','/cuff 7x',' /cuff 7','/r /cuff 7','/cuff 7\n/r hi','/arrest 7\0','/cuffevil 7'})do
 f,c=fixture();check(not c:observe(line),line);eq(#c.offers,0)
end
f,c=fixture();check(c:observe('/CUFF 7'));check(not c:observe('/cuff 7'));eq(#c.offers,1);eq(#f.plans,0)
local plan=f.yes();check(plan);eq(#c.offers,0);eq(#f.plans,1)
for _,step in ipairs(plan.steps)do check(step.text:match('^/f '));check(not step.text:find('/cuff',1,true))end
check(not c:decide(p.token,true),'Old token cannot resend')
for i=1,#plan.steps do c:onExecution('sent_line',{plan=plan,index=i});end;eq(c.queued,nil)
f.tick();eq(#f.plans,1)
f,c=fixture();check(c:observe('/cuff 7'));check(c:observe('/arrest 7 5'))
eq(#c.offers,1,'New jail event supersedes an unconfirmed cuff offer for the same ID');eq(c.offers[1].kind,'jail')
check(c.offers[1].prepared.line:find('КПЗ',1,true));check(not c.offers[1].prepared.line:find('10-19',1,true))
f.yes();eq(#f.plans,1)
f,c=fixture();check(c:observe('/cuff 7'));check(not c:observe('/uncuff 7'));eq(#c.offers,0);check(c:observe('/cuff 7'))
f,c=fixture();f.state.busy=true;check(c:observe('/cuff 7'));p=c.offers[1];c:shown(p.token);check(c:decide(p.token,true))
check(not c:observe('/uncuff 7'));f.state.busy=false;f.tick();eq(#f.plans,0,'Uncuff also cancels an accepted report waiting for the executor')
for _,key in ipairs({'typing','modal','blocked','recording','editingHud','draggingHud','alertPending'})do
 f,c=fixture();check(c:observe('/arrest 7'));p=c.offers[1];c:shown(p.token);f.state[key]=true
 check(not c:decide(p.token,true),key);f.tick(30000);eq(#f.plans,0);eq(p.remaining,f.cfg.toast_ms,'Hidden time not spent: '..key)
 f.state[key]=false;f.tick();c:shown(p.token);check(c:decide(p.token,true));f.tick();eq(#f.plans,1)
end
for _,key in ipairs({'session','ped','alive','demo','focused','paused','onDuty','radioEnabled','name','generation','cfg','unit'})do
 f,c=fixture();check(c:observe('/arrest 7'));p=c.offers[1];c:shown(p.token)
 if key=='name'then f.names[7].name='ID_Reused'
 elseif key=='generation'then f.names[7].generation=2
 elseif key=='cfg'then f.cfg.jail.template='Изменённый доклад'
 elseif key=='session'then f.state.session='two'
 elseif key=='ped'then f.state.ped=2
 elseif key=='unit'then f.state.unit='1-A-7'
 elseif key=='alive'or key=='focused'or key=='onDuty'or key=='radioEnabled'then f.state[key]=false
 else f.state[key]=true end
 f.tick();check(not c:decide(p.token,true),key);eq(#f.plans,0)
end
f,c=fixture();f.state.typing=true;f.state.blocked=true;f.tick();check(c:observe('/cuff 7'),'The submitted command is observed before chat closes')
eq(#f.plans,0);f.state.typing=false;f.state.blocked=false;f.tick();f.yes();eq(#f.plans,1)
f,c=fixture();f.state.demo=true;f.tick();check(not c:observe('/cuff 7'));check(not c:create('jail'));eq(#f.plans,0)
f,c=fixture();check(c:observe('/cuff 7'));c:invalidate(7);eq(#c.offers,0)
f,c=fixture();check(c:observe('/cuff 7'));f.tick(f.cfg.ttl_ms);eq(#c.offers,0)
f,c=fixture();check(c:observe('/cuff 7'));p=c.offers[1];c:shown(p.token);f.tick(1000);eq(p.remaining,f.cfg.toast_ms-1000)
f,c=fixture();f.state.busy=true;check(c:observe('/arrest 7'));p=c.offers[1];c:shown(p.token);check(c:decide(p.token,true));f.tick();eq(#f.plans,0)
f.state.busy=false;f.tick();eq(#f.plans,1);c:onExecution('cancelled',{plan=f.plans[1]});f.tick();eq(#f.plans,1)
f,c=fixture();f.cfg.enabled=false;f.tick();check(not c:observe('/cuff 7'));eq(#c:candidates(),0)
f,c=fixture();for i=1,4 do check(c:observe('/cuff '..i))end;check(not c:observe('/cuff 5'));eq(#c.offers,4)
f,c=fixture();check(c:create('detention',nil,'F4'));f.yes();eq(#f.plans,1,'F4 has the same Y/N route, without requiring a selected target')
f,c=fixture();check(c:observe('/cuff 7'));f.cfg=model.copy(f.cfg);f.tick();eq(#c.offers,1,'Saving equal preferences does not lose a prompt')
local calls=f.reads;for i=1,1000 do f.tick(1)end;eq(f.reads,calls,'Waiting for Y does not poll identities every frame')
f,c=fixture();check(c:observe('/cuff 7'));p=c.offers[1];c:shown(p.token);check(c:decide(p.token,true));f.cfg.enabled=false;f.tick();eq(#f.plans,0)
f,c=fixture();f.state.unit='evil\n/r text';check(not c:observe('/cuff 7'));eq(#f.plans,0)
f,c=fixture();f.cfg.jail.template=string.rep('д',700);check(not c:observe('/arrest 7'),'Wire/parts limits are preflighted');eq(#f.plans,0)
local before=require('pa26_patrol_event_settings').defaults();check(before.command_reports.enabled)
local legacy=model.copy(before);legacy.command_reports=nil;local loaded=assert(require('pa26_patrol_event_settings').validate(legacy));check(loaded.command_reports.enabled)
local payload=TEST_JSON_DECODE(TEST_JSON_ENCODE(loaded));eq(assert(require('pa26_patrol_event_settings').validate(payload)).command_reports.jail.template,loaded.command_reports.jail.template)
f,c=fixture();f.state.busy=true;check(c:observe('/cuff 7'));p=c.offers[1];c:shown(p.token);check(c:decide(p.token,true))
f.state.typing=true;f.tick();f.state.typing=false;f.state.busy=false;f.tick();eq(#f.plans,0,'Opening chat cancels an already accepted delayed send')
-- The actual main-script observers feed one shared controller; no F4 form is needed.
local fixture=require 'support.fixture'
local s=fixture({demo=false,render=false});s.step()
s.workspace.library.settings.manual_actions.enabled=false
s.workspace.library.alerts.on_duty=true;s.workspace.library.alerts.enabled=true;s.step()
s.events.onSendCommand('/cuff 7');eq(#s.custody.offers,1,'Native real RPC triggers the ready report')
s.chatBridge.env.command('/cuff 7');eq(#s.custody.offers,1,'Duplicate native/CEF observation is coalesced')
local token=s.custody.offers[1].token;s.custody:shown(token);check(s.custody:decide(token,false));eq(#s.custody.offers,0)
s.chatBridge.env.command('/arrest 7');eq(#s.custody.offers,1);eq(s.custody.offers[1].kind,'jail')
check(s.custody.offers[1].prepared.line:find('КПЗ',1,true));eq(#s.sent,0,'A ready toast does not send without Y')
token=s.custody.offers[1].token;s.custody:shown(token);check(s.custody:decide(token,true))
s.step(16,{[0x23]=true});check(not s.custody.intent and not s.custody.queued,'End cancels a confirmed report before its first line')
s.step(1500);eq(#s.sent,0,'End leaves no delayed radio transmission')
onScriptTerminate(s.script)
s=fixture({demo=true,render=false});s.step();s.events.onSendCommand('/cuff 7');eq(#s.custody.offers,0);onScriptTerminate(s.script)
