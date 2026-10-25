local core=require'pa26_core';local model=require'pa26_bindings';local target=require'pa26_target'
local ctx={session='A',alive=true,focused=true,paused=false,blocked=false,window=false}
local settings={aim_select_enabled=true,aim_select_delay_ms=150}
local held=false;local now=1000;local person={id=37,ped=99,name='Rider'};local picks={};local reads=0
local env={down=function()return held end,acquire=function()reads=reads+1;return person end,
    select=function(t)picks[#picks+1]=t;return true end}
local a=target.aim(env)
local function step(ms,locked)now=now+(ms or 0);return a:tick(ctx,now,settings,locked)end
step();held=true;check(not step());check(not step(149));eq(reads,0);check(step(1));eq(#picks,1)
person={id=38,ped=100,name='Passenger'};step(5000);eq(#picks,1,'one person per hold')
held=false;step();held=true;step();check(step(150));eq(picks[2].id,38)
for _,field in ipairs({'blocked','paused','window'})do
    held=false;step();held=true;step();ctx[field]=true;step(200);ctx[field]=false;step(200);eq(#picks,2,'blocked hold is not resumed')
end
for _,field in ipairs({'focused','alive'})do
    held=false;step();held=true;step();ctx[field]=false;step(200);ctx[field]=true;step(200);eq(#picks,2)
end
held=false;step();held=true;step();step(150,true);step(200);eq(#picks,2,'running actions lock selection until a new hold')
held=false;step();held=true;step();ctx.session='B';step(200);step(200);eq(#picks,2)
held=false;step();held=true;step();now=now-1000;step();step(200);eq(#picks,2,'timer reset requires a fresh press')
held=false;step();held=true;step();settings.aim_select_enabled=false;step(200);settings.aim_select_enabled=true;step(200);eq(#picks,2)
held=nil;step();held=true;step(200);eq(#picks,2)
held=false;step();held=true;step();person=nil;step(200);eq(#picks,2)
person={id=39,ped=101,name='Next'};check(step());eq(#picks,3,'waiting for a native target can recover while held')
held=false;step();held=true;step();env.acquire=function()error('unavailable')end;check(not step(200))
env.acquire=function()return{id=-1,ped=99,name='Bad'}end;check(not step());eq(#picks,3)
env.acquire=function()return person end;env.select=function()return false end;check(not step());eq(#picks,3)
env.select=function()error('selection unavailable')end;check(not step())
settings.aim_select_delay_ms=0;held=false;step();held=true;env.select=function(t)picks[#picks+1]=t;return true end
check(step());eq(#picks,4)
for _,value in ipairs({-1,2001,0/0,'bad',false})do
    held=false;step();settings.aim_select_delay_ms=value;held=true;check(not step(2500))
end

-- Old files gain the feature; explicit settings and custom bindings survive validation.
local seed=model.defaults(core.defaults());eq(seed.settings.aim_select_enabled,true);eq(seed.settings.aim_select_control,'mouse');eq(seed.settings.aim_select_delay_ms,150)
for _,key in ipairs({'aim_select_enabled','aim_select_control','aim_select_delay_ms'})do seed.settings[key]=nil end
seed.bindings[1].name='Мой бинд';local valid=assert(model.validate(seed,core.defaults()))
eq(valid.settings.aim_select_enabled,true);eq(valid.settings.aim_select_control,'mouse');eq(valid.settings.aim_select_delay_ms,150);eq(valid.bindings[1].name,'Мой бинд')
for _,bad in ipairs({false,'keyboard','',12})do local v=model.copy(valid);v.settings.aim_select_control=bad;check(not model.validate(v,core.defaults()))end
for _,bad in ipairs({false,-1,2001,1.5})do local v=model.copy(valid);v.settings.aim_select_delay_ms=bad;check(not model.validate(v,core.defaults()))end
valid.settings.aim_select_enabled=false;valid.settings.aim_select_control='game';valid.settings.aim_select_delay_ms=0
local reloaded=assert(model.validate(valid,core.defaults()));eq(reloaded.settings.aim_select_enabled,false);eq(reloaded.settings.aim_select_control,'game');eq(reloaded.settings.aim_select_delay_ms,0)

local fixture=require'support.fixture'
local function game(options)
    local f=fixture(options or{demo=false});f.step()
    if f.frames[1].condition()then f.commands.pa26()end
    f.step();return f
end
local function aim(f)
    f.down[2]=true;f.step(16);f.step(150)
end
local function release(f)f.down[2]=false;f.aimControl=false;f.step(16)end
-- No X: both bare hands and a weapon select the actual native-highlighted player.
-- The green marker may be away from screen center; no camera or player-pool sweep is used.
for _,weapon in ipairs({0,24})do for _,seated in ipairs({false,true})do
    local f=game();f.weapon=weapon;f.vehicle=seated;f.sx=100;f.aimControl=false
    aim(f);check(f.workspace.selectedTarget,'native-highlighted person was not selected');eq(f.workspace.selectedTarget.id,37)
    eq(f.poolReads,0);eq(#f.sent,0);eq(#f.localChat,0)
    release(f);f.step(300);eq(f.workspace.selectedTarget.id,37,'release retains the person')
    onScriptTerminate(f.script)
end end
-- The chosen ped may be the passenger. Never silently replace it by the driver.
local f=game();f.actors={
    [99]={id=37,name='Driver',x=0,y=5,z=0,sx=640,sy=360,vehicle=true},
    [100]={id=38,name='Passenger',x=1,y=5,z=0,sx=690,sy=360,vehicle=true}}
f.aimedPed=100;aim(f);eq(f.workspace.selectedTarget.id,38)
f.aimedPed=99;f.step(300);eq(f.workspace.selectedTarget.id,38)
release(f);aim(f);eq(f.workspace.selectedTarget.id,37);eq(#f.sent,0);onScriptTerminate(f.script)
-- Distant selection is separate from command range: no command can use a stale/far target.
f=game();f.distance=15;f.vehicle=true;aim(f);eq(f.workspace.selectedTarget.id,37)
f.step(300);eq(f.workspace.targets.state,'out_of_range')
f.commands.pa26run('1');f.step(2000);eq(#f.sent,0);onScriptTerminate(f.script)
for _,failure in ipairs({'wall','far','unstreamed','npc','hidden','dead'})do
    f=game();f.vehicle=true
    if failure=='no-native-target'then f.aimed=false elseif failure=='wall'then f.clear=false
    elseif failure=='far'then f.distance=41 elseif failure=='unstreamed'then f.streamed=false
    elseif failure=='npc'then f.npc=true elseif failure=='hidden'then f.onScreen=false else f.targetDead=true end
    aim(f);eq(f.workspace.selectedTarget,nil,failure);check(f.poolReads<=2);eq(#f.sent,0);onScriptTerminate(f.script)
end
f=game();f.aimed=false;aim(f);check(f.workspace.selectedTarget,'friendly player without native weapon lock');eq(#f.sent,0);onScriptTerminate(f.script)
-- Opening CEF/native input while held consumes that gesture, even after input closes.
f=game();f.down[2]=true;f.step(16);f.chat=true;f.step(200);f.chat=false;f.step(200)
eq(f.workspace.selectedTarget,nil);release(f);aim(f);eq(f.workspace.selectedTarget.id,37);onScriptTerminate(f.script)
f=game();local bridge=f.chatBridge
local function cef(chat)check(bridge:exchange(encodeJson({schema=1,page='aim',chat=chat,dialog=false,busy=chat,events={}}),f.now))end
cef(true);aim(f);eq(f.workspace.selectedTarget,nil);cef(false);f.step(200);eq(f.workspace.selectedTarget,nil)
release(f);aim(f);eq(f.workspace.selectedTarget.id,37);onScriptTerminate(f.script)
-- Remapped game aim input is selectable, and does not require the mouse button.
local lib=model.defaults(core.defaults());lib.settings.aim_select_control='game'
f=game({demo=false,library=lib});f.aimControl=true;f.step(16);f.step(150)
check(f.workspace.selectedTarget);eq(f.workspace.selectedTarget.id,37);eq(f.down[2],nil);onScriptTerminate(f.script)
-- The Russian settings toggle persists without changing the user's profile or bindings.
f=game();f.commands.pa26();f.page('settings');f.buttonCalls={};f.render()
-- Get the actual options label from the rendered tab row; do not guess its visible wording.
for _,b in ipairs(f.buttonCalls)do if b.label:find('##settings-tab-options',1,true)then f.click=b.label end end
f.render();f.toggle='Выбирать человека при удержании ПКМ##aim-select';f.render();f.step(650)
local saved=f.savedLibrary()
eq(saved.settings.aim_select_enabled,false);eq(assert(model.validate(saved,core.defaults())).settings.aim_select_enabled,false)
local slider=f.imgui.SliderInt
f.imgui.SliderInt=function(label,value,minimum,maximum)
    if label=='Удержание перед выбором, мс'then eq(minimum,0);eq(maximum,2000);value[0]=450;return true end
    if label=='Дальность выбора и сохранения, м'then eq(minimum,20);eq(maximum,200);value[0]=60;return true end
    if label=='Перерыв стрима, мс'then eq(minimum,500);eq(maximum,5000)end
    return slider(label,value,minimum,maximum)
end
f.render();f.imgui.SliderInt=slider;f.step(650)
saved=f.savedLibrary()
eq(saved.settings.aim_select_delay_ms,450);eq(saved.settings.retain_distance,60);check(model.validate(saved,core.defaults()))
f.toggle='Выбирать человека при удержании ПКМ##aim-select';f.render();f.step(650)
saved=f.savedLibrary();eq(saved.settings.aim_select_enabled,true)
onScriptTerminate(f.script)
