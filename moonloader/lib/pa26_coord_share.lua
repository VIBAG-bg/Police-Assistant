-- Received messages only; never called by CEF editing events. Untrusted origins
-- remain explicitly unverified. One offer, fixed cache, no automatic commands.
local core=require 'pa26_core';local grid=require 'pa26_map_grid';local M={};local C={};C.__index=C
local marker='Мои координаты:'
function M.point(p)
 return type(p)=='table'and core.finite(p.x)and core.finite(p.y)and core.finite(p.z or 0)and
  math.abs(p.x)<=6000 and math.abs(p.y)<=6000 and math.abs(p.z or 0)<=3000
end
function M.distance(a,b)return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)end
function M.drawMarker(im,view,target,opacity)
 local x,y=grid.project(view,target.x,target.y)
 if not grid.inside(view,x,y,8)then return false end
 local list=im.GetBackgroundDrawList()
 local position=im.ImVec2(x,y)
 local shadow=im.ColorConvertFloat4ToU32(im.ImVec4(0,0,0,opacity))
 local color=im.ColorConvertFloat4ToU32(im.ImVec4(1,.65,.12,opacity))
 list:AddCircle(position,6,shadow,12,4)
 list:AddCircle(position,6,color,12,2)
 return true
end
function M.parse(text)
 if type(text)~='string'or #text>2048 or not core.validUtf8(text)or text:find('%c')or text:match('^%s*[/@]')then return end
 local first,last=text:find(marker,1,true);if not first then return end
 if text:find(marker,last+1,true)then return end
 local body=text:sub(last+1):match('^%s*(.-)%s*$')
 if body:find(',[^ ]')then return end
 -- Decimal dots and signed integers; comma separators are allowed only with
 -- whitespace. Ambiguous decimal commas are rejected rather than guessed.
 local xs,ys,zs,tail=body:match('^([+-]?%d+%.?%d*)[, ]+%s*([+-]?%d+%.?%d*)[, ]+%s*([+-]?%d+%.?%d*)(.*)$')
 if not xs then xs,ys,tail=body:match('^([+-]?%d+%.?%d*)[, ]+%s*([+-]?%d+%.?%d*)(.*)$')end
 if not xs or #xs>16 or #ys>16 or zs and #zs>16 then return end
 if tail~=''and not tail:match('^%s*%([^()]*%)%s*$')then return end
 if tail:find('[\r\n/;]')or tail:find('0[xX]')then return end
 local p={x=tonumber(xs),y=tonumber(ys),z=zs and tonumber(zs)or 0,height_unknown=not zs}
 if not M.point(p)then return end
 -- Never use numbers from timestamps, IDs or a label as coordinates.
 local prefix=text:sub(1,first-1)
 p.sender='Отправитель не подтверждён';p.sender_verified=false;p.description=tail:match('^%s*%((.-)%)%s*$')
 p.origin=prefix:match('^%[([RF]N?)%]')or'не подтверждён';p.label='OOC-координаты'
 return p
end
function M.format(s,cfg,codec,area,square)
 if not M.point(s)or not core.finite(s.z)or s.interior~=0 then return nil,'Координаты доступны снаружи в подтверждённой игровой сцене.'end
 local channel=cfg.channel;local key=channel and channel:sub(2)..'_verified'
 if not cfg[key]then return nil,'Формат '..tostring(channel)..' ещё не подтверждён. Проверьте его в настройках.'end
 local phone=''
 if channel=='/sms'then if not cfg.phone:match('^%d%d%d%d%d%d?%d?%d?%d?%d?$')then return nil,'Укажите номер телефона: 5–10 цифр.'end;phone=cfg.phone..' 'end
 local payload=string.format('Мои координаты: %.0f %.0f %.0f',s.x,s.y,s.z)
 local clean=type(area)=='string'and area:gsub('[%c()/;]','')or''
 if clean~=''then payload=payload..' ('..clean..(square and', квадрат '..square or'')..')'end
 if channel=='/sms'then payload='(( '..payload..' ))'end
 local line=channel..' '..phone..payload;local wire,why=core.encodeWire(line,codec)
 if not wire then return nil,why end;return {line=line,wire=wire}
