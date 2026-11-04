-- Pure source arbitration and bounded routing. Never creates/deletes GTA waypoints.
local core=require 'pa26_core';local M={};local N={};N.__index=N
local function copy(v)if type(v)~='table'then return v end;local o={};for k,x in pairs(v)do o[k]=copy(x)end;return o end
function M.point(p)
 return type(p)=='table'and core.finite(p.x)and core.finite(p.y)and core.finite(p.z or 0)and
  math.abs(p.x)<=6000 and math.abs(p.y)<=6000 and math.abs(p.z or 0)<=3000
end
function M.distance(a,b)return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)end
function M.waypoint(a,x,y,z)
 -- Only the documented boolean + coordinates tuple is interpreted. Other
 -- runtime signatures remain unknown, never interpreted as deliberate removal.
 if a==false then return'absent'end
 if a==true and M.point({x=x,y=y,z=z})then return'present',{x=x,y=y,z=z or 0,height_unknown=z==nil}end
 return'unknown'
end
function M.new(env)return setmetatable({env=env or{},sources={},serial=0,generation=1,revision=0,status='Выключено'},N)end
function N:reset(session)
 if self.job and self.env.path and self.env.path.cancel then self.env.path:cancel(self.job)end;self.job=nil
 self.sources={};self.session=session;self.serial=0;self.generation=self.generation+1;self.active=nil;self.route=nil
 self.searchAt=nil;self.searchPos=nil;self.negativeUntil=nil;self.missingAt=nil;self.observed=nil;self.searching=false;self.distance=nil;self.distanceKind=nil;self.status='Нет назначения';self.revision=self.revision+1
end
function N:put(kind,p,now,ttl)
 if not({waypoint=true,mark=true,server=true,race=true,bulletin=true})[kind]or not M.point(p)then return nil,'Неверные координаты.'end
 local old=self.sources[kind]
 if old and M.distance(old,p)<.5 and math.abs((old.z or 0)-(p.z or 0))<2 and(kind=='waypoint'or kind=='server'or kind=='race')then return true end
 self.serial=self.serial+1;self.sources[kind]={x=p.x,y=p.y,z=p.z or 0,serial=self.serial,kind=kind,expires=ttl and now+ttl,
  approximate=kind=='bulletin',height_unknown=p.height_unknown or p.z==nil,session=self.session,createdAt=now}
 self:choose(now);return true
end
function N:remove(kind,now)self.sources[kind]=nil;self:choose(now)end
function N:choose(now)
 local best
 for k,p in pairs(self.sources)do
  if p.session~=self.session or p.expires and now>=p.expires then self.sources[k]=nil
  elseif not p.suppressed then
   local explicit=k=='waypoint'or k=='mark'or k=='bulletin'
   local bestExplicit=best and(best.kind=='waypoint'or best.kind=='mark'or best.kind=='bulletin')
   if not best or explicit and not bestExplicit or explicit==not not bestExplicit and p.serial>best.serial then best=p end
  end
 end
 if best~=self.active then
  if self.job and self.env.path and self.env.path.cancel then self.env.path:cancel(self.job)end
  self.job=nil;self.searching=false;self.active=best;self.route=nil;self.searchAt=nil;self.negativeUntil=nil;self.revision=self.revision+1
 end
end
function N:clear(now)
 for _,p in pairs(self.sources)do p.suppressed=true end
 self:choose(now);self.status='Маршрут PA сброшен; метка GTA сохранена'
end
function N:resume(now)for _,p in pairs(self.sources)do p.suppressed=nil end;self:choose(now)end
function N:observe(status,p,now,cfg)
 if status=='present'and M.point(p)then self.missingAt=nil;self:put('waypoint',p,now);if self.sources.waypoint then self.sources.waypoint.marker_missing=nil end
 elseif status=='absent'then
  if not self.missingAt then self.missingAt=now end
  if now-self.missingAt>=cfg.missing_grace_ms then
   if cfg.keep_waypoint and self.sources.waypoint then self.sources.waypoint.marker_missing=true
   else self:remove('waypoint',now)end
  end
 else self.missingAt=nil end
end
function N:acceptPath(ok,points,distance,now,cfg,why)
 local valid=ok and type(points)=='table'and #points>=2 and #points<=2000 and core.finite(distance)and distance>0 and distance<100000
 if valid then for _,v in ipairs(points)do if not M.point(v)then valid=false;break end end end
 if not valid then
  if self.route then self.revision=self.revision+1 end
  self.route=nil;self.distance=M.distance(self.searchPos,self.active);self.distanceKind='по прямой';self.negativeUntil=now+cfg.retry_ms
  self.status=why or'Маршрут не найден · по прямой';return
 end
 self.route=copy(points);self.routeDistance=distance;self.distance=distance;self.distanceKind=self.env.path.supports2D and'по дорожному графу · 2D'or'по дороге'
 self.status='Дорожный маршрут PA';self.revision=self.revision+1
