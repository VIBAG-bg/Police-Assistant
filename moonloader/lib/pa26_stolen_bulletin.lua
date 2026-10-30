-- Bounded server-bulletin observations, shared by native and CEF chat.
local core=require 'pa26_core';local model=require 'pa26_bindings';local grid=require 'pa26_map_grid'
local M={};local B={};B.__index=B;local zoneIndex
local function clean(s)return(s:match('^%s*(.-)%s*$'):gsub('[%.]+$',''))end
local function field(s)return type(s)=='string'and #s<=256 and core.validUtf8(s)and s:match('%S')and not s:find('[%c{}]')end
function M.zone(name)
 if not field(name)then return end
 local key=model.casefold(clean(name))
 if not zoneIndex then zoneIndex={};for _,row in ipairs(require('pa26_zone_bounds'))do zoneIndex[model.casefold(row[1])]={name=row[1],x=row[2],y=row[3],west=row[4],south=row[5],east=row[6],north=row[7]}end end
 return zoneIndex[key]and model.copy(zoneIndex[key])
end
function M.parse(text)
 if type(text)~='string'or #text>2048 or text:find('%c')or not core.validUtf8(text)then return end
 local car,color,tail=text:match('^%[Внимание%]%s+Угнан транспорт%s+(.+)%s+%(Цвет:%s*(.-)%)%.?%s+Последний раз замечен в районе%s+(.+)$')
 if not car then return end
 local area,place=tail:match('^(.-)%s+%(([^()]*)%)%.?$');area=area or tail
 car=clean(car);color=clean(color);area=clean(area);place=place and clean(place)or''
 if not field(car)or not field(color)or not field(area)or place~=''and not field(place)or area:find('[():]')then return end
 return {model=car,color=color,area=area,place=place}
end
function M.new(settings)return setmetatable({settings=settings,serial=0},B)end
function B:observe(text,now)
 if not self.settings().stolen_enabled then return false end
 local row=M.parse(text);if not row then return false end
 if text==self.lastText and(core.elapsed(now,self.lastAt)or math.huge)<3000 then return false end
 self.serial=self.serial+1;row.at=now;row.revision=self.serial;row.source='server';self.data=row;self.lastText=text;self.lastAt=now;return true
end
function B:clear()self.data=nil;self.serial=self.serial+1 end
function B:correct(fields,now,revision)
 if type(fields)~='table'then return nil,'Проверьте поля ориентировки.'end
 if not self.settings().stolen_enabled or not self.data or revision~=self.data.revision then return nil,'Ориентировка изменилась. Откройте её заново.'end
 local age=core.elapsed(now,self.data.at);if not age or age>self.settings().stolen_ttl_ms then return nil,'Срок ориентировки истёк.'end
 local out=model.copy(self.data)
 for _,key in ipairs({'model','color','area','place'})do
  if fields[key]~=nil then if type(fields[key])~='string'then return nil,'Проверьте поле ориентировки: '..key end;local text=clean(fields[key]);if key=='place'and text==''then out[key]=''elseif not field(text)or text:find('[()]')then return nil,'Проверьте поле ориентировки: '..key else out[key]=text end end
 end
 self.serial=self.serial+1;out.revision=self.serial;out.source='manual';self.data=out;return true
end
function B:view(now,map)
 local cfg=self.settings();local row=self.data;local age=row and core.elapsed(now,row.at)
 if not cfg.stolen_enabled or not row or not age or age>cfg.stolen_ttl_ms then return nil end
 local out=model.copy(row);out.remaining=math.max(0,math.ceil((cfg.stolen_ttl_ms-age)/1000))
 local zone=M.zone(row.area);local cell=zone and map and grid.cell(map,zone.x,zone.y,0)
 if cfg.stolen_highlight and map and map.enabled then out.targetCell=cell;out.targetLabel=cell and('УГОН: '..row.area..' ['..cell.label..'] · район приблизительно')or nil end
 out.square=cell and cell.label or'';out.zone=zone;return out
end
function M.values(row)
 return {stolen_model=row and row.model or'',stolen_color=row and row.color or'',stolen_area=row and row.area or'',stolen_square=row and row.square or'',
  stolen_summary=row and(row.model..', цвет '..row.color)or'транспорта из полученной ориентировки',
  stolen_location=row and(row.area..(row.square~=''and(' ('..row.square..', район приблизительно)')or''))or'из полученной ориентировки'}
end
return M
