-- Real Windows x86 data reader, CryptoAPI SHA and graph solver; never launches GTA.
local root=assert(os.getenv('PA_SOURCE_ROOT'));local game=os.getenv('LOCALAPPDATA')..'/Exsellent Launcher/game/'
package.path=root..'/moonloader/lib/?.lua;'..game..'MoonLoader/lib/?.lua;'..package.path
package.cpath=game..'MoonLoader/lib/?.dll;'..package.cpath
local json=require 'cjson';local f=assert(io.open(root..'/tests/ROADS_NATIVE32_CONFIG0450.json','rb'))
local config=json.decode(f:read('*a'));f:close()
local sources=require 'pa26_road_sources';local graph=require 'pa26_navigation_roads';local checks=0
local function check(value,why)checks=checks+1;assert(value,why)end
local counts={}
for _,case in ipairs(config.cases)do
 local resolver=sources.new({script=function()return case.ml..'/police_assistant_2026.lua'end,moonloader=function()return case.ml end})
 local g=graph.new({hash=require('pa26_author_io').hash,openCandidate=function(i,c)return resolver:open(i,c)end})
 g:prepare(case.custom or'')
 for _=1,2000 do g:tick({road_work=256,road_budget_ms=1},true);if g.phase~='loading'then break end end
 if case.expected=='failed'then check(g.phase=='failed');check(not g.graph)
 else
  check(g.phase=='ready',g.status);check(g:view().sourceId==case.expected);check(not g.handle)
  local j=g:begin({x=1500,y=-1700},{x=-2000,y=200},300)
  for _=1,2000 do g:tick({road_work=256,road_budget_ms=1},true);if g:poll(j)then break end end
  local done,points,distance,why=g:poll(j);check(done and points,why);check(#points==462);check(distance>5900 and distance<6100)
  counts[#counts+1]={source=g:view().sourceId,nodes=#points}
 end
 g:reset();check(not g.handle and not g.graph and not g.job)
end
local text=json.encode({status='passed',checks=checks,cases=#config.cases,results=counts,
 environment='Windows x86 LuaJIT and Unicode reader; fixture files only',game_started=false,live_game_written=false,win7_guest_tested=false})
f=assert(io.open(root..'/tests/ROADS_NATIVE32_0450.json','wb'));f:write(text);f:close();print(text)