end
function M.new(env)return setmetatable({env=env,cache={},order={},serial=0},C)end
function C:reset()self.offer=nil;self.cache={};self.order={};self.accepted=nil;self.mark=nil;self.serial=self.serial+1;self.lastOffer=nil end
function C:observe(text,now,s,cfg)
 if not cfg.enabled or not cfg.observe or not s.session then return false end
 local p=M.parse(text);if not p then return false end
 -- Exact local echo only when both origin format and nickname are known. A
 -- matching anonymous payload is merely deduplicated, never authenticated.
 if s.my_nick and text:find(s.my_nick,1,true)and text:match('^%[[RF]N?%]')then return false end
 local key=table.concat({p.x,p.y,p.z,p.origin},':');local previous=self.cache[key]
 if previous and now-previous<5000 or self.lastOffer and now-self.lastOffer<3000 then return false end
 self.cache[key]=now;self.order[#self.order+1]=key
 if #self.order>32 then local old=table.remove(self.order,1);if old~=key then self.cache[old]=nil end end
 if self.offer then return false end
 self.serial=self.serial+1;self.lastOffer=now
 p.at=now;p.token='coordinates:'..self.serial;p.session=s.session;p.ped=s.ped;p.serial=self.serial;p.duration=cfg.offer_ms
 self.offer=p;return true
end
function C:tick(s,now,cfg,arrival)
 self.state=s;self.now=now;self.cfg=cfg
 local p=self.offer
 if not cfg.enabled or p and(p.session~=s.session or p.ped~=s.ped or now<p.at or now-p.at>=cfg.offer_ms)then self.offer=nil end
 local accepted=self.accepted;self.accepted=nil
 if not cfg.enabled or not s.session or s.interior~=0 then self.mark=nil;return end
 if accepted and accepted.session==s.session and accepted.ped==s.ped then
  accepted.expires=now+cfg.ttl_ms
  self.mark=accepted
 end
 local mark=self.mark
 if mark and(mark.session~=s.session or mark.ped~=s.ped or now>=mark.expires or
  cfg.arrival_clear and not mark.height_unknown and
  core.finite(s.z)and math.abs(s.z-mark.z)<8 and M.point(s)and M.distance(s,mark)<(arrival or 15))then
  self.mark=nil
 end
end
function C:shown(token)if self.offer and self.offer.token==token then self.offer.seen=true end end
function C:decide(token,yes)
 local p=self.offer;if type(yes)~='boolean'or not p or p.token~=token or not p.seen or not require('pa26_notifications').safe(self.state)then return false end
 self.offer=nil
 if yes then self.accepted=p end;return true
end
function C:candidates()
 local p=self.offer;if not p then return{}end
 local detail=string.format('X %.0f · Y %.0f · Z %s',p.x,p.y,p.height_unknown and'не известна'or string.format('%.0f',p.z))
 if p.description then detail=detail..' · '..p.description end
 if M.point(self.state)then detail=detail..string.format(' · %.0f м по прямой',M.distance(p,self.state))end
 return {{owner='coordinates',token=p.token,mode='confirm',title='OOC-координаты · поставить метку?',
  body=p.sender..' · это OOC, не IC-сведения.\n'..detail..'\nPA поставит временную метку. Штатная метка GTA сохранится.',
  hint='Y — принять · N — отклонить',status='Источник не удостоверен сервером',priority=5,serial=p.serial,full=true,
  remaining=math.max(0,p.duration-(self.now-p.at)),duration=p.duration,shortcut={key=0,ctrl=false,alt=false,shift=false}}}
end
return M
