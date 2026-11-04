local sources=require 'pa26_road_sources';local roads=require 'pa26_navigation_roads';local hash=require 'pa26_sha256';local ffi=require 'ffi'
eq(hash.digest(''),'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
eq(hash.digest('abc'),'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
eq(hash.digest('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),'248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1')
local yields=0;eq(hash.digest(string.rep('a',1000000),function()yields=yields+1 end),'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');check(yields>1000)
check(not pcall(hash.digest,string.rep('x',2097153)))
local ml='C:\\Игра\\MoonLoader';local script=ml..'\\police_assistant_2026.lua'
local rows=assert(sources.candidates(script,ml,'D:\\Карты\\mine.bin'));eq(#rows,4)
eq(rows[1].id,'bundled');eq(rows[1].sha256,sources.HASH);eq(rows[2].id,'custom');eq(rows[3].id,'launcher');eq(rows[4].id,'legacy')
eq(#assert(sources.candidates(script,ml,rows[1].path)),3,'Deduplicate a custom alias of bundled file')
for _,p in ipairs({'relative.bin','C:\\x\\..\\roads.bin','\\\\server\\file','C:\\file:stream','C:\\NUL.','C:\\x\nfile'})do check(not sources.absolute(p),p)end
check(not sources.candidates('C:\\other\\police_assistant_2026.lua',ml,''));check(not sources.candidates(script,'C:\\other',''))
local function u32(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local function float(n)return ffi.string(ffi.new('float[1]',n),4)end
local raw='LGPS'..u32(1)..u32(3)..u32(2)..float(0)..float(0)..float(100)..float(0)..float(200)..float(0)..u32(0)..u32(1)..u32(12)..u32(1)..u32(2)..u32(20)
local function file(text,closed)
 local at=1;return{read=function(_,n)if at>#text then return end;local p=text:sub(at,at+n-1);at=at+#p;return p end,close=function()closed.n=closed.n+1 end}
end
for _,winner in ipairs({2,3,4})do
 local opens=0;local closed={n=0}
 local resolver=sources.new({script=function()return script end,moonloader=function()return ml end,open=function(p)
  opens=opens+1
  if p==rows[winner].path then return file(raw,closed)end
  return file('broken graph',closed)
 end})
 local g=roads.new({openCandidate=function(i,c)return resolver:open(i,c)end});g:prepare('D:\\Карты\\mine.bin')
 local cfg={road_work=256,road_budget_ms=1}
 g:tick(cfg,false);eq(opens,0,'No file work while input is protected')
 for _=1,300 do g:tick(cfg,true);if g.phase~='loading'then break end end
 eq(g.phase,'ready');eq(g:view().sourceId,rows[winner].id);eq(g:view().progress,100);check(g:view().fallback)
 eq(opens,winner);eq(closed.n,winner)
 local j=g:begin({x=0,y=0},{x=200,y=0},50)
 for _=1,100 do g:tick(cfg,true);if g:poll(j)then break end end
 local done,path,distance=g:poll(j);check(done and path);eq(distance,200)
 g:cancel(j);local previous=opens;g:begin({x=100,y=0},{x=200,y=0},50);g:tick(cfg,true);eq(opens,previous,'Prepared graph is reused')
 check(g:prepare('D:\\Карты\\different.bin'));eq(g.graph,nil);eq(g.job,nil);g:reset();check(not g.handle)
end
local missing=roads.new({openCandidate=function()return nil,nil,'Нет файла'end});missing:prepare('')
for _=1,10 do missing:tick({road_work=256,road_budget_ms=1},true)end
eq(missing.phase,'failed');eq(#missing.failures,4);check(missing:view().status:find('недоступен',1,true))
-- The package-managed graph is pinned: structurally valid arbitrary bytes cannot impersonate it.
local bad=roads.new({openCandidate=function(index)if index==1 then return file(raw,{n=0}),{label='Встроенный',size=#raw,sha256=sources.HASH}end;return nil,nil,'missing'end})
bad:prepare('');for _=1,100 do bad:tick({road_work=256,road_budget_ms=1},true)end
eq(bad.phase,'failed');check(bad.failures[1]:find('SHA%-256'))
local cfg=assert(require('pa26_field_settings').validate({navigation={road_external='D:\\Карты\\mine.bin'}}));eq(cfg.navigation.road_external,'D:\\Карты\\mine.bin')
check(not require('pa26_field_settings').validate({navigation={road_external='relative.bin'}}))
-- Integration: graph prepares before a destination, including the ordinary
-- pause-map cursor. Actual chat/dialog/focus ownership still suspends all IO.
local model=require 'pa26_bindings';local lib=model.defaults(require('pa26_core').defaults())
lib.field.enabled=true;lib.field.navigation.enabled=true;lib.field.navigation.native_path=true
local reads=0;local time=0
local field=require('pa26_field_services').new({library=function()return lib end,revision=function()return 1 end,
 clock=function()return time end,gameNow=function()return time end,codec=codec,notice=function()end,
 openRoads=function()reads=reads+1;return file(raw,{n=0})end})
local scene={session='s',ped=1,interior=0,x=0,y=0,z=0,focused=true,alive=true,paused=true,blocked=true,typing=false}
local input={paused=true,focused=true,alive=true,menuBlocked=true,chatActive=true,dialogActive=false}
for i=1,10 do time=i*50;field:tick(scene,time,input)end;eq(reads,0,'Chat suspends prefetch even while paused')
input.menuBlocked=false;input.chatActive=false
for i=11,100 do time=i*50;field:tick(scene,time,input);if field.snapshot.roads and field.snapshot.roads.available then break end end
eq(reads,1);check(field.snapshot.roads.available,'Esc cursor alone cannot block graph preparation');eq(field.snapshot.target,nil)
field:checkpoint('server',{x=200,y=0,z=0})
for i=101,200 do time=i*50;field:tick(scene,time,input);if field.snapshot.points and #field.snapshot.points>1 then break end end
check(field.snapshot.points and #field.snapshot.points>1,'Road search completes while the ordinary pause map is open')
input.chatActive=true;input.menuBlocked=true;field.navigation:invalidatePath()
for i=201,210 do time=i*50;field:tick(scene,time,input)end
check(not field.navigation.route,'No solver work while chat is active');eq(reads,1,'Do not reread cached graph')
field:reset();check(not field.navigation.env.path.graph)
