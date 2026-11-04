local N=require 'pa26_navigation';local cfg=require('pa26_field_settings').defaults().navigation
local R=require 'pa26_navigation_render';local Path=require 'pa26_navigation_path'
cfg.enabled=true
local s={session='s',interior=0,x=0,y=0,z=0}
local n=N.new();n:tick(s,0,cfg)
eq(N.waypoint(false),'absent');eq(N.waypoint(nil),'unknown');eq(N.waypoint(1,0,0,0),'unknown')
local status,p=N.waypoint(true,0,0,0);eq(status,'present');check(p.x==0 and p.y==0)
for _,p in ipairs({{x=0/0,y=0},{x=math.huge,y=0},{x=6001,y=1},{x=1,y=1,z=3001}})do check(not N.point(p));check(not n:put('mark',p,0))end
check(n:put('server',{x=1,y=1},0));eq(n.active.kind,'server')
n:observe('present',{x=100,y=100,z=0},10,cfg);eq(n.active.kind,'waypoint')
n:put('server',{x=2,y=2},20);eq(n.active.kind,'waypoint')
n:put('mark',{x=200,y=200,z=0},30,1000);eq(n.active.kind,'mark')
n:choose(1030);eq(n.active.kind,'waypoint');check(not n.sources.mark)
n:put('mark',{x=200,y=200},1040,5000);n:observe('present',{x=101,y=101},1050,cfg);eq(n.active.kind,'waypoint')
n:clear(1060);eq(n.active,nil);n:observe('present',{x=101,y=101},1070,cfg);eq(n.active,nil,'Same GTA marker must not reactivate cleared guidance')
n:observe('present',{x=103,y=103},1080,cfg);eq(n.active.kind,'waypoint')
n:observe('absent',nil,1100,cfg);check(n.sources.waypoint);n:observe('unknown',nil,1200,cfg);check(not n.missingAt)
n:observe('absent',nil,1300,cfg);n:observe('absent',nil,1300+cfg.missing_grace_ms,cfg);check(not n.sources.waypoint)
n:tick({session='t',interior=0,x=0,y=0,z=0},2100,cfg);eq(next(n.sources),nil)
n:put('mark',{x=10,y=10},2200);n:tick({session='t',interior=1,x=0,y=0,z=0},2200,cfg);eq(next(n.sources),nil)
-- A verified injectable host exercises scheduling; production native ABI stays blocked.
local calls=0;cfg.native_path=true
local clock=0
n=N.new({clock=function()return clock end,path={verified=true,find=function(_,a,b)calls=calls+1;return {a,b},200 end}})
n:tick(s,0,cfg);n:put('waypoint',{x=100,y=100,z=0},1);n:tick(s,1,cfg);eq(calls,1);eq(n:view().distanceKind,'по дороге')
for i=2,2000 do n:tick(s,i,cfg)end;eq(calls,1,'No recalculation while stationary')
s.x=40;n:tick(s,2001,cfg);eq(calls,2);s.x=0
n.env.path.find=function()calls=calls+1;return nil end
n:put('waypoint',{x=500,y=500,z=0},2100);n:tick(s,2100,cfg);eq(calls,3)
n:tick(s,2101,cfg);n:tick(s,3100,cfg);eq(calls,3)
n:tick(s,2100+cfg.retry_ms,cfg);eq(calls,4)
n.env.path.find=function(_,a,b)n:put('waypoint',{x=1,y=10},10000);return {a,b},10 end
n:tick(s,10000,cfg);eq(n.route,nil,'Never commit a stale destination result')
local points={};for i=1,2000 do points[i]={x=i,y=math.sin(i/10),z=0}end
local simple=R.simplify(points,257);check(#simple<=257);eq(simple[1].x,1);eq(simple[#simple].x,2000)
points[5].x=0/0;check(#R.simplify(points,257)==0,'Validate ALL input nodes, even omitted ones')
eq(Path.new().verified,false)
local locked,unlocked=0,0
local b={buildVerified=true,abiVerified=true,gameAcceptance=true,stale=function()return false end,
 lock=function()locked=locked+1;return true end,unlock=function()unlocked=unlocked+1;return true end,
 find=function(a,c,cap)eq(cap,2000);return {a,c},10 end}
local path=Path.new(b);check(path.verified);path:find({x=0,y=0},{x=1,y=1});eq(locked,1);eq(unlocked,1)
path:find({x=0,y=0},{x=2,y=2});eq(locked,1)
b.stale=function()return true end;check(not Path.new(b).verified)
b.stale=function()return false end;b.find=function()return {},0 end
path=Path.new(b);path:find({x=0,y=0},{x=1,y=1});check(not path.verified);eq(unlocked,1,'Invalid first result keeps sentinel')
