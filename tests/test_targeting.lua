-- Explicit legacy personal fixture: the fresh wanted example is disabled.
local support=require 'support.fixture'
local function fixture(options)options=options or{};options.legacyWanted=true;options.nearby=false;return support(options)end
local core=require 'pa26_core'

-- Reference geometry maps clockwise sectors to the actual saved actions.
for slot,index in ipairs({2,4,5,6,3,1}) do
    local angle=-math.pi/2+(slot-.5)*math.pi/3
    eq(core.radialAction(math.cos(angle)*150,math.sin(angle)*150,92,218),index)
end
eq(core.radialAction(0,0,92,218),nil)
eq(core.radialAction(92,0,92,218),nil)
eq(core.radialAction(219,0,92,218),nil)
eq(core.radialAction(0/0,0,92,218),nil)
eq(core.radialAction(0,150,0,218),nil)
eq(core.cameraScore(640,360,1280,720),0)
eq(core.cameraScore(0,360,1280,720),nil)
eq(core.cameraScore(640,360,0/0,720),nil)
eq(core.cameraScore(-1,360,1280,720),nil)
check(core.capturedTargetValid({id=0,ped=99,name='Player'}))
for _,target in ipairs({{}, {id=1004,ped=99,name='Player'}, {id=37,ped=0/0,name='Player'},
    {id=37,ped=99,name=''}, {id=37,ped=99,name=string.rep('a',25)}}) do check(not core.capturedTargetValid(target)) end

