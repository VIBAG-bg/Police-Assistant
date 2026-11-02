-- Native presentation only. Font/atlas work happens once in OnInitialize.
-- Glyphs never modify widget IDs, source records, user text or outgoing messages.
local points=require 'pa26_icon_glyphs'
local M={enabled=true,points=points,glyphs={},available={}}
M.tones={normal={.21,.72,.79,1},safe={.33,.79,.58,1},warning={.89,.69,.35,1},
 info={.46,.60,.91,1},danger={.91,.49,.47,1},muted={.65,.73,.80,1}}
local function utf8(n)return string.char(224+math.floor(n/4096),128+math.floor(n/64)%64,128+n%64)end
for name,n in pairs(points)do M.glyphs[name]=utf8(n)end
M.sections={home='house',binds='keyboard',addons='sliders',partners='car-side',hints='circle-question',
 knowledge='book-open',stats='clipboard-list',settings='gear',updates='rotate'}
M.cards={radio='tower-broadcast',traffic='car-side',risk='car-burst',force='shield-halved',
 rights='scale-balanced',commands='keyboard',service='users',wanted='crosshairs',fines='gavel',catalog='file-lines'}
local actions={stop_order='bullhorn',pursuit='route',tire='triangle-exclamation',stop='clipboard-list',
 high_risk='car-burst',approach='magnifying-glass',risk_order='bullhorn',explain_stop='id-card',
 foot='route',explain_detention='scale-balanced',finish='flag-checkered',documents='id-card',
 select='car-side',wanted='crosshairs',fast_pt='crosshairs',fast_wanted='crosshairs',combat_wanted='crosshairs',pursuit_mark='crosshairs'}
local semanticRules={{'Сохран','floppy-disk'},{'Заверш','flag-checkered'},{'Начать','play'},{'Продолжить','play'},
  {'Пауза','pause'},{'Удалить','xmark'},{'Отмен','xmark'},
  {'Назад','arrow-left'},{'Все памятки','arrow-left'},{'Поиск','magnifying-glass'},{'Найти','magnifying-glass'},
  {'Розыск','crosshairs'},{'/su','crosshairs'},{'/pt','crosshairs'},{'Штраф','gavel'},{'Пеленгац','location-dot'},
  {'Настрой','gear'},{'Шаблон','pen'},{'Изменить','pen'},{'Редакт','pen'},{'Обнов','rotate'},
  {'Восстанов','rotate'},{'Патруль','car-side'},{'Трафик','car-side'},{'Экипаж','users'},
  {'Напарник','users'},{'Контакт','users'},{'Рация','tower-broadcast'},{'Мегафон','bullhorn'},
  {'Доклад','clipboard-list'},{'База знаний','book-open'},{'Памят','book-open'},{'Помощь','circle-question'}}
local function semantic(label)
 label=tostring(label or'')
 if label:find('##copilot-fast-pt',1,true)then return 'crosshairs'end
 if label:match('^НЕТ')then return 'xmark'elseif label:match('^ДА')then return 'check'end
 local action=label:match('##copilot%-([a-z_]+)$');if action and actions[action]then return actions[action]end
 local section=label:match('##nav([a-z]+)$');if section then return M.sections[section]end
 if label:find('##important%-open%-')then return 'book-open'end
 if label:find('##copilot%-dispatch%-')or label:find('##copilot%-quick%-')then return 'tower-broadcast'end
 if label:find('##session%-crew%-')then return end -- ordinary fields remain quiet
 label=label:match('^(.-)##')or label

 for _,r in ipairs(semanticRules)do if label:find(r[1],1,true)then return r[2]end end
end
local cache,cacheCount={},0
function M.semantic(label)
 label=tostring(label or'')
 local found=cache[label];if found~=nil then return found or nil end
 found=semantic(label);if cacheCount>=512 then cache={};cacheCount=0 end
 cache[label]=found or false;cacheCount=cacheCount+1;return found
end
function M.setEnabled(value)M.enabled=value~=false end
function M.clear()
 M.font=nil;M.owner=nil;M.available={};M.buffer=nil;M.ranges=nil;M.config=nil;M.mode=nil
end
function M.initialize(im,ffi,base)
 M.clear()
 local ok,why=pcall(function()
  local carrier=require 'pa26_icon_font'
  assert(#carrier.data==426112 and carrier.data:sub(1,4)=='\0\1\0\0','Invalid bundled icon font')
  local cfg=im.ImFontConfig();cfg.FontDataOwnedByAtlas=false;cfg.PixelSnapH=true
  cfg.OversampleH=2;cfg.OversampleV=1
  cfg.MergeMode=base~=nil;if base~=nil then cfg.DstFont=base end
  local sorted={};for _,n in pairs(points)do sorted[#sorted+1]=n end;table.sort(sorted)
  local ranges=ffi.new('unsigned short[?]',#sorted*2+1)
  for i,n in ipairs(sorted)do ranges[(i-1)*2]=n;ranges[(i-1)*2+1]=n end
  local buffer=ffi.new('unsigned char[?]',#carrier.data);ffi.copy(buffer,carrier.data,#carrier.data)
  local font=im.GetIO().Fonts:AddFontFromMemoryTTF(buffer,#carrier.data,18,cfg,ranges)
  assert(font~=nil,'Icon font could not be loaded')
  M.font=font;M.owner=im;M.buffer=buffer;M.ranges=ranges;M.config=cfg;M.mode=base and'merged'or'dedicated'
 end)
 if not ok then M.clear();return nil,tostring(why)end
 return true
end
function M.get(name)
 if not M.enabled or not M.font or not points[name]then return end
 local known=M.available[name]
 if known==nil then
  local ok,glyph=pcall(function()return M.font:FindGlyphNoFallback(points[name])end)
  known=ok and glyph~=nil;M.available[name]=known
 end
 return known and M.glyphs[name]or nil
end
function M.draw(im,name,x,y,size,tone,alpha,drawList)
 if M.owner~=im then return false end
 local glyph=M.get(name);if not glyph then return false end
 local t=M.tones[tone]or M.tones.normal
 local color=im.ColorConvertFloat4ToU32(im.ImVec4(t[1],t[2],t[3],(alpha or 1)*t[4]))
 local list=drawList or im.GetWindowDrawList()
 list:AddTextFontPtr(M.font,size,im.ImVec2(x,y),color,glyph,nil,0)
 return true
end
function M.heading(im,ui,text,name,tone)
 local size=im.GetFontSize();local p=im.GetCursorScreenPos();local width=im.GetContentRegionAvail().x
 local gutter=math.min(size,20)+9
 if width>=180 and M.draw(im,name or M.semantic(text),p.x,p.y+math.max(0,(size-18)/2),math.min(size,20),tone)then
  im.SetCursorPosX(im.GetCursorPosX()+gutter);ui.text(text)
 else ui.text(text)end
end
return M
