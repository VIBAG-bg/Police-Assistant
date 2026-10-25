local core=require 'pa26_core'
local module=require 'pa26_hud'
local fixture=require 'support.fixture'
local hud=module.new(core.widgetDefaults(),{decode=codec.decode})
local person={id=37,name='Player_Name'}
check(not hud:targetNotice('selected',{id=-1,name='Bad'},nil,1000))
check(hud:targetNotice('selected',person,nil,1000)); eq(#hud.notices,1)
eq(hud.notices[1].duration,10000); check(hud.notices[1].positive)
hud:expireNotices(10999); eq(#hud.notices,1)
hud:expireNotices(11000); eq(#hud.notices,0)
hud:targetNotice('selected',person,nil,12000)
hud:targetNotice('cleared',person,'manual',13000)
eq(#hud.notices,1,'ending replaces this person\'s green notice')
check(not hud.notices[1].positive); eq(hud.notices[1].duration,15000)
eq(hud.notices[1].detail,'Выбор снят вручную.')
hud:expireNotices(27999); eq(#hud.notices,1); hud:expireNotices(28000); eq(#hud.notices,0)
hud:targetNotice('cleared',person,'disconnected',30000)
eq(hud.notices[1].duration,20000); eq(hud.notices[1].detail,'Игрок вышел с сервера.')
hud:expireNotices(49999); eq(#hud.notices,1); hud:expireNotices(50000); eq(#hud.notices,0)
hud:targetNotice('selected',person,nil,51000)
check(not hud:targetNotice('rebound',person,nil,52000)); eq(#hud.notices,1); eq(hud.notices[1].startedAt,51000)
hud:expireNotices(50000); eq(#hud.notices,0,'timer resets discard stale notifications')
for id=1,5 do hud:targetNotice('selected',{id=id,name='Person_'..id},nil,60000+id) end
eq(#hud.notices,3); eq(hud.notices[1].id,5); eq(hud.notices[3].id,3)
check(hud:setConfirmationHeight(96)); check(not hud:setConfirmationHeight(-1)); check(not hud:setConfirmationHeight(0/0))

local function overlaps(a,b)
    return a.x<b.x+b.w and a.x+a.w>b.x and a.y<b.y+b.h and a.y+a.h>b.y
end
local function safe(r,width,height,boxes,reserve)
    local lane=module.overlayLayout(r,width,height,boxes,reserve); check(lane,'lane should fit in this viewport')
    local all={}
    if lane.confirmation then all[#all+1]=lane.confirmation end
    for _,box in ipairs(lane.notices) do all[#all+1]=box end
    eq(#lane.notices,#boxes)
    for i,box in ipairs(all) do
        check(box.x>=4 and box.y>=4 and box.x+box.w<=width-4 and box.y+box.h<=height-4)
        check(not overlaps(box,r),'attached panel must not cover the HUD')
        for j=1,i-1 do check(not overlaps(box,all[j]),'SOS and interaction panels must not overlap') end
    end
    return lane
end
local r={x=960,y=170,w=272,h=174,scale=1}
local lane=safe(r,1280,720,{92,110},96)
check(lane.confirmation.y>=r.y+r.h); check(lane.notices[1].y>=lane.confirmation.y+96)
safe({x=1008,y=546,w=272,h=174,scale=1},1280,720,{92},96) -- bottom/right edge
safe({x=0,y=0,w=272,h=174,scale=1},640,480,{92},0) -- exact top/left edge
safe({x=368,y=160,w=272,h=174,scale=1},640,480,{92,92,92},96) -- moves to the side
safe({x=1912,y=340,w=544,h=348,scale=2},2560,1440,{184,184},192)
eq(module.overlayLayout(r,1280,720,{800},0),nil)
eq(module.overlayLayout({x=0,y=0,w=0/0,h=174,scale=1},1280,720,{92},0),nil)

local function matching(s,text)
    local out={}; for _,draw in ipairs(s.drawnLabels) do if draw.text==text then out[#out+1]=draw end end; return out
end
local function fresh(s) s.drawnText={}; s.drawnLabels={}; s.render() end
local function selected()
    local s=fixture({demo=false}); s.step(); s.commands.pa26select('37'); s.step(300); fresh(s)
    local name=matching(s,'Player_Name [37]'); eq(#name,1)
    check(name[1].color.g>name[1].color.r and name[1].color.a>.9,'start nickname should be green')
    check(table.concat(s.drawnText,'\n'):find('Взаимодействие начато',1,true))
    eq(#s.localChat,0); eq(#s.sent,0)
    return s
end
local s=selected()
s.step(9699); fresh(s); eq(#matching(s,'Player_Name [37]'),1)
s.step(1); fresh(s); eq(#matching(s,'Player_Name [37]'),0)
-- Repeated acquisition does not restart a ten-second card.
s.commands.pa26select('37'); s.step(300); fresh(s); eq(#matching(s,'Player_Name [37]'),0)
s.commands.pa26select('off'); s.step(300); fresh(s)
local ended=matching(s,'Player_Name [37]'); eq(#ended,1)
check(ended[1].color.r>ended[1].color.g,'termination nickname should be red')
check(table.concat(s.drawnText,'\n'):find('Выбор снят вручную.',1,true)); eq(#s.localChat,0)
s.step(14699); fresh(s); eq(#matching(s,'Player_Name [37]'),1)
s.step(1); fresh(s); eq(#matching(s,'Player_Name [37]'),0)
onScriptTerminate(s.script)

-- Both SAMP.Lua quit events and native polling produce one 20-second card.
for _,events in ipairs({true,false}) do
    s=fixture({demo=false,sampEvents=events}); s.step(); s.commands.pa26select('37'); s.step(300)
    if events then s.events.onPlayerQuit(37,1) else s.targetConnected=false; s.step(300) end
    fresh(s); eq(#matching(s,'Player_Name [37]'),1)
    check(table.concat(s.drawnText,'\n'):find('Игрок вышел с сервера.',1,true))
    if events then s.events.onPlayerQuit(37,1); s.events.onPlayerJoin(37,0,false,'Player_Name') end
    s.step(19999); fresh(s); eq(#matching(s,'Player_Name [37]'),1)
    s.step(1); fresh(s); eq(#matching(s,'Player_Name [37]'),0)
    eq(#s.localChat,0); eq(#s.sent,0); check(not s.hasLog('Ошибка интерфейса'))
    onScriptTerminate(s.script)
end

-- A second selection gives the new person a green card and the old one a red card.
s=selected(); s.id=38; s.name='Second_Name'; s.commands.pa26select('38'); s.step(300); fresh(s)
local old,new=matching(s,'Player_Name [37]'),matching(s,'Second_Name [38]')
eq(#old,1); eq(#new,1); check(old[1].color.r>old[1].color.g); check(new[1].color.g>new[1].color.r)
check(table.concat(s.drawnText,'\n'):find('Выбран другой игрок.',1,true)); eq(#s.localChat,0)
onScriptTerminate(s.script)
