local core = require 'pa26_core'
local hudModule = require 'pa26_hud'
local ffi = require 'ffi'
local cfg = core.widgetDefaults()
local state = {id=0,ping=0,wall=1,x=0,y=0,z=0,interior=0,nick='Victor_Auditore',gxt='~g~East Beach'}
local reads, saves, edits, logs = 0,0,0,{}
local env = {
    localId=function() reads=reads+1; return state.id end,
    nickname=function() return state.nick end,ping=function() return state.ping end,
    coordinates=function() return state.x,state.y,state.z end,
    interior=function() return state.interior end,zone=function() return state.zone or 'EBE' end,
    zoneText=function() return state.gxt end,decode=codec.decode,
    wallTime=function() return state.wall end,localClock=function() return '11.10.2026 15:00:01' end,
    localDate=function() return '11.10.2026' end,gameClock=function() return state.hours or 15,state.minutes or 30 end,
    save=function(value) saves=saves+1; state.saved=value; return not state.saveFailure end,
    log=function(value) logs[#logs+1]=value end,beginEdit=function() edits=edits+1 end,
}
local hud=hudModule.new(cfg,env)
check(not hud.connected); hud:refresh('a',1000)
eq(hud.data.id,0); eq(hud.data.ping,0); eq(hud.data.district,'East Beach')
check(hud.data.identity:find('Victor_Auditore[0]',1,true)); check(hud.data.clock:find('11.10.2026',1,true))
hud:refresh('a',1100); eq(reads,1)
state.wall=2; hud:refresh('a',1100); eq(reads,2,'wall clock must update when game timer stops')
state.nick=codec.encode('Виктор'); state.gxt='~b~Лос Сантос'; hud:refresh('a',1700)
eq(hud.data.nickname,'Виктор'); eq(hud.data.district,'East Beach')
state.interior=3; hud:refresh('a',2300); eq(hud.data.district,'Interior 3')
state.interior=0; state.gxt=nil; hud:refresh('a',2900); eq(hud.data.district,'East Beach')
-- Actual GAN bytes from this user's american.gxt: Russian font-atlas symbols.
state.zone='GAN'; state.gxt='\130\170\174\166o\174'; hud:refresh('a',3500)
eq(hud.data.district,'Ganton','GXT font-atlas bytes must never be treated as CP1251')
state.zone='EASB'; hud:refresh('a',4100); eq(hud.data.district,'Easter Basin')
state.zone='EBE'; hud:refresh('a',4700); eq(hud.data.district,'East Beach')
state.zone='LA'; state.gxt='broken'; hud:refresh('a',5300); eq(hud.data.district,'Los Santos')
eq(hudModule.zoneName('gan','Лос Сантос'),'Ganton')
eq(hudModule.zoneName('NONE','garbage'),'San Andreas')
eq(hudModule.zoneName('CUSTOM','~b~Custom Park'),'Custom Park')
eq(hudModule.zoneName('CUSTOM','\255bad'),'CUSTOM')
eq(hudModule.zoneName('../GAN','bad'),'San Andreas')
eq(hudModule.zoneName(nil,'bad'),'San Andreas')
eq(hudModule.zoneName(string.rep('X',17),'bad'),'San Andreas')
for _,invalid in ipairs({-1,1004,0/0,math.huge,'1'}) do
    state.id=invalid; hud:refresh('a',hud.lastNow+600); eq(hud.data.id,nil); eq(hud.data.nickname,nil)
end
state.id=37
for _,invalid in ipairs({-1,0/0,math.huge,0.5,'40',1000000}) do
    state.ping=invalid; hud:refresh('a',hud.lastNow+600); eq(hud.data.ping,nil)
end
state.ping=42; env.nickname=function() error('nickname unavailable') end
hud:refresh('a',hud.lastNow+600); eq(hud.data.nickname,nil); eq(hud.data.ping,42)
hud:change('time_source','game'); hud:refresh('a',hud.lastNow+600); eq(hud.data.clock,'11.10.2026 15:30')
state.hours=24; hud:refresh('a',hud.lastNow+600); eq(hud.data.clock,'Игровое время: —')
hud:refresh(nil,hud.lastNow+600); check(not hud.connected); eq(hud.data.id,nil); eq(hud.data.nickname,nil)

-- Bounds, scale and persistence are independent of game/UI rendering.
for _,size in ipairs({{640,480},{1920,1080},{320,200},{16384,16384}}) do
    hud:change('x',32768); hud:change('y',32768); hud:change('scale',2)
    local r=hud:layout(size[1],size[2]); check(r~=nil)
    check(r.x>=0 and r.y>=0 and r.x+r.w<=size[1] and r.y+r.h<=size[2]); check(r.scale<=2)
end
eq(hud:layout(0/0,700),nil); eq(hud:layout(100,100),nil)
check(not hud:change('scale',0/0)); check(not hud:change('scale',2.1)); check(not hud:change('x',-1))
hud:resetPosition(); eq(hud.settings.x,8); eq(hud.settings.y,170); eq(hud.settings.scale,1)
local detached=hud:getSettings(); detached.x=100; eq(hud.settings.x,8)
hud:savePending(100); eq(saves,0); hud.drag={}; hud:savePending(2000); eq(saves,0)
hud.drag=nil; hud:savePending(2001); eq(saves,0); hud:savePending(2700); eq(saves,1); check(not hud.dirty)
hud:change('x',20); hud:savePending(3000); hud:savePending(3699); eq(saves,1)
state.saveFailure=true; hud:savePending(3700); eq(saves,2); eq(#logs,1); check(not hud.dirty)
hud:change('x',21); hud:savePending(2147483640); hud:savePending(-2147482900); eq(saves,3)
hud:setVisible(false); check(not hud.settings.visible); hud:setInteraction(true,true); check(not hud.editing and not hud.interactive)
hud:resetPosition(); hud:setInteraction(true,false); check(hud.editing)
ffi.cdef 'typedef struct {float x,y;} Pa26HudVec2; typedef struct {Pa26HudVec2 MousePos; bool MouseDown[5];} Pa26HudIO;'
local io=ffi.new('Pa26HudIO')
local mini={GetIO=function() return io end,ImVec2=function(x,y) return ffi.new('Pa26HudVec2',x,y) end}
hud:setPointer(32,44,false,true); hud:prepareInput(mini,false); eq(io.MousePos.x,32); eq(io.MouseDown[1],true)
hud:setPointer(32,44,false,false); hud:prepareInput(mini,false); eq(io.MouseDown[1],false,'disabled mouse-up must not stick')
hud:stopInteraction(); check(not hud.editing and not hud.interactive and hud.drag==nil)

-- Cosmetic corruption/migration must not silently change saved RP mode.
local raw={main={schema='2',show_on_connect='true',menu_key='120',radial_key='88',max_distance='8',interval_ms='1500',demo_mode='false'}}
for _,a in ipairs(core.actions) do raw[a.key]=core.defaults()[a.key] end
local migrated, warnings=core.normalizeConfig(raw); check(not migrated.main.demo_mode); eq(migrated.widget.x,8); eq(#warnings,0)
raw.widget={scale='nan',x='-1',time_source='server',visible='broken'}
migrated,warnings=core.normalizeConfig(raw); check(not migrated.main.demo_mode); check(#warnings>=4)
eq(migrated.widget.scale,1); eq(migrated.widget.time_source,'local')
