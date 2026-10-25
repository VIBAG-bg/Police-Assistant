local mod=require 'pa26_nearby';local model=require 'pa26_bindings';local core=require 'pa26_core'
local function setup()
    local s={cfg=mod.defaults(),now=1000,scans=0,picks={},state={session='server',ped=1,interior=0,alive=true,focused=true,paused=false,blocked=false,nearbyOpen=true},
        all={{id=4,ped=40,name='Near_One',distance=3},{id=5,ped=50,name='Rider_Two',distance=5},{id=6,ped=60,name='Far_Three',distance=21}}}
    local n=mod.new({settings=function()return s.cfg end,scan=function()s.scans=s.scans+1;if s.error then error('failure')end;return s.all end,
        resolve=function(t,distance)for _,r in ipairs(s.all)do if not s.hidden and r.id==t.id and r.ped==t.ped and r.name==t.name and r.distance<=distance then return r end end end,
        select=function(t)s.picks[#s.picks+1]=t;return true end})
    function s.tick(ms)s.now=s.now+(ms or 0);n:tick(s.state,s.now)end
    s.tick();return n,s
end
local n,s=setup();eq(#n:view().rows,2);eq(n:view().rows[1].id,4);eq(s.scans,1)
local stable=n:view().rows[1];local id=mod.buttonId(stable);stable.distance=4.5;eq(mod.buttonId(stable),id,'Movement cannot change a button identity')
stable.ped=41;check(mod.buttonId(stable)~=id,'A new actor must have a new button identity')
for i=1,30 do s.tick(10)end;eq(s.scans,1,'Poll is cached, not per frame');s.tick(200);eq(s.scans,2)
local view=n:view();check(n:request(view.rows[2],view.revision));eq(#s.picks,0,'Renderer request must not inspect or select immediately')
s.tick(16);eq(#s.picks,1);eq(s.picks[1].id,5)
local copy=n:view();copy.rows[1].name='Mutation';eq(n:view().rows[1].name,'Near_One')
for _,reason in ipairs({'name','ped','quit','wall','far','interior','session','closed','modal','focus','paused','blocked','dead'})do
    n,s=setup();view=n:view();check(n:request(view.rows[1],view.revision))
    if reason=='name'then s.all[1].name='Reused_ID'elseif reason=='ped'then s.all[1].ped=41
    elseif reason=='quit'then n:invalidate(4)elseif reason=='wall'then s.hidden=true elseif reason=='far'then s.all[1].distance=100
    elseif reason=='interior'then s.state.interior=1 elseif reason=='session'then s.state.session='other'
    elseif reason=='closed'then s.state.nearbyOpen=false elseif reason=='modal'then s.state.modal=true
    elseif reason=='focus'then s.state.focused=false elseif reason=='paused'then s.state.paused=true
    elseif reason=='blocked'then s.state.blocked=true else s.state.alive=false end
    s.tick(16);eq(#s.picks,0,reason)
end
n,s=setup();view=n:view();n:invalidate(4);s.tick(500);check(not n:request(view.rows[1],view.revision),'Reused same ID/name/ped cannot restore a stale click')
n,s=setup();s.all={};for i=1,40 do s.all[i]={id=i,ped=100+i,name='Player_'..i,distance=i%10}end
s.tick(500);eq(#n:view().rows,8);eq(n:view().rows[1].id,10);eq(n:view().total,40)
local previous=n:view();s.cfg.distance=10;s.tick();check(not n:request(previous.rows[1],previous.revision),'Settings changes retire the old list')
s.cfg.enabled=false;s.tick();eq(#n:view().rows,0)
n,s=setup();s.error=true;s.tick(500);eq(#n:view().rows,0);eq(#s.picks,0)
local defaults=model.defaults(core.defaults());check(not defaults.bindings[3].enabled);check(not defaults.bindings[3].script:find('/wanted',1,true))
local personal=model.copy(defaults);personal.bindings[3].enabled=true;personal.bindings[3].script='/wanted {id}';personal.bindings[3].skip_confirmation=true;personal.nearby=nil
local upgraded=assert(model.validate(personal,core.defaults()));eq(upgraded.bindings[3].script,'/wanted {id}');check(upgraded.bindings[3].enabled);check(upgraded.bindings[3].skip_confirmation);check(upgraded.nearby.enabled)
eq(#require('pa26_server_commands').bindingWarnings(upgraded.bindings[3]),1)
for _,bad in ipairs({false,'true',1})do local c=mod.defaults();c.enabled=bad;if type(bad)~='boolean'then check(not mod.validate(c))end end
for _,field in ipairs({'distance','max_people','interval_ms'})do local c=mod.defaults();c[field]=0/0;check(not mod.validate(c))end
-- Real UI/main(): one click, no server sends, native revalidation next tick.
local fixture=require 'support.fixture';local f=fixture({demo=false});f.step();f.page('binds');f.step(550)
local list=f.workspace.library.nearby;check(list.enabled)
check(table.concat(f.drawnText,'\n'):find('Люди рядом',1,true))
local function buttonLabel(f)
    for i=#f.buttonCalls,1,-1 do local label=f.buttonCalls[i].label
        if label:find('Player_Name [37]',1,true)==1 and label:find('###nearby-',1,true)then return label end
    end
    error('Visible player button not rendered')
end
local label=buttonLabel(f)
f.click=label;f.render();eq(f.click,nil);eq(#f.sent,0);check(not f.workspace.selectedTarget)
f.step(16);check(f.workspace.selectedTarget);eq(f.workspace.selectedTarget.id,37);eq(#f.sent,0)
-- A stale cached button cannot select an actor hidden between rendering and main.
f.onScreen=false;f.click=label;f.render();f.workspace:clearTarget('manual');f.step(16);check(not f.workspace.selectedTarget);eq(#f.sent,0)
f.onScreen=true;f.step(550);f.page('settings');f.click='Доступ##settings-tab-options';f.render();eq(f.click,nil)
f.toggle='Показывать видимых людей рядом##nearby-enabled';f.render();f.step(700);check(not f.workspace.library.nearby.enabled)
local saved=f.savedLibrary();check(not saved.nearby.enabled)
check(not f.hasLog('Ошибка интерфейса'));eq(#f.scopes,0);eq(f.invalidIOReads,0);eq(#f.sent,0)
onScriptTerminate(f.script)
-- A spawn with the same player handle/session must retire an old UI click.
f=fixture({demo=false});f.step();f.page('binds');f.step(550)
f.click=buttonLabel(f);f.render();eq(f.click,nil)
f.events.onSendSpawn();f.step(16);check(not f.workspace.selectedTarget);eq(#f.sent,0)
onScriptTerminate(f.script)
