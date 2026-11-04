-- A reference into existing notes. Cached plain text; no second note database.
local M={};local N={};N.__index=N
function M.new()return setmetatable({},N)end
function N:update(notes,cfg,revision)
 if self.revision==revision and self.id==cfg.note_id and self.enabled==cfg.enabled then return self.note end
 self.revision=revision;self.id=cfg.note_id;self.enabled=cfg.enabled;self.note=nil
 if cfg.enabled then for _,n in ipairs(notes or{})do if n.id==cfg.note_id then
  self.note={id=n.id,title=n.name,text=n.body};break
 end end end;return self.note
end
function M.geometry(cfg,w,h)
 local width=math.min(w-16,math.max(math.min(220,w-16),w*cfg.width))
 local height=math.min(h-16,math.max(math.min(100,h-16),h*cfg.height))
 return {x=math.min(math.max(8,w*cfg.x),w-width-8),y=math.min(math.max(8,h*cfg.y),h-height-8),w=width,h=height}
end
function N:draw(im,cfg,w,h,editing)
 local n=self.note;if not n then return end
 local g=M.geometry(cfg,w,h);local flags=im.WindowFlags.NoSavedSettings+im.WindowFlags.NoFocusOnAppearing
 if not editing then flags=flags+im.WindowFlags.NoInputs+im.WindowFlags.NoMove+im.WindowFlags.NoResize end
 flags=flags+(im.WindowFlags.NoNav or 0)
 im.SetNextWindowPos(im.ImVec2(g.x,g.y),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(g.w,g.h),im.Cond.Always)
 im.SetNextWindowBgAlpha(cfg.opacity)
 if im.Begin('Памятка · '..n.title..'###pa45-pinned',nil,flags)then
  local font=im.GetFont();local size=tonumber(font.FontSize)*cfg.font_scale
  local key=tostring(font)..':'..size..':'..g.w..':'..self.revision
  if self.wrapKey~=key then self.wrapped=require('pa26_menu').labelLayout(font,size,g.w-32,n.text);self.wrapKey=key end
  local origin=im.GetCursorScreenPos();local list=im.GetWindowDrawList()
  local tint=im.ColorConvertFloat4ToU32(im.ImVec4(1,1,1,1));local visible=math.max(1,math.floor((g.h-48)/size))
  for i=1,math.min(#self.wrapped.lines,visible)do list:AddTextFontPtr(font,size,im.ImVec2(origin.x,origin.y+(i-1)*size),tint,self.wrapped.lines[i].text)end
  if #self.wrapped.lines>visible then list:AddTextFontPtr(font,size,im.ImVec2(origin.x,origin.y+visible*size),tint,'… Полный текст: F9 → Памятки')end
  im.End()
 else im.End()end
end
return M
