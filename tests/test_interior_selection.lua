local core=require 'pa26_core';local fixture=require 'support.fixture'
for _,own in ipairs({0,1,3,6,10,18,255})do
    check(core.pedAreaCompatible(own,0),'zero remote area must not imply outdoors')
    check(core.pedAreaCompatible(own,own))
    for _,remote in ipairs({1,3,6,10,18,255})do eq(core.pedAreaCompatible(own,remote),own==remote)end
end
for _,bad in ipairs({-1,256,0/0,1.5,'6',false})do
    check(not core.pedAreaCompatible(6,bad));check(not core.pedAreaCompatible(bad,0))
end
check(not core.pedAreaCompatible(nil,0));check(not core.pedAreaCompatible(6,nil))
local function setup(own,remote)
    local s=fixture({demo=false});s.localInterior=own;s.remoteInterior=remote;s.name='Officer_Interior'
    s.step();if s.frames[1].condition()then s.commands.pa26()end;s.step(16)
    return s
end
local function aim(s)
    s.down[2]=false;s.step(16);s.down[2]=true;s.step(16);s.step(170)
end
local function healthy(s)
    check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,' | '));eq(#s.scopes,0);eq(s.invalidIOReads,0)
end
local function chosen(s,why,expectedSent)
    check(s.workspace.selectedTarget,why);eq(s.workspace.selectedTarget.id,37)
    s.step(300);eq(s.workspace.targets.state,'available','retention must use the same interior rule')
    eq(#s.sent,expectedSent or 0,'sent='..#s.sent..', expected='..tostring(expectedSent));healthy(s)
end
-- Real main script: RMB with native lock, RMB gaze fallback, explicit ID and
-- both nearby controls. Every route must accept remote area 0 inside a room.
for _,area in ipairs({1,3,6,10,18})do
    for _,route in ipairs({'native','gaze','id','nearby-row','nearby-id'})do
        local s=setup(area,0)
        if route=='native'then aim(s)
        elseif route=='gaze'then s.aimed=false;aim(s)
        elseif route=='id'then s.commands.pa26select('37');s.step(16)
        else
            s.commands.pa26();s.page('binds');s.click='Выбрать игрока для проверки бинда##bind-target';s.render();s.step(550)
            if route=='nearby-id'then
                s.edits={['Выбрать игрока по ID##nearby-id']='37'};s.render();s.click='Выбрать по ID##nearby-select-id'
            else
                for i=#s.buttonCalls,1,-1 do
                    local label=s.buttonCalls[i].label
                    if label:find('Officer_Interior [37]',1,true)==1 and label:find('###nearby-',1,true)then s.click=label;break end
                end
                check(s.click,'officer missing from the interior nearby list')
            end
            s.render();eq(s.click,nil);s.step(16)
        end
        chosen(s,route..' in area '..area);onScriptTerminate(s.script)
    end
end
-- Streets and explicitly matching nonzero interiors retain their old behavior.
for _,areas in ipairs({{0,0},{6,6}})do
    local s=setup(areas[1],areas[2]);aim(s);chosen(s,'matching area');onScriptTerminate(s.script)
end
-- Unknown remote code is never a permission to select an invisible/obstructed
-- actor, an NPC, disconnected account, dead actor or one beyond selection range.
for _,failure in ipairs({'wall','offscreen','far','unstreamed','npc','dead','disconnected','known-mismatch','outdoor-mismatch'})do
    local s=setup(6,0)
    if failure=='wall'then s.clear=false elseif failure=='offscreen'then s.onScreen=false
    elseif failure=='far'then s.distance=41 elseif failure=='unstreamed'then s.streamed=false
    elseif failure=='npc'then s.npc=true elseif failure=='dead'then s.targetDead=true
    elseif failure=='disconnected'then s.targetConnected=false elseif failure=='known-mismatch'then s.remoteInterior=5
    elseif failure=='outdoor-mismatch'then s.localInterior=0;s.remoteInterior=6;s.step(16)end
    aim(s);check(not s.workspace.selectedTarget,failure);eq(#s.sent,0);healthy(s);onScriptTerminate(s.script)
end
-- Once selected indoors, a real RP bind still revalidates and uses that person.
local s=setup(6,0);aim(s);s.down[2]=false;s.step(16)
local model=require 'pa26_bindings';local lib=model.copy(s.workspace.library)
lib.bindings[1].target_required=true;lib.bindings[1].skip_confirmation=true
lib.bindings[1].script='/me проверил данные {select_name}.'
check(s.workspace:save(lib));s.commands.pa26run('1');s.step(16);s.step(100)
check(#s.sent==1,'interior target must also work during final bind revalidation')
check(s.sent[1].line:find('Officer Interior',1,true));healthy(s);onScriptTerminate(s.script)
-- Entering/leaving retains identity, never the pending action or UI gesture.
s=setup(6,0);aim(s);check(s.workspace.selectedTarget)
s.localInterior=7;s.streamed=false;s.step(16);check(s.workspace.selectedTarget)
eq(s.workspace.targets.state,'unavailable');check(s.workspace.targets.transition)
s.step(6000);check(s.workspace.selectedTarget,'unstreaming across a transition lost the person')
eq(s.workspace.targets.state,'unavailable');eq(#s.sent,0)
s.streamed=true;s.step(300);chosen(s,'same person after streaming');check(not s.workspace.targets.transition)
s.localInterior=0;s.step(16);chosen(s,'same person outdoors')
healthy(s);onScriptTerminate(s.script)
-- Old portal coordinates cannot erase or authorize the retained identity.
s=setup(6,0);aim(s);s.down[2]=false;s.step(16)
local lib=model.copy(s.workspace.library);lib.bindings[1].target_required=true;lib.bindings[1].skip_confirmation=true
lib.bindings[1].script='/me проверил данные {select_name}.\n@wait(2000)\n/me закончил проверку.'
local ok,err=s.workspace:save(lib);check(ok,err);s.commands.pa26run('1');s.step(16);s.step(100)
check(s.workspace.executor.queue,'expected queued RP: '..s.workspace.status..' / '..table.concat(s.logs,' | '))
s.localInterior=0;s.distance=3000;s.onScreen=false;s.step(16)
check(s.workspace.selectedTarget);check(not s.workspace.executor.queue);check(not s.workspace.pending)
local before=#s.sent;s.step(6000);eq(#s.sent,before);check(s.workspace.selectedTarget)
s.commands.pa26run('1');s.step(100);s.step(100);eq(#s.sent,before,'inaccessible retained target allowed an action');check(not s.workspace.pending)
s.distance=5;s.onScreen=true;s.step(300);chosen(s,'followed outside after old coordinates expired',before)
healthy(s);onScriptTerminate(s.script)
-- Invalid identity/life/session still clear selection during a transition.
for _,why in ipairs({'quit','join','identity','death','session','toggle-off'})do
    s=setup(6,0);aim(s)
    if why=='toggle-off'then
        local lib=model.copy(s.workspace.library);lib.settings.keep_target_on_interior_change=false;check(s.workspace:save(lib))
    end
    s.localInterior=0;s.streamed=false;s.step(16)
    if why=='quit'then s.events.onPlayerQuit(37)
    elseif why=='join'then s.events.onPlayerJoin(37)
    elseif why=='identity'then s.name='Other_Person';s.step(300)
    elseif why=='death'then s.localDead=true;s.step(300)
    elseif why=='session'then s.connected=false;s.step(300)end
    check(not s.workspace.selectedTarget,why);eq(#s.sent,0);healthy(s);onScriptTerminate(s.script)
end
s=setup(6,0);s.commands.pa26();s.page('binds');s.click='Выбрать игрока для проверки бинда##bind-target';s.render();s.step(550)
s.edits={['Выбрать игрока по ID##nearby-id']='37'};s.render();s.click='Выбрать по ID##nearby-select-id';s.render()
s.localInterior=7;s.step(16);check(not s.workspace.selectedTarget,'stale nearby click crossed interior boundary')
eq(#s.sent,0);healthy(s);onScriptTerminate(s.script)
