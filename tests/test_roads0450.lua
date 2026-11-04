local ffi=require 'ffi';local roads=require 'pa26_navigation_roads';local nav=require 'pa26_navigation'
local function u32(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local function f32(n)local v=ffi.new('float[1]',n);return ffi.string(v,4)end
local nodes={{0,0},{100,0},{100,100},{200,100},{0,100}}
local edges={{0,1},{1,2},{2,3},{0,4},{4,2}}
local function bytes(version)
 local s={'LGPS',u32(version or 1),u32(#nodes),u32(#edges)}
 for _,p in ipairs(nodes)do s[#s+1]=f32(p[1])..f32(p[2])end
 for _,e in ipairs(edges)do s[#s+1]=u32(e[1])..u32(e[2])..u32(12)end
 return table.concat(s)
end
local function fixture(raw)
 local f={opens=0,reads=0,closed=0}
 local g=roads.new({open=function()
  f.opens=f.opens+1;local at=1
  return {read=function(_,n)f.reads=f.reads+1;if at>#raw then return end;local v=raw:sub(at,at+n-1);at=at+#v;return v end,
   close=function()f.closed=f.closed+1 end}
 end})
 return g,f
end
local cfg={road_work=16,road_budget_ms=1,road_snap=100,native_path=true,enabled=true,retry_ms=1000,recalculate_ms=1500,movement=20,missing_grace_ms=200}
local g,f=fixture(bytes());local job=g:begin({x=0,y=0},{x=200,y=100},50)
g:tick(cfg,false);eq(f.opens,0)
for _=1,200 do g:tick(cfg,true);check(g.lastOps<=16);if g:poll(job)then break end end
local done,path,distance=g:poll(job);check(done);check(path);check(#path>=4);eq(distance,300);eq(f.opens,1);eq(f.closed,1)
local first=job;job=g:begin({x=100,y=0},{x=0,y=100},100);check(select(1,g:poll(first)));check(not select(2,g:poll(first)))
g:cancel(job);g:tick(cfg,true);check(not g.job);g:reset();eq(g.graph,nil)
for _,raw in ipairs({bytes(2),bytes():sub(1,20),bytes()..'extra','LGPS'..u32(1)..u32(999999)..u32(1),
 'LGPS'..u32(1)..u32(2)..u32(1)..f32(0/0)..f32(0)..f32(1)..f32(1)..u32(0)..u32(1)..u32(12)})do
 local bad,files=fixture(raw);local j=bad:begin({x=0,y=0},{x=100,y=100})
 for _=1,100 do bad:tick(cfg,true);if bad:poll(j)then break end end
 check(j.done);eq(j.points,nil);check(j.error);bad:reset()
end
local missing=roads.new({open=function()return nil,'missing'end});local j=missing:begin({x=0,y=0},{x=1,y=1});missing:tick(cfg,true);check(j.done);check(j.error)
local invalid=missing:begin({x=math.huge,y=0},{x=1,y=1});check(invalid.done)
-- Async arbitration must reject stale jobs, draw 2D routes and preserve an explicitly retained waypoint.
g=fixture(bytes());local n=nav.new({path=g,clock=function()return 1 end})
local state={session='s',x=0,y=0,z=0,interior=0};n:reset('s');n:put('waypoint',{x=200,y=100,height_unknown=true},0)
for t=1,200 do g:tick(cfg,true);n:tick(state,t*50,cfg);if n.route then break end end
check(n.route);eq(n.distance,300);check(n.distanceKind:find('2D',1,true))
cfg.keep_waypoint=true;n:observe('absent',nil,10000,cfg);n:observe('absent',nil,11000,cfg)
check(n.sources.waypoint);check(n.sources.waypoint.marker_missing)
n:clear(11001);eq(n.active,nil);check(n:view().resumable);n:resume(11002);check(n.active)
n:put('mark',{x=0,y=100,z=0},12000);n:calculate(state,12000,cfg);local old=n.job;n:reset('different');eq(n.job,nil);check(not g.job)