end
function N:calculate(pos,now,cfg)
 local p=self.active;if not p or not M.point(pos)then return end
 if self.route then self.distance=self.routeDistance;self.distanceKind=self.env.path and self.env.path.supports2D and'по дорожному графу · 2D'or'по дороге'
 else self.distance=M.distance(pos,p);self.distanceKind='по прямой'end
 if not cfg.native_path or p.height_unknown and not(self.env.path and self.env.path.supports2D)then
  if self.job and self.env.path and self.env.path.cancel then self.env.path:cancel(self.job)end;self.job=nil;self.searching=false
  if self.route then self.route=nil;self.revision=self.revision+1 end
  self.distance=M.distance(pos,p);self.distanceKind='по прямой'
  self.status=p.height_unknown and'Высота неизвестна · дорожный GPS не используется'or'Направление по прямой · дорожный GPS выключен';return
 end
 if not self.env.path or self.env.path.verified~=true or self.suspended then self.status=self.suspended or'Дорожный GPS не проверен для этой сборки; выключен';return end
 if self.job then
  local job=self.job;local ok,done,points,distance,why=pcall(self.env.path.poll,self.env.path,job)
  if ok and not done then self.status=self.env.path.phase=='loading'and self.env.path.status or'Построение маршрута PA';return end
  self.job=nil;self.searching=false;self.env.path:cancel(job)
  if self.jobGeneration~=self.generation or self.jobSerial~=p.serial then return end
  self:acceptPath(ok and done,points,distance,now,cfg,why);return
 end
 if self.searching or self.negativeUntil and now<self.negativeUntil then return end
 if self.searchAt and now-self.searchAt<cfg.recalculate_ms then return end
 if self.searchPos and M.distance(pos,self.searchPos)<cfg.movement and self.route then return end
 self.searching=true;self.searchAt=now;self.searchPos=copy(pos)
 local generation,serial=self.generation,p.serial
 if self.env.path.asynchronous then
  local ok,job=pcall(self.env.path.begin,self.env.path,copy(pos),copy(p),cfg.road_snap)
  if ok and job then self.job=job;self.jobGeneration=generation;self.jobSerial=serial;self.status='Построение маршрута PA'
  else self.searching=false;self:acceptPath(false,nil,nil,now,cfg,'Не удалось запустить поиск маршрута')end
  return
 end
 local start=self.env.clock and self.env.clock()or now
 local ok,points,distance=pcall(self.env.path.find,self.env.path,copy(pos),copy(p))
 local elapsed=self.env.clock and self.env.clock()-start or 0
 self.searching=false
 if generation~=self.generation or not self.active or self.active.serial~=serial then return end
 if elapsed>8 then self.slow=(self.slow or 0)+1;if self.slow>=2 then self.suspended='Дорожный GPS приостановлен: медленные native-вызовы';self.route=nil;return end end
 self:acceptPath(ok,points,distance,now,cfg)
end
function N:invalidatePath()
 if self.job and self.env.path and self.env.path.cancel then self.env.path:cancel(self.job)end
 self.job=nil;self.searching=false;self.route=nil;self.routeDistance=nil;self.searchAt=nil;self.searchPos=nil;self.negativeUntil=nil
 self.revision=self.revision+1
end
function N:tick(s,now,cfg)
 if not core.finite(now)then return end
 if self.session~=s.session or self.lastNow and now<self.lastNow then self:reset(s.session)end;self.lastNow=now
 if not cfg.enabled or not s.session or s.interior~=0 then
  if self.active or next(self.sources)then self:reset(s.session)end;self.status='Навигация выключена / интерьер';return
 end
 self:choose(now);self:calculate(s,now,cfg)
end
function N:view()
 -- Routes are immutable after validation/replacement. Consumers simplify into
 -- their own bounded drawing snapshot, so unchanged paths are not copied again.
 local resumable=false;for _,p in pairs(self.sources)do if p.suppressed then resumable=true;break end end
 return {target=copy(self.active),points=self.route,revision=self.revision,distance=self.distance,distanceKind=self.distanceKind,status=self.status,resumable=resumable}
end
return M