local function open(s)
    s.step(); s.commands.pa26()
    s.down[0x58]=true; s.step(16,{[0x58]=true})
    check(s.frames[2].condition()); eq(#s.sent,0)
end
local function noTarget(s,why)
    open(s)
    local text=table.concat(s.drawnText,'\n')
    check(text:find('Нет цели',1,true)~=nil,why)
    local scale=math.min(1,(s.io.DisplaySize.x-32)/600,(s.io.DisplaySize.y-32)/650)
    s.io.MousePos.x,s.io.MousePos.y=s.io.DisplaySize.x/2-156*scale,s.io.DisplaySize.y/2
    s.render(); s.down[0x58]=false; s.step(150); s.step(5000)
    eq(#s.sent,0,why); check(not s.frames[2].condition())
end

-- Plain camera gaze, no weapon/native-target result, identifies the visible player.
local s=fixture({demo=false}); s.aimed=false; s.liveAction()
eq(s.sent[1].line,'/me '..core.defaults().wanted.me)
check(table.concat(s.drawnText,'\n'):find('ID 37',1,true))
eq(s.poolReads,1,'scene must be scanned once on X, never every renderer/send tick')
s.step(1500); s.step(1500); eq(s.sent[3].line,'/wanted 37'); eq(s.poolReads,1)
s=fixture({demo=false}); s.aimed=false; s.torsoOnly=true; s.liveAction()
eq(#s.sent,1,'looking at the torso must work when the head is away from the center')
s=fixture({demo=false}); s.aimed=false; s.upperBlocked=true; s.liveAction()
eq(#s.sent,1,'a visible torso remains selectable when the upper point is blocked')

-- Seated players use the same identity/range locks. Glass is passed only by
-- the native transparent-material trace, with cars/buildings/objects enabled.
for _,aimed in ipairs({false,true}) do
    for _,glass in ipairs({false,true}) do
        s=fixture({demo=false}); s.aimed=aimed; s.vehicle=true; s.glass=glass
        s.liveAction(); check(table.concat(s.drawnText,'\n'):find('ID 37',1,true))
        eq(#s.sent,1); s.step(1500); s.step(1500); eq(s.sent[3].line,'/wanted 37')
        eq(s.transparentReads>0,glass)
    end
end

-- Leaving or entering a vehicle keeps the same visible person's ID.
for _,startsSeated in ipairs({false,true}) do
    s=fixture({demo=false}); s.aimed=false; s.vehicle=startsSeated; s.liveAction()
    s.vehicle=not startsSeated; s.step(1500); s.step(1500); eq(s.sent[3].line,'/wanted 37')
end

for _,failure in ipairs({'opaque','far','hidden','traceerror','tracenil','missingtrace','invalidvehicle'}) do
    s=fixture({demo=false}); s.aimed=false; s.vehicle=true; s.glass=true
    if failure=='opaque' then s.clear=false
    elseif failure=='far' then s.distance=20
    elseif failure=='hidden' then s.onScreen=false
    elseif failure=='traceerror' then s.traceError=true
    elseif failure=='tracenil' then s.traceNil=true
    elseif failure=='missingtrace' then processLineOfSight=nil
    elseif failure=='invalidvehicle' then isCharInAnyCar=function() return nil end end
    local before=s.remoteIdentityReads
    noTarget(s,'occupant '..failure)
    eq(s.remoteIdentityReads,before,'unseen seated player identity was read')
end
s=fixture({demo=false}); s.aimed=false; s.glass=true
noTarget(s,'foot target behind glass stays subject to the stricter foot check')
eq(s.transparentReads,0,'transparent-surface fallback is limited to occupants')
s=fixture({demo=false}); s.aimed=false; s.vehicle=true; s.glass=true; s.liveAction()
s.clear=false; s.step(1500); s.step(5000); eq(#s.sent,1,'opaque obstruction cancels a moving occupant queue')

-- Drivers and passengers are picked individually; no assumption that the
-- first occupant/driver of a vehicle is the person in the center.
s=fixture({demo=false}); s.aimed=false; s.pool={99,100}
s.actors={
    [99]={id=37,name='Driver',x=0,y=5,z=0,sx=690,sy=360,vehicle=true},
    [100]={id=38,name='Passenger',x=1,y=5,z=0,sx=640,sy=360,vehicle=true},
}
s.liveAction(); s.step(1500); s.step(1500); eq(s.sent[3].line,'/wanted 38')
s=fixture({demo=false}); s.aimed=false; s.pool={99,100}
s.actors={
    [99]={id=37,name='Driver',x=0,y=5,z=0,sx=640,sy=360,vehicle=true},
    [100]={id=38,name='Passenger',x=1,y=5,z=0,sx=645,sy=360,vehicle=true},
}
noTarget(s,'overlapping occupants'); check(s.hasLog('несколько игроков'))

-- The camera and selector use different coordinates; moving the selector cannot retarget.
s=fixture({demo=false}); s.aimed=false; open(s)
s.pool={1}; s.sx=0; s.io.MousePos.x,s.io.MousePos.y=20,20
s.step(); check(s.frames[2].condition()); eq(s.poolReads,1)
onWindowMessage(0x0100,0x1B); s.step(); eq(#s.sent,0)

for _,case in ipairs({'far','wall','offscreen','behindcamera','outsidecenter','dead','npc',
    'unstreamed','projectionerror','poolerror','invalidpool','invalidid','missingprojection','invalidcoords','invalidscreen'}) do
    s=fixture({demo=false}); s.aimed=false
    if case=='far' then s.distance=20
    elseif case=='wall' then s.clear=false
    elseif case=='offscreen' then s.onScreen=false
    elseif case=='behindcamera' then s.projected=false
    elseif case=='outsidecenter' then s.sx=100
    elseif case=='dead' then s.targetDead=true
    elseif case=='npc' then s.npc=true
    elseif case=='unstreamed' then s.streamed=false
    elseif case=='projectionerror' then s.projectionError=true
    elseif case=='poolerror' then s.poolError=true
    elseif case=='invalidpool' then s.invalidPool=true
    elseif case=='invalidid' then s.id=1004
    elseif case=='missingprojection' then convert3DCoordsToScreenEx=nil
    elseif case=='invalidcoords' then s.distance=0/0
    elseif case=='invalidscreen' then getScreenResolution=function() return 0/0,720 end end
    noTarget(s,case)
end

-- Invalid/far/occluded bodies are never queried for remote identity.
for _,field in ipairs({'clear','onScreen','targetExists'}) do
    s=fixture({demo=false}); s.aimed=false; s.step(); s.commands.pa26(); s[field]=false
    local before=s.remoteIdentityReads
    s.down[0x58]=true; s.step(16,{[0x58]=true})
    eq(s.remoteIdentityReads,before,'identity was read before visibility checks: '..field)
end

for _,failure in ipairs({'wall','far','name','streamed','offscreen'}) do
    s=fixture({demo=false}); s.aimed=false; s.liveAction(); eq(#s.sent,1)
    if failure=='wall' then s.clear=false
    elseif failure=='far' then s.distance=20
    elseif failure=='name' then s.name='Different_Player'
    elseif failure=='streamed' then s.streamed=false
    else s.onScreen=false end
    s.step(1500); s.step(5000); eq(#s.sent,1,'camera target must be revalidated before every line: '..failure)
end

-- Two similarly centered people are ambiguous; a clearly centered one is chosen.
s=fixture({demo=false}); s.aimed=false
s.pool={1,99,100}
s.actors={
    [99]={id=37,name='Player_A',x=0,y=5,z=0,sx=640,sy=360},
    [100]={id=38,name='Player_B',x=1,y=5,z=0,sx=645,sy=360},
}
noTarget(s,'ambiguous crowd'); check(s.hasLog('несколько игроков'))
s=fixture({demo=false}); s.aimed=false
s.pool={99,100,99} -- duplicated native handle cannot become a second target
s.actors={
    [99]={id=37,name='Player_A',x=0,y=5,z=0,sx=640,sy=360},
    [100]={id=38,name='Player_B',x=1,y=5,z=0,sx=690,sy=360},
}
s.liveAction(); s.step(1500); s.step(1500); eq(s.sent[3].line,'/wanted 37')

-- Pool limit fails closed even when an otherwise good target is near the beginning.
s=fixture({demo=false}); s.aimed=false; s.pool={}
for i=1,2049 do s.pool[i]=99 end
noTarget(s,'pool limit'); check(s.hasLog('Слишком много персонажей'))

-- Banner must occupy exactly the profile's width at the true PNG aspect ratio.
s=fixture(); s.step()
local image=s.imageDraws[2]
local profileWidth
for _,call in ipairs(s.childCalls) do if call.name=='profile##pa26' then profileWidth=call.width end end
check(profileWidth~=nil); check(math.abs(image.w-profileWidth)<.01)
check(math.abs(image.w/image.h-1983/793)<.0001)
