-- Real installed x86 ImGui, isolated Lua state; no GTA process or personal writes.
local source=debug.getinfo(1,'S').source:sub(2):gsub('\\','/');local root=assert(source:match('^(.*[/])'))..'../'
local game=os.getenv('LOCALAPPDATA')..'/Exsellent Launcher/game/'
getWorkingDirectory=function()return game..'MoonLoader'end
package.path=root..'moonloader/lib/?.lua;'..game..'MoonLoader/lib/?.lua;'..package.path;package.cpath=game..'MoonLoader/lib/?.dll;'..package.cpath
local ffi=require 'ffi';local im=require 'mimgui.imgui'
for field,prefix in pairs{HoveredFlags='ImGuiHoveredFlags_',Cond='ImGuiCond_',WindowFlags='ImGuiWindowFlags_',Col='ImGuiCol_',StyleVar='ImGuiStyleVar_',MouseCursor='ImGuiMouseCursor_',InputTextFlags='ImGuiInputTextFlags_',DrawCornerFlags='ImDrawCornerFlags_'}do im[field]=setmetatable({},{__index=function(_,key)return im.lib[prefix..key]end})end
im.new={char=setmetatable({},{__index=function(_,n)return ffi.typeof('char['..n..']')end}),int=function(v)return ffi.new('int[1]',v)end,float=function(v)return ffi.new('float[1]',v)end,bool=function(v)return ffi.new('bool[1]',v)end}
local ctx=im.CreateContext(nil);local gui=im.GetIO();gui.IniFilename=nil;gui.LogFilename=nil;gui.DeltaTime=1/60
local fonts={};for _,size in ipairs({16,24})do fonts[size]=gui.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeui.ttf',size,nil,gui.Fonts:GetGlyphRangesCyrillic())end
local px,w,h=ffi.new('unsigned char*[1]'),ffi.new('int[1]'),ffi.new('int[1]');gui.Fonts:GetTexDataAsRGBA32(px,w,h,nil)
local json=require 'cjson';local file=assert(io.open(root..'moonloader/resource/pa26/knowledge-base.json','rb'));local data=json.decode(file:read('*a'));file:close()
local function strip(t)for k,v in pairs(t)do if v==json.null then t[k]=nil elseif type(v)=='table'then strip(v)end end end;strip(data)
local k=require('pa26_knowledge').new();k:activate(assert(require('pa26_knowledge').validate(data)))
local view=require('pa26_knowledge_ui').new(im,ffi,k);local model=require 'pa26_bindings';local menu=require 'pa26_menu'
local stack={};local ui={push=function(f)stack[#stack+1]=f end,finish=function()assert(table.remove(stack))()end,text=function(t)im.PushTextWrapPos(0);im.TextUnformatted(t);im.PopTextWrapPos()end}
local checks,frames=0,0;local phase='';local tileButtons={};local targetTile;local reached=0
local function check(v,why)checks=checks+1;assert(v,why)end
local original=im.Button
local originalChild=im.BeginChild
im.BeginChild=function(name,size,...)
 if targetTile and name=='##important-tile-'..targetTile then
  im.SetScrollY(math.max(0,im.GetCursorPosY()+size.y-im.GetWindowHeight()+12))
 end
 return originalChild(name,size,...)
end
im.Button=function(label,...)
 local result=original(label,...)
 if im.IsItemVisible()then
  local a,b=im.GetItemRectMin(),im.GetItemRectMax();local p,z=im.GetWindowPos(),im.GetWindowSize()
  check(a.x>=p.x-1 and b.x<=p.x+z.x+1,'Horizontal overflow '..phase..' '..label)
  if label:find('##important-open-',1,true)then
   check(a.y>=p.y and b.y<=p.y+z.y-8,'Tile button clipped '..phase..' '..label);tileButtons[label]=true
  end
 end
 return result
end
local cb={openWanted=function()error('Unexpected send/navigation')end,openCaseGround=function()error('Unexpected action')end}
local function frame(screen,ratio,size,card,tab,scroll)
 gui.DisplaySize=im.ImVec2(screen[1],screen[2]);view.buttonFont=fonts[size];view.headingFont=fonts[size]
 view.importantView={card=card,tab=tab,query='',page=1,expanded={}}
 im.NewFrame();im.PushFont(fonts[size]);local bounds=menu.windowBounds(screen[1],screen[2],'main',ratio*100)
 local layout=menu.layout(bounds.width,bounds.height)
 local ww,hh=math.max(80,layout.w-12),math.max(80,layout.bodyH-12)
 im.SetNextWindowPos(im.ImVec2(4,4),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(ww,hh),im.Cond.Always)
 im.Begin('important-dashboard',nil,im.WindowFlags.NoSavedSettings+im.WindowFlags.NoDecoration)
 view:draw(ui,cb);check(#stack==0,'Unbalanced dashboard scopes '..phase)
 im.End();im.PopFont();im.Render();frames=frames+1
end
for _,screen in ipairs({{640,480},{800,600},{1024,768},{1152,864},{1366,768},{1920,1080},{2560,1440}})do
 for _,ratio in ipairs({.70,1})do for _,size in ipairs({16,24})do
  phase=screen[1]..'x'..screen[2]..' '..ratio..' font '..size
  k.personal.view.top_tab='important'
  for n=1,3 do frame(screen,ratio,size)end
  for _,card in ipairs(k.important.cards)do
   targetTile=card.id
   for n=1,4 do frame(screen,ratio,size)end
   check(tileButtons['Открыть памятку##important-open-'..card.id],'Tile button unreachable '..phase..' '..card.id)
   reached=reached+1
   tileButtons={}
  end
  targetTile=nil
  for _,card in ipairs(k.important.cards)do for _,section in ipairs(card.sections)do
   for n=1,2 do frame(screen,ratio,size,card.id,section.id)end
  end end
  k.personal.view.top_tab='registry';for n=1,2 do frame(screen,ratio,size)end
 end end
end
check(reached==280,'Every tile must be reachable in all 28 viewport/font combinations')
local out=assert(io.open(root..'tests/IMPORTANT_NATIVE32_RESULTS.json','wb'))
out:write(json.encode{status='passed',checks=checks,frames=frames,screen_count=7,font_sizes={16,24},window_percent={70,100},game_written=false});out:close()
print('Important native32: '..checks..' checks, '..frames..' frames passed')
im.DestroyContext(ctx)
