-- 30 minutes of virtual session time at 120 Hz, accelerated deterministic host.
-- This is NOT a claim of 30 wall-clock minutes, GTA FPS or live CEF latency.
local core=require 'pa26_core';local model=require 'pa26_bindings'
local lib=model.defaults(core.defaults());local before=model.copy(lib);lib.field.enabled=true
lib.field.navigation.enabled=true;lib.field.navigation.observe_waypoint=true
lib.field.coordinates.enabled=true;lib.field.coordinates.observe=true
local now,reads,sends=0,0,0
local field=require('pa26_field_services').new({library=function()return lib end,revision=function()return 1 end,
 clock=function()return now end,gameNow=function()return now end,codec=codec,
 waypoint=function()reads=reads+1;return true,100,200,0 end,
 start=function()sends=sends+1;return true end,notice=function()end})
local s={session='one',ped=1,demo=false,x=0,y=0,z=0,interior=0,focused=true,alive=true,paused=false,blocked=false}
for i=1,216000 do
 now=i*(1000/120);s.typing=i%400<150;s.paused=i%10000<100;s.interior=i%5000<500 and 1 or 0
 if i==108000 then s.session='two' end
 field:tick(s,now)
 if i<=1000 then field:observe('[FN] Test: Мои координаты: '..i..' 100 0','native',now)end
 if i%1000==0 then local n=0;for _ in pairs(field.navigation.sources)do n=n+1 end;check(n<=5);check(#field.coordinates.order<=32);eq(sends,0)end
end
check(reads<7205);eq(sends,0);eq(field.navigation.env.path.verified,false)
eq(lib.notes[1].body,before.notes[1].body);eq(lib.bindings[1].script,before.bindings[1].script)
field:reset('done');eq(next(field.navigation.sources),nil);eq(field.coordinates.offer,nil)
