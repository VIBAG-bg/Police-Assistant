-- Actual x86 ImGui window constraints and default navigation, without GTA/D3D.
local src=debug.getinfo(1,'S').source:sub(2):gsub('\\','/');local root=assert(src:match('^(.*)/tests/'))
local game=os.getenv('LOCALAPPDATA')..'/Exsellent Launcher/game/'
package.path=root..'/moonloader/lib/?.lua;'..game..'MoonLoader/lib/?.lua;'..package.path;package.cpath=game..'MoonLoader/lib/?.dll;'..package.cpath
getWorkingDirectory=function()return game..'MoonLoader'end
local ffi=require 'ffi';local im=require 'mimgui.imgui';local json=require 'cjson'
for name,prefix in pairs{HoveredFlags='ImGuiHoveredFlags_',Cond='ImGuiCond_',WindowFlags='ImGuiWindowFlags_',Col='ImGuiCol_',StyleVar='ImGuiStyleVar_',MouseCursor='ImGuiMouseCursor_',InputTextFlags='ImGuiInputTextFlags_'}do im[name]=setmetatable({},{__index=function(_,k)return im.lib[prefix..k]end})end
im.new={char=setmetatable({},{__index=function(_,n)return ffi.typeof('char['..n..']')end}),int=function(n)return ffi.new('int[1]',n)end,float=function(n)return ffi.new('float[1]',n)end,bool=function(n)return ffi.new('bool[1]',n)end}
local ctx=im.CreateContext(nil);local gui=im.GetIO();gui.IniFilename=nil;gui.LogFilename=nil;gui.DeltaTime=1/60
local body=gui.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeui.ttf',18,nil,gui.Fonts:GetGlyphRangesCyrillic())
local heading=gui.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeuib.ttf',24,nil,gui.Fonts:GetGlyphRangesCyrillic())
local button=gui.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeuib.ttf',18,nil,gui.Fonts:GetGlyphRangesCyrillic())
local small=gui.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeui.ttf',16,nil,gui.Fonts:GetGlyphRangesCyrillic())
gui.FontDefault=body;assert(require('pa26_icons').initialize(im,ffi,button))
local px,w,h=ffi.new('unsigned char*[1]'),ffi.new('int[1]'),ffi.new('int[1]');gui.Fonts:GetTexDataAsRGBA32(px,w,h,nil)
local menu=require 'pa26_menu';local geo=require 'pa26_geometry';local checks,frames=0,0
local function check(v,why)checks=checks+1;assert(v,why)end
local nav={};local original=im.Button
im.Button=function(label,...)
 local result=original(label,...)
 if label:find('##nav',1,true)then local a,b=im.GetItemRectMin(),im.GetItemRectMax();local p,s=im.GetWindowPos(),im.GetWindowSize();nav[#nav+1]={inside=a.y>=p.y-1 and b.y<=p.y+s.y+1,scroll=im.GetScrollMaxY()}end
 return result
end
local displays={{640,480},{800,600},{1152,864},{1366,768},{1920,1080},{2560,1440},{3440,1440},{800,1100}}
for _,display in ipairs(displays)do for _,scale in ipairs({1,1.25})do for key in pairs(geo.windows)do
 gui.DisplaySize=im.ImVec2(display[1],display[2]);gui.FontGlobalScale=scale;local m=menu.new()
 for pass=1,3 do
  nav={};im.NewFrame();check(m:prepareWindow(im,key));local stack={}
  local ui={push=function(fn)stack[#stack+1]=fn end,finish=function()assert(table.remove(stack))()end,text=function(t)im.PushTextWrapPos(0);im.TextUnformatted(t);im.PopTextWrapPos()end}
  m:pushTheme(im,ui);im.Begin('Geometry '..key..display[1],nil,im.WindowFlags.NoTitleBar+im.WindowFlags.NoSavedSettings+im.WindowFlags.NoResize+im.WindowFlags.NoMove)
  m:resizeWindow(im,ui,key)
  local p,s=im.GetWindowPos(),im.GetWindowSize();check(p.x>=15 and p.y>=15);check(p.x+s.x<=display[1]-15 and p.y+s.y<=display[2]-15)
  if key=='main'then
   m:draw(im,ui,{connected=true,nickname='Officer_Demo',id=37,ping=42,menuKey='F9'},
    {actions=function()end,updates=function()end,openAssist=function()end,openPatrol=function()end,openSettings=function()end,finishWork=function()end},
    {heading=heading,brand=heading,button=button,compact=button,small=small})
   if pass==3 and scale==1 and display[1]>=1152 and display[2]>=768 then
    check(#nav==8);for _,row in ipairs(nav)do check(row.inside and row.scroll<=1,'Navigation is clipped on '..display[1]..'x'..display[2])end
   end
  end
  im.End();while #stack>0 do ui.finish()end;im.Render();frames=frames+1
  if pass==2 then m:recoverWindowPositions()end
 end
end end end
require('pa26_icons').clear();im.DestroyContext(ctx)
local f=assert(io.open(root..'/tests/GEOMETRY_NATIVE32_0440.json','wb'));f:write(json.encode({status='passed',checks=checks,frames=frames,displays=displays,font_scales={1,1.25},windows=8,synthetic=true,game_started=false}));f:close()
print('Responsive native geometry: '..checks..' checks; '..frames..' frames.')
