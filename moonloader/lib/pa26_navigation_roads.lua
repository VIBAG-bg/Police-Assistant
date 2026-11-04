-- Read-only LGPS v1 data adapter. No ASI loading, hooks, native addresses or input interception.
local core=require 'pa26_core'
local portableHash=require 'pa26_sha256'
local M={MAX_BYTES=2097152,MAX_NODES=65536,MAX_EDGES=131072};local G={};G.__index=G
local function u32(s,p)local a,b,c,d=s:byte(p,p+3);if not d then error('Короткая запись графа')end;return a+b*256+c*65536+d*16777216 end
local function f32(s,p)
 local v=u32(s,p);local sign=v>=2147483648 and -1 or 1;v=v%2147483648
 local e=math.floor(v/8388608);local m=v%8388608
 if e==255 then error('Нечисловая координата графа')end
 return sign*math.ldexp(e==0 and m or m+8388608,e==0 and -149 or e-150)
end
local function distance(a,b)return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)end
local function cell(x,y)return math.floor(x/128)..':'..math.floor(y/128)end
local function push(h,id,cost)
 if #h>=131072 then error('Очередь поиска переполнена')end
 local i=#h+1;while i>1 do local p=math.floor(i/2);if h[p].cost<=cost then break end;h[i]=h[p];i=p end
 h[i]={id=id,cost=cost}
end
local function pop(h)
 local first=h[1];local last=table.remove(h);if #h==0 then return first end
 local i=1;while i*2<=#h do local j=i*2;if j<#h and h[j+1].cost<h[j].cost then j=j+1 end
  if h[j].cost>=last.cost then break end;h[i]=h[j];i=j
 end;h[i]=last;return first
end
function M.new(env)return setmetatable({env=env or{},verified=true,supports2D=true,asynchronous=true,kind='road_graph',phase='idle',serial=0,progress=0,status='Граф дорог ещё не загружен',failures={}},G)end
function G:cancel(job)if not job or self.job==job then self.job=nil end end
function G:reset()
 if self.handle then pcall(self.handle.close,self.handle)end
 self.handle=nil;self.loader=nil;self.graph=nil;self.job=nil;self.phase='idle';self.serial=self.serial+1;self.status='Граф дорог ещё не загружен'
 self.sourceKey=nil;self.source=nil;self.candidateIndex=1;self.progress=0;self.failures={}
end
function G:prepare(custom)
 custom=custom or'';local changed=self.sourceKey~=nil and self.sourceKey~=custom
 if changed then self:reset()end;self.sourceKey=custom
 if self.phase=='idle'then
  self.candidateIndex=1;self.phase='loading';self.loader=coroutine.create(function()self:load()end)
 end
 return changed
end
function G:view()
 return {phase=self.phase,available=self.phase=='ready',source=self.source and self.source.label or'Не выбран',
  sourceId=self.source and self.source.id,progress=self.progress,status=self.status,
  validation=self.phase=='ready'and(self.source and self.source.sha256 and'SHA-256 и структура проверены'or'LGPS v1: структура проверена')or'Проверка не завершена',
  fallback=#self.failures>0 and table.concat(self.failures,'; ')or nil}
end
function G:load()
 local handle,meta,why
 if self.env.openCandidate then handle,meta,why=self.env.openCandidate(self.candidateIndex,self.sourceKey)
 elseif self.env.open then handle,why=self.env.open()end
 self.source=type(meta)=='table'and meta or nil;self.progress=0
 self.status='Загрузка: '..(self.source and self.source.label or'дорожный граф')
 if not handle then error(why or'Дорожный файл отсутствует или недоступен',0)end
 self.handle=handle
 local header=handle:read(16)
 if type(header)~='string'or #header~=16 or header:sub(1,4)~='LGPS'or u32(header,5)~=1 then error('Неизвестный формат дорожного графа')end
 local n,m=u32(header,9),u32(header,13);local size=16+n*8+m*12
 if n<2 or n>M.MAX_NODES or m<1 or m>M.MAX_EDGES or size>M.MAX_BYTES then error('Граф превышает допустимые пределы')end
 if self.source and self.source.size and size~=self.source.size then error('Размер встроенного графа не совпадает с проверенной версией',0)end
 local chunks={header};local remaining=size-16
 while remaining>0 do
  local part=handle:read(math.min(16384,remaining));if type(part)~='string'or #part==0 then error('Дорожный граф обрезан')end
  remaining=remaining-#part;chunks[#chunks+1]=part;self.progress=math.floor(20*(size-remaining)/size);coroutine.yield()
 end
 if handle:read(1)~=nil then error('Лишние данные в дорожном графе')end
 handle:close();self.handle=nil
 local raw=table.concat(chunks);chunks=nil
 if self.source and self.source.sha256 then
  self.status='Проверка целостности встроенного графа'
  -- The already-supported Windows SHA implementation avoids JIT warm-up in a
  -- navigation frame. Portable fallback remains cooperative and data-bounded.
  local digest
  if self.env.hash then local ok,value=pcall(self.env.hash,raw);if ok then digest=value end end
  if not digest then digest=portableHash.digest(raw,function(at,total)
   if at%512==1 then self.progress=20+math.floor(20*at/total);coroutine.yield()end
  end)end
  if digest~=self.source.sha256 then error('SHA-256 встроенного графа не совпадает. Переустановите ресурс PA.',0)end
 end
 self.status='Подготовка дорожной сети'
 local graph={nodes={},adj={},cells={},edges=m};local pos=17
 for i=1,n do
  local x,y=f32(raw,pos),f32(raw,pos+4);pos=pos+8
  if not core.finite(x)or not core.finite(y)or math.abs(x)>6000 or math.abs(y)>6000 then error('Координата графа за пределами карты')end
  graph.nodes[i]={x=x,y=y,z=0,height_unknown=true};graph.adj[i]={}
  local key=cell(x,y);local bucket=graph.cells[key]or{};graph.cells[key]=bucket;bucket[#bucket+1]=i
  if i%4==0 then self.progress=40+math.floor(60*i/(n+m));coroutine.yield()end
 end
 for edgeIndex=1,m do
  local a,b,hint=u32(raw,pos)+1,u32(raw,pos+4)+1,u32(raw,pos+8);pos=pos+12
  if a<1 or a>n or b<1 or b>n or a==b or hint>255 then error('Неверная связь дорожного графа')end
  local w=math.max(.001,distance(graph.nodes[a],graph.nodes[b]))
  if #graph.adj[a]>=32 or #graph.adj[b]>=32 then error('Слишком много связей одного узла')end
  graph.adj[a][#graph.adj[a]+1]={id=b,w=w};graph.adj[b][#graph.adj[b]+1]={id=a,w=w}
  if edgeIndex%4==0 then self.progress=40+math.floor(60*(n+edgeIndex)/(n+m));coroutine.yield()end
 end
 self.graph=graph;self.phase='ready';self.progress=100;self.status='Дорожный GPS: доступен · '..n..' узлов'
end
local function nearest(graph,p,radius)
 local best,d=nil,radius;local reach=math.ceil(radius/128);local x,y=math.floor(p.x/128),math.floor(p.y/128)
 for cx=x-reach,x+reach do for cy=y-reach,y+reach do
  for _,id in ipairs(graph.cells[cx..':'..cy]or{})do
   local value=distance(graph.nodes[id],p);if value<d or value==d and(not best or id<best)then best=id;d=value end
   coroutine.yield()
  end
 end end
 return best,d
end
function G:solve(job)
 local graph=self.graph
 local a=nearest(graph,job.a,job.snap);local b=nearest(graph,job.b,job.snap)
 if not a or not b then job.error='Начало или назначение слишком далеко от дорожного графа';return end
 if a==b then job.error='Назначение у того же дорожного узла';return end
 local heap={};push(heap,a,0)
 local costs={[a]=0};local previous={};local closed={};local visits=0
 while #heap>0 do
  local v=pop(heap).id
  if not closed[v]then
   closed[v]=true;visits=visits+1
   if visits>M.MAX_NODES then error('Предел поиска маршрута')end
   if v==b then
    local reverse={};local at=b
    while at do
     if #reverse>=2000 then job.error='Маршрут слишком подробный';return end
     reverse[#reverse+1]=graph.nodes[at];if at==a then break end;at=previous[at];coroutine.yield()
    end
    if reverse[#reverse]~=graph.nodes[a]then error('Разрыв пути')end
    local points={};for i=#reverse,1,-1 do points[#points+1]=reverse[i];coroutine.yield()end
    job.points=points;job.distance=costs[b];job.visits=visits;return
   end
   for _,edge in ipairs(graph.adj[v])do
    if not closed[edge.id]then
     local candidate=costs[v]+edge.w
     if not costs[edge.id]or candidate<costs[edge.id]then
      costs[edge.id]=candidate;previous[edge.id]=v;push(heap,edge.id,candidate+distance(graph.nodes[edge.id],graph.nodes[b]))
     end
    end
    coroutine.yield()
   end
  end
  coroutine.yield()
 end
 job.error='Между узлами нет дорожного маршрута'
end
function G:begin(a,b,snap)
 self.serial=self.serial+1
 local function valid(p)return type(p)=='table'and core.finite(p.x)and core.finite(p.y)and math.abs(p.x)<=6000 and math.abs(p.y)<=6000 end
 local job={serial=self.serial};self.job=job
 if not valid(a)or not valid(b)or snap~=nil and not core.finite(snap)then job.done=true;job.error='Неверное назначение';return job end
 job.a={x=a.x,y=a.y};job.b={x=b.x,y=b.y};job.snap=math.max(25,math.min(600,snap or 300))
 self.job=job
 if self.phase=='idle'then self:prepare(self.sourceKey)end
 if self.phase=='failed'then job.error=self.status;job.done=true end
 return job
end
function G:poll(job)
 if not job or job~=self.job then return true,nil,nil,'Поиск отменён'end
 return job.done==true,job.points,job.distance,job.error
end
function G:tick(cfg,safe)
 if not safe then return end
 cfg=cfg or{}
 local work=math.max(16,math.min(1024,math.floor(cfg.road_work or 256)))
 local budget=math.max(.25,math.min(3,cfg.road_budget_ms or 1))
 local start=os.clock();self.lastOps=0
 for _=1,work do
  local co=self.loader
  if not co and self.graph and self.job and not self.job.done then
   local job=self.job;job.co=job.co or coroutine.create(function()self:solve(job)end);co=job.co
  end
  if not co then break end
  local ok,why=coroutine.resume(co);self.lastOps=self.lastOps+1
  if not ok then
   if self.handle then pcall(self.handle.close,self.handle);self.handle=nil end
   if co==self.loader then
    self.graph=nil;self.failures[#self.failures+1]=(self.source and self.source.label or'Граф')..': '..tostring(why):gsub('^.-:%d+: ','')
    self.candidateIndex=(self.candidateIndex or 1)+1
    if self.env.openCandidate and self.candidateIndex<=4 then
     self.loader=coroutine.create(function()self:load()end);self.status='Проверяю резервный источник';self.progress=0
    else
     self.loader=nil;self.phase='failed';self.status='Дорожный GPS: недоступен. '..table.concat(self.failures,'; ')
     if self.job then self.job.done=true;self.job.error=self.status end
    end
   elseif self.job then self.job.done=true;self.job.error=tostring(why)end
   break
  end
  if coroutine.status(co)=='dead'then
   if co==self.loader then self.loader=nil elseif self.job then self.job.done=true;self.job.co=nil end
  end
  if self.lastOps%16==0 and(os.clock()-start)*1000>=budget then break end
  if self.loader and self.handle then break end -- at most one small file read per frame
 end
 self.lastStepMs=(os.clock()-start)*1000
end
return M
